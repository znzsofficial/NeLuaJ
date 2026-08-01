package org.luaj.android

import android.annotation.SuppressLint
import com.androlua.LuaActivity
import com.nekolaska.ktx.argAt
import com.nekolaska.ktx.asString
import com.nekolaska.ktx.firstArg
import com.nekolaska.ktx.ifNotNil
import com.nekolaska.ktx.isNotNil
import com.nekolaska.ktx.secondArg
import com.nekolaska.ktx.toLuaInstance
import com.nekolaska.ktx.toLuaValue
import okhttp3.Call
import okhttp3.FormBody
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONArray
import org.json.JSONObject
import org.luaj.Globals
import org.luaj.LuaFunction
import org.luaj.LuaString
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.LuaValue.NIL
import org.luaj.Varargs
import org.luaj.lib.TwoArgFunction
import org.luaj.lib.VarArgFunction
import kotlin.jvm.Volatile
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

private fun OkHttpClient.Builder.setTimeout(timeout: Long) =
    callTimeout(timeout, java.util.concurrent.TimeUnit.SECONDS)
        .connectTimeout(timeout, java.util.concurrent.TimeUnit.SECONDS)
        .readTimeout(timeout, java.util.concurrent.TimeUnit.SECONDS)
        .writeTimeout(timeout, java.util.concurrent.TimeUnit.SECONDS)

class AsyncOkHttp(
    private val context: LuaActivity,
    private val client: OkHttpClient = OkHttpClient.Builder().setTimeout(120).build()
) {
    @Volatile
    private var currentStreamCall: Call? = null

    /** 取消当前正在进行的流式请求（用于 AI 停止按钮）。 */
    fun cancelAll() {
        currentStreamCall?.cancel()
    }
    val unsafe by lazy {
        val trustAllCerts = arrayOf<TrustManager>(
            @SuppressLint("CustomX509TrustManager")
            object : X509TrustManager {
                @SuppressLint("TrustAllX509TrustManager")
                override fun checkClientTrusted(
                    chain: Array<out java.security.cert.X509Certificate>?,
                    authType: String?
                ) {
                }

                @SuppressLint("TrustAllX509TrustManager")
                override fun checkServerTrusted(
                    chain: Array<out java.security.cert.X509Certificate>?,
                    authType: String?
                ) {
                }

                override fun getAcceptedIssuers(): Array<out java.security.cert.X509Certificate> =
                    arrayOf()
            })

        AsyncOkHttp(
            context,
            OkHttpClient.Builder().apply {
                setTimeout(120)
                sslSocketFactory(SSLContext.getInstance("SSL").apply {
                    init(null, trustAllCerts, java.security.SecureRandom())
                }.socketFactory, trustAllCerts[0] as X509TrustManager)
                hostnameVerifier { hostname, session -> true } // 忽略主机名验证
            }.build()
        )
    }

    @JvmOverloads
    fun get(
        url: String,
        headers: Map<String, String>? = null,
        callback: LuaFunction
    ) =
        client.newCall(
            if (headers != null) {
                url.urlBuilder().headers(
                    okhttp3.Headers.Builder().apply {
                        for (i in headers.keys) add(i, headers[i] ?: "null")
                    }.build()
                ).build()
            } else {
                url.urlBuilder().build()
            }
        ).enqueueWithCallback(callback)

    @JvmOverloads
    fun postText(
        url: String,
        body: String,
        headers: Map<String, String>? = null,
        callback: LuaFunction
    ) =
        post(
            url,
            body.toRequestBody("text/plain; charset=utf-8".toMediaTypeOrNull()),
            headers,
            callback
        )

    @JvmOverloads
    fun postJson(
        url: String,
        body: String,
        headers: Map<String, String>? = null,
        callback: LuaFunction
    ) =
        post(
            url,
            body.toRequestBody("application/json; charset=utf-8".toMediaTypeOrNull()),
            headers,
            callback
        )

    private fun parseBody(body: String) =
        FormBody.Builder().apply {
            for (i in body.split("&")) {
                val split = i.split("=")
                add(split[0], split[1])
            }
        }.build()

    @JvmOverloads
    fun post(
        url: String,
        body: String,
        headers: Map<String, String>? = null,
        callback: LuaFunction
    ) = post(url, parseBody(body), headers, callback)

    fun post(
        url: String,
        body: RequestBody,
        headers: Map<String, String>?,
        callback: LuaFunction
    ) =
        client.newCall(
            if (headers != null) {
                url.urlBuilder()
                    .post(body)
                    .headers(
                        okhttp3.Headers.Builder().apply {
                            for (i in headers.keys) add(i, headers[i] ?: "null")
                        }.build()
                    ).build()
            } else
                url.urlBuilder().post(body).build()
        ).enqueueWithCallback(callback)

    private fun Call.enqueueWithCallback(callback: LuaFunction) =
        enqueue(object : okhttp3.Callback {
            override fun onFailure(call: Call, e: java.io.IOException) {
                context.runOnUiThread {
                    try {
                        callback.call(e.message)
                    } catch (e: Exception) {
                        context.sendMsg("网络请求失败，回调发生异常：${e.message}")
                    }
                }
            }

            override fun onResponse(call: Call, response: Response) {
                try {
                    val body = response.body.string()
                    val code = response.code
                    context.runOnUiThread {
                        runCatching {
                            callback.call(
                                code.toLuaValue(),
                                body.toLuaValue(),
                                response.toLuaInstance()
                            )
                        }.onFailure { context.sendMsg("回调发生异常：${it.message}") }
                    }
                } catch (e: Exception) {
                    context.sendMsg("网络请求发生异常：${e.message}")
                }
            }
        })

    @JvmOverloads
    fun postJsonStream(
        url: String,
        body: String,
        headers: Map<String, String>? = null,
        onChunk: LuaFunction,
        onDone: LuaFunction
    ) {
        val request = (if (headers != null) {
            url.urlBuilder()
                .post(body.toRequestBody("application/json; charset=utf-8".toMediaTypeOrNull()))
                .headers(
                    okhttp3.Headers.Builder().apply {
                        for (i in headers.keys) add(i, headers[i] ?: "null")
                    }.build()
                )
        } else {
            url.urlBuilder()
                .post(body.toRequestBody("application/json; charset=utf-8".toMediaTypeOrNull()))
        }).build()
        val call = client.newCall(request)
        currentStreamCall = call
        call.enqueue(object : okhttp3.Callback {
            override fun onFailure(call: Call, e: java.io.IOException) {
                if (currentStreamCall === call) currentStreamCall = null
                context.runOnUiThread {
                    try {
                        onDone.call(LuaString.valueOf("ERROR: " + (e.message ?: "Network error")))
                    } catch (e: Exception) {
                        context.sendMsg("Stream failure: ${e.message}")
                    }
                }
            }

            override fun onResponse(call: Call, response: Response) {
                if (currentStreamCall === call) currentStreamCall = null
                try {
                    if (!response.isSuccessful) {
                        val responseCode = response.code
                        val errBody = response.body.string()
                        response.close()
                        context.runOnUiThread {
                            try {
                                onDone.call(
                                    LuaString.valueOf("HTTP $responseCode"),
                                    LuaString.valueOf(errBody)
                                )
                            } catch (e: Exception) {
                                context.sendMsg("Stream callback: ${e.message}")
                            }
                        }
                        return
                    }
                    val source = response.body.source()
                    val fullText = StringBuilder()
                    val toolCallsArr = JSONArray()
                    val toolCallsMap = mutableMapOf<Int, JSONObject>()

                    while (true) {
                        val line = source.readUtf8Line() ?: break
                        val normalizedLine = line.trimStart()
                        if (!normalizedLine.startsWith("data:")) continue
                        val data = normalizedLine.substring(5).trimStart()
                        if (data == "[DONE]") break

                        try {
                            val json = JSONObject(data)
                            val choices = json.optJSONArray("choices")
                            if (choices == null || choices.length() == 0) continue
                            val choice = choices.getJSONObject(0)
                            // Streaming responses use delta. Some compatible
                            // providers put tool calls in message while delta
                            // only contains the visible text.
                            val deltaCandidate = choice.optJSONObject("delta")
                            val messageCandidate = choice.optJSONObject("message")
                            val deltaHasToolPayload = deltaCandidate?.let {
                                it.has("tool_calls") || it.has("tool_call") ||
                                    it.has("function_call") || it.has("name") ||
                                    it.has("arguments")
                            } == true
                            val messageHasToolPayload = messageCandidate?.let {
                                it.has("tool_calls") || it.has("tool_call") ||
                                    it.has("function_call") || it.has("name") ||
                                    it.has("arguments")
                            } == true
                            if (messageHasToolPayload && deltaCandidate != null &&
                                deltaCandidate.has("content") && !deltaCandidate.isNull("content")) {
                                val content = deltaCandidate.getString("content")
                                fullText.append(content)
                                context.runOnUiThread {
                                    try {
                                        onChunk.call(LuaString.valueOf(content))
                                    } catch (_: Exception) { }
                                }
                            }
                            val delta = if (deltaHasToolPayload || !messageHasToolPayload) {
                                deltaCandidate
                            } else {
                                messageCandidate
                            }
                            if (delta == null) continue

                            // A few providers flatten the function fields into delta.
                            if (delta.has("name") || delta.has("arguments")) {
                                val acc = toolCallsMap[0] ?: JSONObject().also {
                                    toolCallsMap[0] = it
                                }
                                if (delta.has("name") && !delta.isNull("name")) {
                                    acc.put("name", delta.getString("name"))
                                }
                                if (delta.has("arguments") && !delta.isNull("arguments")) {
                                    acc.put(
                                        "arguments",
                                        acc.optString("arguments", "") + delta.getString("arguments")
                                    )
                                }
                            }

                            // 文本内容
                            if (delta.has("content") && !delta.isNull("content")) {
                                val content = delta.getString("content")
                                fullText.append(content)
                                context.runOnUiThread {
                                    try {
                                        onChunk.call(LuaString.valueOf(content))
                                    } catch (_: Exception) { }
                                }
                            }

                            // 工具调用
                            val tcArray = delta.optJSONArray("tool_calls")
                            if (tcArray != null) {
                                for (i in 0 until tcArray.length()) {
                                    val tc = tcArray.getJSONObject(i)
                                    val idx = tc.optInt("index", i)
                                    var acc = toolCallsMap[idx]
                                    if (acc == null) {
                                        acc = JSONObject()
                                        toolCallsMap[idx] = acc
                                        acc.put("id", tc.optString("id", ""))
                                    }
                                    if (tc.has("id") && !tc.isNull("id")) {
                                        acc.put("id", tc.getString("id"))
                                    }
                                    if (tc.has("name") && !tc.isNull("name")) {
                                        acc.put("name", tc.getString("name"))
                                    }
                                    val func = tc.optJSONObject("function")
                                    if (func != null) {
                                        if (func.has("name") && !func.isNull("name")) {
                                            acc.put("name", func.getString("name"))
                                        }
                                        if (func.has("arguments") && !func.isNull("arguments")) {
                                            acc.put("arguments",
                                                acc.optString("arguments", "") + func.getString("arguments"))
                                        }
                                    }
                                }
                            }

                            val singleToolCall = delta.optJSONObject("tool_call")
                            if (singleToolCall != null) {
                                val acc = toolCallsMap[singleToolCall.optInt("index", 0)]
                                    ?: JSONObject().also {
                                        toolCallsMap[singleToolCall.optInt("index", 0)] = it
                                    }
                                if (singleToolCall.has("id") && !singleToolCall.isNull("id")) {
                                    acc.put("id", singleToolCall.getString("id"))
                                }
                                if (singleToolCall.has("name") && !singleToolCall.isNull("name")) {
                                    acc.put("name", singleToolCall.getString("name"))
                                }
                                val singleFunction = singleToolCall.optJSONObject("function")
                                if (singleFunction != null) {
                                    if (singleFunction.has("name") && !singleFunction.isNull("name")) {
                                        acc.put("name", singleFunction.getString("name"))
                                    }
                                    if (singleFunction.has("arguments") && !singleFunction.isNull("arguments")) {
                                        acc.put(
                                            "arguments",
                                            acc.optString("arguments", "") + singleFunction.getString("arguments")
                                        )
                                    }
                                }
                            }

                            // Older OpenAI-compatible APIs use function_call instead
                            // of tool_calls while streaming.
                            val legacyFunction = delta.optJSONObject("function_call")
                            if (legacyFunction != null) {
                                val acc = toolCallsMap[0] ?: JSONObject().also {
                                    toolCallsMap[0] = it
                                }
                                if (legacyFunction.has("name") && !legacyFunction.isNull("name")) {
                                    acc.put("name", legacyFunction.getString("name"))
                                }
                                if (legacyFunction.has("arguments") && !legacyFunction.isNull("arguments")) {
                                    acc.put(
                                        "arguments",
                                        acc.optString("arguments", "") + legacyFunction.getString("arguments")
                                    )
                                }
                            }
                        } catch (_: Exception) {
                            // 跳过解析失败的行
                        }
                    }

                    // 整理 tool calls
                    for ((i, acc) in toolCallsMap.toSortedMap()) {
                        val toolName = acc.optString("name", "").trim()
                        // Do not expose incomplete provider chunks as a tool call.
                        // They otherwise become an empty-name call in Lua.
                        if (toolName.isEmpty()) continue
                        val tc = JSONObject()
                        // Some compatible APIs omit the id from streamed tool-call chunks.
                        // The same fallback is used for the assistant and tool messages.
                        val toolCallId = acc.optString("id", "").ifEmpty { "call_$i" }
                        tc.put("id", toolCallId)
                        tc.put("name", toolName)
                        tc.put("arguments", acc.optString("arguments", ""))
                        toolCallsArr.put(tc)
                    }

                    val fullTextStr = fullText.toString()
                    val toolCallsStr = if (toolCallsArr.length() > 0) toolCallsArr.toString() else null

                    context.runOnUiThread {
                        try {
                            onDone.call(
                                LuaString.valueOf(fullTextStr),
                                if (toolCallsStr != null) LuaString.valueOf(toolCallsStr) else NIL
                            )
                        } catch (_: Exception) { }
                    }
                } catch (e: Exception) {
                    context.runOnUiThread {
                        try {
                                onDone.call(
                                    LuaString.valueOf("ERROR: " + (e.message ?: "Stream error"))
                                )
                        } catch (e2: Exception) {
                            context.sendMsg("Stream error callback: ${e2.message}")
                        }
                    }
                }
            }
        })
    }

    private fun String.urlBuilder() = Request.Builder().url(this)
}

class okhttp : TwoArgFunction() {
    private lateinit var globals: Globals
    private val client = OkHttpClient.Builder().build()
    override fun call(modname: LuaValue, env: LuaValue): LuaValue {
        globals = env.checkglobals()
        val okhttp = LuaTable().apply {
            set("get", get())
            set("post", post())
            set("postJson", postJson())
            set("put", put())
            set("delete", delete())
            set("head", head())
            set("patch", patch())
        }
        env["okhttp"] = okhttp
        if (env["package"].isNotNil()) env["package"]["loaded"]["okhttp"] = okhttp
        return NIL
    }

    inner class postJson : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val requestBuilder = Request.Builder()
            args.argAt(3).ifNotNil()?.checktable()?.apply {
                for (key in keys()) {
                    requestBuilder.addHeader(key.asString(), get(key).asString())
                }
            }
            return client.newCall(
                requestBuilder.url(
                    args.firstArg().checkjstring()
                ).post(
                    args.secondArg().checkjstring()
                        .toRequestBody("application/json; charset=utf-8".toMediaTypeOrNull())
                ).build()
            ).execute().toLuaInstance()
        }
    }

    inner class get : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val requestBuilder = Request.Builder()
            args.secondArg().ifNotNil()?.checktable()?.apply {
                for (key in keys()) {
                    requestBuilder.addHeader(key.asString(), get(key).asString())
                }
            }
            return client.newCall(
                requestBuilder.url(
                    args.firstArg().checkjstring()
                ).build()
            ).execute().toLuaInstance()
        }
    }

    inner class post : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val builder = FormBody.Builder()
            val requestBuilder = Request.Builder()
            args.secondArg().checktable().apply {
                for (key in keys()) {
                    builder.add(key.asString(), get(key).asString())
                }
            }
            args.argAt(3).ifNotNil()?.checktable()?.apply {
                for (key in keys()) {
                    requestBuilder.addHeader(key.asString(), get(key).asString())
                }
            }
            return client.newCall(
                requestBuilder.url(
                    args.firstArg().checkjstring()
                ).post(
                    builder.build()
                ).build()
            ).execute().toLuaInstance()
        }
    }

    inner class delete : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val builder = FormBody.Builder()
            val requestBuilder = Request.Builder()
            args.secondArg().checktable().apply {
                for (key in keys()) {
                    builder.add(key.asString(), get(key).asString())
                }
            }
            args.argAt(3).ifNotNil()?.checktable()?.apply {
                for (key in keys()) {
                    requestBuilder.addHeader(key.asString(), get(key).asString())
                }
            }
            return client.newCall(
                requestBuilder.url(
                    args.firstArg().checkjstring()
                ).delete(
                    builder.build()
                ).build()
            ).execute().toLuaInstance()
        }
    }

    inner class put : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val builder = FormBody.Builder()
            val requestBuilder = Request.Builder()
            args.secondArg().checktable().apply {
                for (key in keys()) {
                    builder.add(key.asString(), get(key).asString())
                }
            }
            args.argAt(3).ifNotNil()?.checktable()?.apply {
                for (key in keys()) {
                    requestBuilder.addHeader(key.asString(), get(key).asString())
                }
            }
            return client.newCall(
                requestBuilder.url(
                    args.firstArg().checkjstring()
                ).put(
                    builder.build()
                ).build()
            ).execute().toLuaInstance()
        }
    }

    inner class head : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val requestBuilder = Request.Builder()
            args.secondArg().ifNotNil()?.checktable()?.apply {
                for (key in keys()) {
                    requestBuilder.addHeader(key.asString(), get(key).asString())
                }
            }
            return client.newCall(
                requestBuilder.url(
                    args.firstArg().checkjstring()
                ).head().build()
            ).execute().toLuaInstance()
        }
    }

    inner class patch : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val builder = FormBody.Builder()
            val requestBuilder = Request.Builder()
            args.secondArg().checktable().apply {
                for (key in keys()) {
                    builder.add(key.asString(), get(key).asString())
                }
            }
            args.argAt(3).ifNotNil()?.checktable()?.apply {
                for (key in keys()) {
                    requestBuilder.addHeader(key.asString(), get(key).asString())
                }
            }
            return client.newCall(
                requestBuilder.url(
                    args.firstArg().checkjstring()
                ).patch(
                    builder.build()
                ).build()
            ).execute().toLuaInstance()
        }
    }
}
