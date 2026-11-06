package com.nekolaska.mcp.server

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.net.Socket
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class McpServerTest {
    private val calls = AtomicInteger()
    private val backend = object : McpProtocolAdapter.Backend {
        override fun tools() = JSONArray().put(JSONObject().put("name", "echo").put("inputSchema", JSONObject().put("type", "object")))
        override fun call(name: String, args: JSONObject): JSONObject {
            calls.incrementAndGet()
            return JSONObject().put("content", JSONArray()).put("structuredContent", args)
        }
        override fun resources() = JSONArray().put(JSONObject().put("uri", "neluaj://docs/test").put("name", "test"))
        override fun readResource(uri: String) = JSONObject().put("contents", JSONArray().put(JSONObject().put("uri", uri).put("text", "hello")))
    }
    private val token = "0123456789abcdef0123456789abcdef"
    private val version = McpProtocolAdapter.VERSION
    private fun request(method: String, params: JSONObject = JSONObject()) = JSONObject().put("jsonrpc", "2.0").put("id", 7).put("method", method).put("params", params).toString()

    @Test fun negotiationMethodsAndNotifications() {
        val adapter = McpProtocolAdapter(backend)
        val init = adapter.handle(request("initialize", JSONObject().put("protocolVersion", "future")
            .put("capabilities", JSONObject()).put("clientInfo", JSONObject().put("name", "test").put("version", "1"))), null)
        assertEquals(version, init.body!!.getJSONObject("result").getString("protocolVersion"))
        for (method in listOf("ping", "tools/list", "resources/list", "resources/templates/list")) {
            assertTrue(adapter.handle(request(method), version).body!!.has("result"))
        }
        assertEquals(202, adapter.handle("""{"jsonrpc":"2.0","method":"notifications/initialized"}""", version).status)
        assertNull(adapter.handle("""{"jsonrpc":"2.0","method":"tools/call","params":{"name":"echo"}}""", version).body)
        assertEquals(0, calls.get())
        assertTrue(adapter.handle(request("tools/call", JSONObject().put("name", "echo")), version).body!!.has("result"))
        assertEquals(1, calls.get())
        assertTrue(adapter.handle(request("resources/read", JSONObject().put("uri", "neluaj://docs/test")), version).body!!.has("result"))
    }

    @Test fun invalidRequestsNeverExecuteBackend() {
        val adapter = McpProtocolAdapter(backend)
        assertEquals(400, adapter.handle("[]", version).status)
        assertEquals(400, adapter.handle("{", version).status)
        assertEquals(400, adapter.handle(request("ping"), null).status)
        assertEquals(400, adapter.handle(request("ping"), "2026-07-28").status)
        assertEquals(-32601, adapter.handle(request("missing"), version).body!!.getJSONObject("error").getInt("code"))
        assertEquals(-32602, adapter.handle(request("tools/call", JSONObject().put("name", "missing")), version).body!!.getJSONObject("error").getInt("code"))
        assertEquals(-32602, adapter.handle(request("tools/call", JSONObject().put("name", "echo").put("arguments", JSONArray())), version).body!!.getJSONObject("error").getInt("code"))
        assertEquals(0, calls.get())
    }

    @Test fun cancellationIsValidatedAndOnlyAcceptedAsNotification() {
        val cancelled = mutableListOf<Any>()
        val callIds = mutableListOf<Any>()
        val cancellable = object : McpProtocolAdapter.Backend by backend {
            override fun cancel(requestId: Any) { cancelled.add(requestId) }
            override fun callWithRequestId(requestId: Any, name: String, args: JSONObject): JSONObject {
                callIds.add(requestId)
                return backend.call(name, args)
            }
        }
        val adapter = McpProtocolAdapter(cancellable)
        adapter.handle(request("tools/call", JSONObject().put("name", "echo")), version)
        assertEquals(listOf(7), callIds)
        fun cancel(value: Any?) = JSONObject().put("jsonrpc", "2.0").put("method", "notifications/cancelled")
            .put("params", JSONObject().put("requestId", value ?: JSONObject.NULL))
        for (id in listOf<Any>(7, "request-2")) {
            val result = adapter.handle(cancel(id).toString(), version)
            assertEquals(202, result.status)
            assertNull(result.body)
        }
        assertEquals(listOf(7, "request-2"), cancelled)
        for (invalid in listOf(null, JSONObject(), JSONArray(), true, 1.5)) {
            val result = adapter.handle(cancel(invalid).toString(), version)
            assertEquals(400, result.status)
            assertNull(result.body)
        }
        val asRequest = adapter.handle(cancel(7).put("id", "cancel-request").toString(), version)
        assertEquals(-32601, asRequest.body!!.getJSONObject("error").getInt("code"))
        assertEquals(2, cancelled.size)
    }

    @Test fun toolFailuresAreResultsAndDoNotLeakBackendDetails() {
        val failing = object : McpProtocolAdapter.Backend by backend {
            override fun call(name: String, args: JSONObject): JSONObject = error("secret/path/token")
            override fun callWithRequestId(requestId: Any, name: String, args: JSONObject) = call(name, args)
        }
        val result = McpProtocolAdapter(failing).handle(request("tools/call", JSONObject().put("name", "echo")), version)
        assertEquals(200, result.status)
        assertTrue(result.body!!.getJSONObject("result").getBoolean("isError"))
        assertFalse(result.body.toString().contains("secret/path/token"))
    }

    @Test fun onlyExplicitBrowserOriginIsAllowed() {
        val host = McpServerHost(token, backend, 0, allowedOrigins = setOf("http://localhost:6274"))
        host.start()
        try {
            assertTrue(exchange(host, extra = "Origin: http://localhost:6274\r\n").startsWith("HTTP/1.1 200"))
            assertTrue(exchange(host, extra = "Origin: http://localhost:6275\r\n").startsWith("HTTP/1.1 403"))
            assertTrue(exchange(host, extra = "Origin: null\r\n").startsWith("HTTP/1.1 403"))
        } finally { host.stop() }
    }

    @Test fun explicitTokenlessModeStillEnforcesLoopbackHostAndOrigin() {
        val host = McpServerHost("", backend, 0, requireToken = false)
        host.start()
        try {
            assertTrue(exchange(host, auth = null).startsWith("HTTP/1.1 200"))
            assertTrue(exchange(host, auth = null, extra = "Origin: https://example.org\r\n").startsWith("HTTP/1.1 403"))
            assertTrue(exchange(host, auth = null, hostHeader = "example.org").startsWith("HTTP/1.1 403"))
        } finally { host.stop() }
        assertTrue(runCatching { McpServerHost("", backend, 0) }.isFailure)
    }

    private fun exchange(host: McpServerHost, body: String = request("ping"), method: String = "POST", auth: String? = token,
                         extra: String = "", hostHeader: String = "127.0.0.1:${host.getPort()}", length: Int = body.toByteArray().size): String {
        return Socket("127.0.0.1", host.getPort()).use { socket ->
            socket.soTimeout = 4000
            val authorization = auth?.let { "Authorization: Bearer $it\r\n" }.orEmpty()
            val headers = "$method /mcp HTTP/1.1\r\nHost: $hostHeader\r\n${authorization}Content-Type: application/json\r\nAccept: application/json, text/event-stream\r\nMCP-Protocol-Version: $version\r\nContent-Length: $length\r\n$extra\r\n"
            socket.getOutputStream().write((headers + body).toByteArray())
            socket.getInputStream().readBytes().toString(Charsets.UTF_8)
        }
    }

    @Test fun httpSecurityLimitsAndRestart() {
        val host = McpServerHost(token, backend, 0, maxBodyBytes = 256)
        host.start()
        try {
            assertTrue(host.isRunning())
            assertTrue(exchange(host).startsWith("HTTP/1.1 200"))
            assertTrue(exchange(host, auth = "bad").startsWith("HTTP/1.1 401"))
            assertTrue(exchange(host, extra = "Origin: https://evil.example\r\n").startsWith("HTTP/1.1 403"))
            assertTrue(exchange(host, hostHeader = "evil.example").startsWith("HTTP/1.1 403"))
            assertTrue(exchange(host, method = "GET").startsWith("HTTP/1.1 405"))
            // A claimed oversized body is rejected without waiting to receive it.
            assertTrue(exchange(host, body = "", length = 257).startsWith("HTTP/1.1 413"))
            assertTrue(exchange(host, extra = "Transfer-Encoding: chunked\r\n").startsWith("HTTP/1.1 400"))
            assertTrue(exchange(host, body = "[]").startsWith("HTTP/1.1 400"))
            val notification = exchange(host, body = """{"jsonrpc":"2.0","method":"notifications/initialized"}""")
            assertTrue(notification.startsWith("HTTP/1.1 202"))
            assertEquals("", notification.substringAfter("\r\n\r\n"))
        } finally { host.stop() }
        assertFalse(host.isRunning())
        host.start()
        try { assertTrue(exchange(host).startsWith("HTTP/1.1 200")) } finally { host.stop() }
    }

    @Test fun slowConnectionsExpireAndCapacityRecovers() {
        val host = McpServerHost(token, backend, 0, maxConnections = 1, requestTimeoutMillis = 200)
        host.start()
        try {
            Socket("127.0.0.1", host.getPort()).use { socket ->
                socket.soTimeout = 2000
                socket.getOutputStream().write("POST /mcp HTTP/1.1\r\n".toByteArray())
                // Absolute deadline applies even before authentication/complete headers.
                assertEquals(-1, socket.getInputStream().read())
            }
        } finally { host.stop() }
    }

    @Test fun connectionLimitHoldsUntilBackendActuallyFinishes() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val finished = CountDownLatch(1)
        val blocking = object : McpProtocolAdapter.Backend by backend {
            override fun callWithRequestId(requestId: Any, name: String, args: JSONObject) = call(name, args)
            override fun call(name: String, args: JSONObject): JSONObject {
                entered.countDown()
                release.await(3, TimeUnit.SECONDS)
                finished.countDown()
                return JSONObject().put("content", JSONArray())
            }
        }
        val host = McpServerHost(token, blocking, 0, maxConnections = 1, requestTimeoutMillis = 500)
        host.start()
        try {
            val thread = Thread { try { exchange(host, request("tools/call", JSONObject().put("name", "echo"))) } catch (_: Exception) { } }
            thread.start()
            assertTrue(entered.await(2, TimeUnit.SECONDS))
            Socket("127.0.0.1", host.getPort()).use { excess ->
                excess.soTimeout = 1500
                assertEquals(-1, excess.getInputStream().read())
            }
            thread.join(2000) // Deadline closes caller while the backend still owns its slot.
            assertFalse(thread.isAlive)
            assertEquals(1L, finished.count)
            Socket("127.0.0.1", host.getPort()).use { excess ->
                excess.soTimeout = 1500
                assertEquals(-1, excess.getInputStream().read())
            }
        } finally { release.countDown(); host.stop() }
    }
}
