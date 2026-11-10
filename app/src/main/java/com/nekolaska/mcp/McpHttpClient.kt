package com.nekolaska.mcp

import okhttp3.Call
import okhttp3.Headers
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.Collections
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** One tool invocation, including discovery/retries. Registration and cancellation
 * share a monitor so a cancelled invocation can never acquire another resource. */
class McpRequestGroup {
    private var cancelled = false
    private val resources = LinkedHashMap<Any, () -> Unit>()

    @Synchronized fun isCancelled(): Boolean = cancelled
    fun lock(lock: java.util.concurrent.locks.ReentrantLock): Boolean {
        while (!isCancelled()) {
            if (lock.tryLock(25, TimeUnit.MILLISECONDS)) {
                if (!isCancelled()) return true
                lock.unlock()
                return false
            }
        }
        return false
    }
    @Synchronized internal fun <T> acquire(action: () -> T): T {
        if (cancelled) throw IOException("MCP_CANCELLED")
        return action()
    }
    @Synchronized internal fun register(key: Any, cancel: () -> Unit) {
        if (cancelled) cancel() else resources[key] = cancel
    }
    @Synchronized internal fun release(key: Any) { resources.remove(key) }
    @Synchronized internal fun cancelActions(): List<() -> Unit> {
        if (cancelled) return emptyList()
        cancelled = true
        return resources.values.toList().also { resources.clear() }
    }
    fun cancel() { cancelActions().forEach { runCatching { it() } } }
}

/** Legacy MCP HTTP+SSE transport used only by the Agent MCP integration. */
class McpSseConnection(
    private val client: OkHttpClient,
    private val url: String,
    private val headers: Map<String, String>
) {
    private companion object {
        const val CLOSED_RESPONSE = "\u0000mcp-sse-closed"
    }

    private val endpointReady = CountDownLatch(1)
    private val responses = ConcurrentHashMap<String, ArrayBlockingQueue<String>>()
    @Volatile private var endpoint: String? = null
    @Volatile private var error: String? = null
    @Volatile private var call: Call? = null

    init {
        val request = Request.Builder()
            .url(url)
            .headers(Headers.Builder().apply {
                headers.forEach { (name, value) -> add(name, value) }
            }.build())
            .build()
        call = client.newCall(request)
        call?.enqueue(object : okhttp3.Callback {
            override fun onFailure(call: Call, e: IOException) {
                fail(e.message ?: "SSE connection failed")
            }

            override fun onResponse(call: Call, response: Response) {
                try {
                    if (!response.isSuccessful) {
                        fail("HTTP ${response.code}: ${response.body.string().take(300)}")
                        return
                    }
                    val source = response.body.source()
                    var event = "message"
                    val data = ArrayList<String>()
                    fun finishEvent() {
                        if (data.isEmpty()) return
                        val payload = data.joinToString("\n")
                        data.clear()
                        when (event) {
                            "endpoint" -> {
                                val streamUrl = response.request.url
                                val endpointUrl = streamUrl.resolve(payload)
                                if (endpointUrl == null) {
                                    fail("Invalid MCP SSE endpoint")
                                    call.cancel()
                                } else if (endpointUrl.scheme != streamUrl.scheme
                                    || endpointUrl.host != streamUrl.host
                                    || endpointUrl.port != streamUrl.port
                                ) {
                                    // Credentials configured for one MCP server must never
                                    // follow an endpoint event to a different origin.
                                    fail("MCP SSE endpoint must use the stream origin")
                                    call.cancel()
                                } else {
                                    endpoint = endpointUrl.toString()
                                    endpointReady.countDown()
                                }
                            }
                            "message" -> {
                                val json = runCatching { JSONObject(payload) }.getOrNull()
                                val id = runCatching {
                                    if (json != null && json.has("id") && !json.isNull("id")) json.get("id").toString() else null
                                }.getOrNull()
                                if (id != null && json?.optString("method") == "ping") {
                                    postServerResponse(id, endpoint ?: response.request.url.toString())
                                } else if (id != null) {
                                    responses[id]?.offer(payload)
                                }
                            }
                        }
                        event = "message"
                    }
                    while (true) {
                        val line = source.readUtf8Line()?.removeSuffix("\r") ?: break
                        when {
                            line.isEmpty() -> finishEvent()
                            line.startsWith("event:") -> event = line.substring(6).trim()
                            line.startsWith("data:") -> {
                                var value = line.substring(5)
                                if (value.startsWith(" ")) value = value.substring(1)
                                data.add(value)
                            }
                        }
                    }
                    finishEvent()
                    if (error == null) fail("SSE connection closed")
                } catch (error: Exception) {
                    fail(error.message ?: "SSE read failed")
                } finally {
                    response.close()
                }
            }
        })
    }

    private fun fail(message: String) {
        if (error == null) error = message
        endpointReady.countDown()
        responses.values.forEach { it.offer(CLOSED_RESPONSE) }
    }

    fun awaitEndpoint(timeoutMillis: Long): String? {
        endpointReady.await(timeoutMillis, TimeUnit.MILLISECONDS)
        return endpoint
    }

    fun awaitEndpoint(timeoutMillis: Long, group: McpRequestGroup): String? {
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMillis)
        while (!group.isCancelled()) {
            val remaining = deadline - System.nanoTime()
            if (remaining <= 0) return null
            if (endpointReady.await(minOf(remaining, TimeUnit.MILLISECONDS.toNanos(25)), TimeUnit.NANOSECONDS)) {
                return if (group.isCancelled()) null else endpoint
            }
        }
        return null
    }

    fun prepareResponse(id: String) {
        val queue = responses.getOrPut(id) { ArrayBlockingQueue(1) }
        if (error != null) queue.offer(CLOSED_RESPONSE)
    }

    fun cancelResponse(id: String) {
        responses.remove(id)?.let { queue ->
            queue.clear()
            queue.offer(CLOSED_RESPONSE)
        }
    }

    fun prepareResponse(id: String, group: McpRequestGroup) {
        group.acquire {
            prepareResponse(id)
            group.register(responseKey(id)) { cancelResponse(id) }
        }
    }

    private fun responseKey(id: String): Pair<McpSseConnection, String> = this to id

    fun cancelResponse(id: String, group: McpRequestGroup) {
        cancelResponse(id)
        group.release(responseKey(id))
    }

    fun awaitResponse(id: String, timeoutMillis: Long, group: McpRequestGroup): String? = try {
        if (group.isCancelled()) null else awaitResponse(id, timeoutMillis)
    } finally {
        cancelResponse(id, group)
    }

    fun awaitResponse(id: String, timeoutMillis: Long): String? {
        val queue = responses[id] ?: return null
        return try {
            val response = queue.poll(timeoutMillis, TimeUnit.MILLISECONDS)
            response?.takeUnless { it == CLOSED_RESPONSE }
        } finally {
            responses.remove(id)
        }
    }

    fun getError(): String? = error

    fun isUsable(): Boolean = endpoint != null && error == null

    fun close() {
        call?.cancel()
        call = null
        fail("SSE connection closed")
        responses.clear()
    }

    private fun postServerResponse(id: String, endpoint: String) {
        val jsonId: Any = id.toLongOrNull() ?: id
        val body = JSONObject()
            .put("jsonrpc", "2.0")
            .put("id", jsonId)
            .put("result", JSONObject())
            .toString()
        val request = Request.Builder()
            .url(endpoint)
            .headers(Headers.Builder().apply {
                headers.forEach { (name, value) -> add(name, value) }
                set("Accept", "application/json")
            }.build())
            .post(body.toRequestBody("application/json; charset=utf-8".toMediaTypeOrNull()))
            .build()
        client.newCall(request).enqueue(object : okhttp3.Callback {
            override fun onFailure(call: Call, e: IOException) = Unit
            override fun onResponse(call: Call, response: Response) = response.close()
        })
    }
}

class McpHttpClient @JvmOverloads constructor(
    client: OkHttpClient = OkHttpClient.Builder().build()
) {
    private val client = client.newBuilder()
        .followRedirects(false)
        .followSslRedirects(false)
        .callTimeout(120, TimeUnit.SECONDS)
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .writeTimeout(120, TimeUnit.SECONDS)
        .build()
    private val activeCalls = Collections.newSetFromMap(ConcurrentHashMap<Call, Boolean>())
    private val sseConnections = Collections.newSetFromMap(ConcurrentHashMap<McpSseConnection, Boolean>())
    private val groups = Collections.newSetFromMap(ConcurrentHashMap<McpRequestGroup, Boolean>())
    private val lifecycle = Any()

    fun newRequestGroup(): McpRequestGroup = synchronized(lifecycle) {
        McpRequestGroup().also { groups.add(it) }
    }
    fun releaseRequestGroup(group: McpRequestGroup) { groups.remove(group) }

    fun openSse(url: String, headers: Map<String, String>, group: McpRequestGroup): McpSseConnection =
        synchronized(lifecycle) { group.acquire { openSse(url, headers) } }

    fun openSse(url: String, headers: Map<String, String>): McpSseConnection = synchronized(lifecycle) {
        val connection = McpSseConnection(
            client.newBuilder()
                .callTimeout(0, TimeUnit.MILLISECONDS)
                .readTimeout(0, TimeUnit.MILLISECONDS)
                .build(),
            url,
            headers
        )
        sseConnections.add(connection)
        connection
    }

    @JvmOverloads
    fun postJson(url: String, body: String, headers: Map<String, String>, expectedId: Long, group: McpRequestGroup? = null): McpHttpResult {
        val request = Request.Builder()
            .url(url)
            .headers(Headers.Builder().apply {
                headers.forEach { (name, value) -> add(name, value) }
            }.build())
            .post(body.toRequestBody("application/json; charset=utf-8".toMediaTypeOrNull()))
            .build()
        fun createCall(): Call = client.newCall(request).also { call ->
            activeCalls.add(call)
            group?.register(call) { call.cancel() }
        }
        val call = synchronized(lifecycle) {
            if (group != null) group.acquire { createCall() } else createCall()
        }
        return try {
            call.execute().use { response ->
                val responseBody = if (expectedId >= 0 && response.isSuccessful &&
                    response.header("Content-Type").orEmpty().contains("text/event-stream", ignoreCase = true)
                ) {
                    readMatchingSseResponse(response, expectedId)
                } else {
                    response.body.string()
                }
                if (expectedId >= 0 && responseBody.isNotBlank() && response.isSuccessful &&
                    !matchesResponseId(responseBody, expectedId)
                ) {
                    throw IOException("MCP response did not contain JSON-RPC id $expectedId")
                }
                McpHttpResult(response.code, responseBody, response.headers)
            }
        } finally {
            group?.release(call)
            activeCalls.remove(call)
        }
    }

    fun cancelAll() {
        // Mark every old group terminal before allowing registration again.
        // Run cancellation callbacks outside the lifecycle lock (OkHttp may
        // invoke listeners inline). New invocations belong to the next epoch.
        val actions = synchronized(lifecycle) {
            val pending = groups.flatMap { it.cancelActions() }.toMutableList()
            groups.clear()
            activeCalls.forEach { call -> pending.add { call.cancel() } }
            activeCalls.clear()
            sseConnections.forEach { connection -> pending.add { connection.close() } }
            sseConnections.clear()
            pending
        }
        actions.forEach { runCatching { it() } }
    }

    fun deleteSession(url: String, headers: Map<String, String>) {
        val request = Request.Builder()
            .url(url)
            .headers(Headers.Builder().apply {
                headers.forEach { (name, value) -> add(name, value) }
            }.build())
            .delete()
            .build()
        val call = synchronized(lifecycle) {
            client.newCall(request).also { activeCalls.add(it) }
        }
        call.enqueue(object : okhttp3.Callback {
            override fun onFailure(call: Call, e: IOException) {
                activeCalls.remove(call)
            }

            override fun onResponse(call: Call, response: Response) {
                response.close()
                activeCalls.remove(call)
            }
        })
    }

    fun validateServerUrl(rawUrl: String, hasHeaders: Boolean): String? {
        val url = rawUrl.toHttpUrlOrNull() ?: return "MCP server URL is invalid"
        if (url.username.isNotEmpty() || url.password.isNotEmpty()) return "MCP server URL cannot contain credentials"
        if (url.scheme == "https") return null
        if (url.scheme != "http") return "MCP server URL must use http:// or https://"
        val host = url.host.lowercase()
        val loopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        if (!loopback) {
            return if (hasHeaders) "MCP credentials require HTTPS; HTTP is allowed only for localhost"
            else "Cleartext MCP is allowed only for localhost"
        }
        return null
    }

    private fun readMatchingSseResponse(response: Response, expectedId: Long): String {
        val source = response.body.source()
        val data = ArrayList<String>()
        fun finishEvent(): String? {
            if (data.isEmpty()) return null
            val payload = data.joinToString("\n")
            data.clear()
            if (payload == "[DONE]") return null
            return selectResponse(payload, expectedId)
        }
        while (true) {
            val line = source.readUtf8Line()?.removeSuffix("\r")
                ?: return finishEvent() ?: throw IOException("MCP SSE stream closed without JSON-RPC id $expectedId")
            when {
                line.isEmpty() -> finishEvent()?.let { return it }
                line.startsWith("data:") -> data.add(line.substring(5).removePrefix(" "))
            }
        }
    }

    private fun matchesResponseId(encoded: String, expectedId: Long): Boolean =
        selectResponse(encoded, expectedId) != null

    private fun selectResponse(encoded: String, expectedId: Long): String? = runCatching {
        selectResponse(JSONObject(encoded), expectedId)?.toString()
    }.getOrElse {
        runCatching { selectResponse(JSONArray(encoded), expectedId)?.toString() }.getOrNull()
    }

    private fun selectResponse(value: Any?, expectedId: Long): JSONObject? = when (value) {
        is JSONObject -> {
            val id = value.opt("id")
            if (value.optString("jsonrpc") == "2.0" &&
                (value.has("result") || value.has("error")) &&
                id is Number && id.toLong() == expectedId
            ) value else null
        }
        is JSONArray -> (0 until value.length()).firstNotNullOfOrNull { index ->
            selectResponse(value.opt(index), expectedId)
        }
        else -> null
    }
}

class McpHttpResult(
    private val statusCode: Int,
    private val responseBody: String,
    private val responseHeaders: Headers
) {
    fun code(): Int = statusCode
    fun body(): String = responseBody
    fun header(name: String): String? = responseHeaders[name]
}
