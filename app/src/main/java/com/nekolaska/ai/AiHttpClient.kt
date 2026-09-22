package com.nekolaska.ai

import android.annotation.SuppressLint
import com.androlua.LuaActivity
import com.nekolaska.ktx.toLuaValue
import okhttp3.Call
import okhttp3.Headers
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONArray
import org.json.JSONObject
import org.luaj.LuaFunction
import org.luaj.LuaString
import org.luaj.LuaValue
import org.luaj.LuaValue.FALSE
import org.luaj.LuaValue.NIL
import org.luaj.LuaValue.TRUE
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

private fun OkHttpClient.Builder.withAiTimeout(timeout: Long) =
    callTimeout(timeout, TimeUnit.SECONDS)
        .connectTimeout(timeout, TimeUnit.SECONDS)
        .readTimeout(timeout, TimeUnit.SECONDS)
        .writeTimeout(timeout, TimeUnit.SECONDS)

/** Dedicated transport for agent model requests. It is intentionally separate
 * from LuaJ's general-purpose HTTP surface in org.luaj.android.okhttp. */
class AiHttpClient @JvmOverloads constructor(
    private val activity: LuaActivity,
    private val client: OkHttpClient = OkHttpClient.Builder().withAiTimeout(120).build()
) {
    @Volatile
    private var currentStreamCall: Call? = null

    val unsafe by lazy {
        val trustAllCerts = arrayOf<TrustManager>(
            @SuppressLint("CustomX509TrustManager")
            object : X509TrustManager {
                @SuppressLint("TrustAllX509TrustManager")
                override fun checkClientTrusted(
                    chain: Array<out java.security.cert.X509Certificate>?,
                    authType: String?
                ) = Unit

                @SuppressLint("TrustAllX509TrustManager")
                override fun checkServerTrusted(
                    chain: Array<out java.security.cert.X509Certificate>?,
                    authType: String?
                ) = Unit

                override fun getAcceptedIssuers(): Array<out java.security.cert.X509Certificate> = arrayOf()
            }
        )
        AiHttpClient(
            activity,
            OkHttpClient.Builder().apply {
                withAiTimeout(120)
                sslSocketFactory(
                    SSLContext.getInstance("SSL").apply {
                        init(null, trustAllCerts, java.security.SecureRandom())
                    }.socketFactory,
                    trustAllCerts[0] as X509TrustManager
                )
                hostnameVerifier { _, _ -> true }
            }.build()
        )
    }

    fun cancelAll() {
        currentStreamCall?.cancel()
    }

    fun get(
        url: String,
        headers: Map<String, String>? = null,
        callback: LuaFunction
    ) {
        val call = client.newCall(
            Request.Builder()
                .url(url)
                .get()
                .headers(headerList(headers))
                .build()
        )
        deliver(call, callback)
    }

    fun postJson(
        url: String,
        body: String,
        headers: Map<String, String>? = null,
        callback: LuaFunction
    ) {
        deliver(client.newCall(request(url, body, headers)), callback)
    }

    fun postJsonStream(
        url: String,
        body: String,
        headers: Map<String, String>? = null,
        onChunk: LuaFunction,
        onDone: LuaFunction
    ) {
        val call = client.newCall(request(url, body, headers))
        currentStreamCall = call
        call.enqueue(object : okhttp3.Callback {
            override fun onFailure(call: Call, e: java.io.IOException) {
                if (currentStreamCall === call) currentStreamCall = null
                finishError(onDone, "ERROR: ${e.message ?: "Network error"}")
            }

            override fun onResponse(call: Call, response: Response) {
                try {
                    if (!response.isSuccessful) {
                        val code = response.code
                        val text = response.body.string()
                        finishError(onDone, "HTTP $code", text)
                        return
                    }
                    streamResponse(response, onChunk, onDone)
                } catch (error: Exception) {
                    finishError(onDone, "ERROR: ${error.message ?: "Stream error"}")
                } finally {
                    response.close()
                    if (currentStreamCall === call) currentStreamCall = null
                }
            }
        })
    }

    private fun headerList(headers: Map<String, String>?) =
        Headers.Builder().apply {
            headers?.forEach { (name, value) -> add(name, value) }
        }.build()

    private fun deliver(call: Call, callback: LuaFunction) {
        call.enqueue(object : okhttp3.Callback {
            override fun onFailure(call: Call, e: java.io.IOException) {
                activity.runOnUiThread {
                    runCatching { callback.call(LuaString.valueOf("ERROR: ${e.message ?: "Network error"}")) }
                        .onFailure { activity.sendMsg("AI network callback: ${it.message}") }
                }
            }

            override fun onResponse(call: Call, response: Response) {
                response.use {
                    val code = response.code
                    val text = response.body.string()
                    activity.runOnUiThread {
                        runCatching { callback.call(code.toLuaValue(), text.toLuaValue()) }
                            .onFailure { activity.sendMsg("AI network callback: ${it.message}") }
                    }
                }
            }
        })
    }

    private fun request(url: String, body: String, headers: Map<String, String>?): Request =
        Request.Builder()
            .url(url)
            .post(body.toRequestBody("application/json; charset=utf-8".toMediaTypeOrNull()))
            .headers(headerList(headers))
            .build()

    private fun finishError(onDone: LuaFunction, text: String, detail: String? = null) {
        activity.runOnUiThread {
            runCatching {
                if (detail == null) onDone.call(LuaString.valueOf(text), NIL, TRUE)
                else onDone.call(LuaString.valueOf(text), LuaString.valueOf(detail), TRUE)
            }.onFailure { activity.sendMsg("AI stream callback: ${it.message}") }
        }
    }

    private fun streamResponse(response: Response, onChunk: LuaFunction, onDone: LuaFunction) {
        val fullText = StringBuilder()
        val reasoningText = StringBuilder()
        var incomplete = false
        val chatCalls = mutableMapOf<Int, JSONObject>()
        val responsesState = ResponsesStreamState()

        fun valueOfJson(value: Any?): String = when (value) {
            null, JSONObject.NULL -> ""
            is String -> value
            else -> value.toString()
        }
        fun putNonEmpty(accumulator: JSONObject, key: String, value: Any?) {
            val value = valueOfJson(value)
            val next = keepExistingWhenBlank(accumulator.optString(key, ""), value)
            if (next.isNotEmpty()) accumulator.put(key, next)
        }
        fun outputIndex(event: JSONObject): Int? =
            if (event.has("output_index") && !event.isNull("output_index")) event.optInt("output_index") else null
        fun recordOutput(event: JSONObject, item: JSONObject) {
            responsesState.recordOutput(outputIndex(event), item.optString("id", ""), item.toString())
            if (item.optString("type") == "function_call") {
                responsesState.observeFunctionCall(
                    item.optString("call_id", ""),
                    item.optString("id", ""),
                    outputIndex(event),
                    item.optString("name", ""),
                    if (item.has("arguments")) item.optString("arguments", "") else null
                )
            }
        }
        fun completeResponseCall(event: JSONObject, item: JSONObject) {
            if (item.optString("type") != "function_call") return
            responsesState.completeFunctionCall(
                item.optString("call_id", ""),
                item.optString("id", ""),
                outputIndex(event),
                item.optString("name", ""),
                if (item.has("arguments")) item.optString("arguments", "") else null
            )
        }
        fun appendChatCall(call: JSONObject, fallbackIndex: Int) {
            val index = call.optInt("index", fallbackIndex)
            val accumulator = chatCalls[index] ?: JSONObject().also { chatCalls[index] = it }
            if (call.has("id") && !call.isNull("id")) putNonEmpty(accumulator, "id", call.opt("id"))
            if (call.has("name") && !call.isNull("name")) putNonEmpty(accumulator, "name", call.opt("name"))
            call.optJSONObject("function")?.let { function ->
                if (function.has("name") && !function.isNull("name")) putNonEmpty(accumulator, "name", function.opt("name"))
                if (function.has("arguments") && !function.isNull("arguments")) {
                    accumulator.put("arguments", accumulator.optString("arguments", "") + valueOfJson(function.opt("arguments")))
                }
            }
        }
        fun appendText(text: String) {
            if (text.isEmpty()) return
            fullText.append(text)
            activity.runOnUiThread { runCatching { onChunk.call(LuaString.valueOf(text)) } }
        }
        fun appendCompletedText(output: JSONArray) {
            val completedText = StringBuilder()
            for (index in 0 until output.length()) {
                val item = output.optJSONObject(index) ?: continue
                if (item.optString("type") != "message") continue
                val content = item.optJSONArray("content") ?: continue
                for (contentIndex in 0 until content.length()) {
                    val part = content.optJSONObject(contentIndex) ?: continue
                    if (part.optString("type") == "output_text") {
                        completedText.append(part.optString("text", ""))
                    } else if (part.optString("type") == "refusal") {
                        completedText.append(part.optString("refusal", ""))
                    }
                }
            }
            val completed = completedText.toString()
            val streamed = fullText.toString()
            when {
                completed.isEmpty() -> Unit
                streamed.isEmpty() -> appendText(completed)
                completed.startsWith(streamed) -> appendText(completed.substring(streamed.length))
                streamed != completed -> {
                    // The completed response is authoritative when a relay sent
                    // duplicate or non-prefix text fragments while streaming.
                    fullText.setLength(0)
                    fullText.append(completed)
                }
            }
        }

        val source = response.body.source()
        while (true) {
            val line = source.readUtf8Line() ?: break
            val normalized = line.trimStart()
            if (!normalized.startsWith("data:")) continue
            val data = normalized.substring(5).trimStart()
            if (data == "[DONE]") break
            try {
                val json = JSONObject(data)
                val event = json.optString("type", json.optString("event", ""))
                if (event.startsWith("response.")) {
                    if (event == "response.failed") {
                        val error = json.optJSONObject("response")?.optJSONObject("error") ?: json.optJSONObject("error")
                        throw IllegalStateException(error?.optString("message", "Responses request failed") ?: "Responses request failed")
                    }
                    if (event == "response.incomplete") incomplete = true
                    when (event) {
                        "response.output_text.delta" -> appendText(json.optString("delta", ""))
                        "response.reasoning_text.delta",
                        "response.reasoning_summary_text.delta" -> reasoningText.append(json.optString("delta", ""))
                        "response.function_call_arguments.delta" -> responsesState.appendArguments(
                            json.optString("call_id", ""), json.optString("item_id", ""), outputIndex(json), json.optString("delta", "")
                        )
                        "response.function_call_arguments.done" -> responsesState.setArguments(
                            json.optString("call_id", ""), json.optString("item_id", ""), outputIndex(json),
                            if (json.has("arguments")) json.optString("arguments", "") else null
                        )
                        "response.output_item.added" -> json.optJSONObject("item")?.let { recordOutput(json, it) }
                        "response.output_item.done" -> json.optJSONObject("item")?.let {
                            recordOutput(json, it)
                            completeResponseCall(json, it)
                        }
                        "response.completed", "response.incomplete" -> {
                            json.optJSONObject("response")?.optJSONArray("output")?.let { output ->
                                val complete = ArrayList<String>()
                                for (index in 0 until output.length()) {
                                    output.optJSONObject(index)?.let { item ->
                                        complete.add(item.toString())
                                        val outputEvent = JSONObject().put("output_index", index)
                                        recordOutput(outputEvent, item)
                                        completeResponseCall(outputEvent, item)
                                    }
                                }
                                if (complete.isNotEmpty()) responsesState.setCompletedOutput(complete)
                                appendCompletedText(output)
                            }
                        }
                    }
                    continue
                }
                if (event == "error") {
                    val error = json.optJSONObject("error") ?: json
                    throw IllegalStateException(error.optString("message", "Stream request failed"))
                }
                val choices = json.optJSONArray("choices")
                if (choices == null || choices.length() == 0) continue
                val choice = choices.getJSONObject(0)
                val deltaCandidate = choice.optJSONObject("delta")
                val messageCandidate = choice.optJSONObject("message")
                val choiceHasToolPayload = choice.has("tool_calls") || choice.has("tool_call") || choice.has("function_call") || choice.has("name") || choice.has("arguments")
                val deltaHasToolPayload = deltaCandidate?.let { it.has("tool_calls") || it.has("tool_call") || it.has("function_call") || it.has("name") || it.has("arguments") } == true
                val messageHasToolPayload = messageCandidate?.let { it.has("tool_calls") || it.has("tool_call") || it.has("function_call") || it.has("name") || it.has("arguments") } == true
                val appendedDeltaContent = (messageHasToolPayload || choiceHasToolPayload)
                    && deltaCandidate != null && deltaCandidate.has("content") && !deltaCandidate.isNull("content")
                if (appendedDeltaContent) {
                    appendText(deltaCandidate.getString("content"))
                }
                val delta = when {
                    choiceHasToolPayload -> choice
                    deltaHasToolPayload -> deltaCandidate
                    messageHasToolPayload -> messageCandidate
                    deltaCandidate != null -> deltaCandidate
                    else -> messageCandidate
                } ?: continue
                if (delta.optJSONObject("function_call") != null) {
                    val accumulator = chatCalls[0] ?: JSONObject().also { chatCalls[0] = it }
                    accumulator.put("legacy_function_call", true)
                }
                if (delta.has("name") || delta.has("arguments")) {
                    val accumulator = chatCalls[0] ?: JSONObject().also { chatCalls[0] = it }
                    if (delta.has("name") && !delta.isNull("name")) putNonEmpty(accumulator, "name", delta.opt("name"))
                    if (delta.has("arguments") && !delta.isNull("arguments")) {
                        accumulator.put("arguments", accumulator.optString("arguments", "") + valueOfJson(delta.opt("arguments")))
                    }
                }
                if (delta.has("content") && !delta.isNull("content")
                    && !(appendedDeltaContent && delta === deltaCandidate)
                ) appendText(delta.getString("content"))
                val reasoning = when {
                    delta.has("reasoning_content") && !delta.isNull("reasoning_content") -> valueOfJson(delta.opt("reasoning_content"))
                    delta.has("reasoning") && !delta.isNull("reasoning") -> valueOfJson(delta.opt("reasoning"))
                    else -> ""
                }
                if (reasoning.isNotEmpty()) reasoningText.append(reasoning)
                delta.optJSONArray("tool_calls")?.let { calls ->
                    for (index in 0 until calls.length()) calls.optJSONObject(index)?.let { appendChatCall(it, index) }
                }
                delta.optJSONObject("tool_call")?.let { appendChatCall(it, it.optInt("index", 0)) }
                delta.optJSONObject("function_call")?.let { legacy ->
                    val accumulator = chatCalls[0] ?: JSONObject().also { chatCalls[0] = it }
                    accumulator.put("legacy_function_call", true)
                    if (legacy.has("name") && !legacy.isNull("name")) putNonEmpty(accumulator, "name", legacy.opt("name"))
                    if (legacy.has("arguments") && !legacy.isNull("arguments")) {
                        accumulator.put("arguments", accumulator.optString("arguments", "") + valueOfJson(legacy.opt("arguments")))
                    }
                }
            } catch (error: IllegalStateException) {
                throw error
            } catch (_: Exception) {
                // Ignore malformed intermediary SSE chunks from compatible relays.
            }
        }

        val toolCalls = JSONArray()
        for ((index, accumulator) in chatCalls.toSortedMap()) {
            val name = accumulator.optString("name", "").trim()
            if (name.isEmpty()) continue
            toolCalls.put(JSONObject().apply {
                put("id", accumulator.optString("id", "").ifEmpty { "call_$index" })
                put("name", name)
                put("arguments", accumulator.optString("arguments", ""))
                if (accumulator.optBoolean("legacy_function_call", false)) put("legacy_function_call", true)
                if (toolCalls.length() == 0 && reasoningText.isNotEmpty()) put("reasoning_content", reasoningText.toString())
            })
        }
        for (toolCall in responsesState.toolCalls()) {
            toolCalls.put(JSONObject().apply {
                put("id", toolCall.id)
                toolCall.itemId?.let { put("item_id", it) }
                put("name", toolCall.name)
                put("arguments", toolCall.arguments.ifEmpty { "{}" })
                if (toolCalls.length() == 0 && reasoningText.isNotEmpty()) put("reasoning_content", reasoningText.toString())
            })
        }
        val rawOutput = responsesState.responseOutput().joinToString(prefix = "[", postfix = "]", separator = ",").takeIf { it != "[]" }
        activity.runOnUiThread {
            runCatching {
                onDone.invoke(LuaValue.varargsOf(arrayOf(
                    LuaString.valueOf(fullText.toString()),
                    if (toolCalls.length() > 0) LuaString.valueOf(toolCalls.toString()) else NIL,
                    FALSE,
                    if (incomplete) TRUE else FALSE,
                    rawOutput?.let(LuaString::valueOf) ?: NIL,
                    reasoningText.toString().takeIf { it.isNotEmpty() }?.let(LuaString::valueOf) ?: NIL
                )))
            }.onFailure { activity.sendMsg("AI stream callback: ${it.message}") }
        }
    }
}
