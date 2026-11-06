package com.nekolaska.mcp.server

import fi.iki.elonen.NanoHTTPD
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit

/** Owned by the Android lifecycle host, with no Activity or filesystem dependency. */
class McpServerHost @JvmOverloads constructor(
    token: String,
    backend: McpProtocolAdapter.Backend,
    private val port: Int = 8765,
    private val maxBodyBytes: Int = 1024 * 1024,
    private val maxConnections: Int = 4,
    private val requestTimeoutMillis: Int = 30_000,
    private val allowedOrigins: Set<String> = emptySet(),
    private val requireToken: Boolean = true
) {
    private val expectedTokenHash = digest(token)
    private val adapter = McpProtocolAdapter(backend)
    private var server: NanoHTTPD? = null
    private var runner: BoundedRunner? = null

    init {
        require(!requireToken || (token.length >= 32 && token.all { it.code in 0x21..0x7e })) { "Use a generated pairing token of at least 32 characters" }
        require(port in 0..65535 && maxBodyBytes in 1..16 * 1024 * 1024)
        require(maxConnections in 1..32 && requestTimeoutMillis in 100..300_000)
    }

    @Synchronized fun start() {
        if (server != null) return
        val bounded = BoundedRunner(maxConnections, requestTimeoutMillis)
        val http = object : NanoHTTPD("127.0.0.1", port) {
            override fun serve(session: IHTTPSession): Response = handle(session, listeningPort)
        }
        http.setAsyncRunner(bounded)
        http.setTempFileManagerFactory {
            object : NanoHTTPD.TempFileManager {
                override fun clear() = Unit
                override fun createTempFile(filenameHint: String?): NanoHTTPD.TempFile =
                    throw UnsupportedOperationException("MCP uploads must stay in bounded memory")
            }
        }
        try { http.start(requestTimeoutMillis, true) }
        catch (failure: Exception) { http.stop(); bounded.closeAll(); throw failure }
        runner = bounded
        server = http
    }

    /** Closes listeners/connections, but does not interrupt a transaction already executing. */
    @Synchronized fun stop() {
        server?.stop()
        runner?.closeAll()
        server = null
        runner = null
    }

    @Synchronized fun isRunning(): Boolean = server?.isAlive == true
    @Synchronized fun getPort(): Int = server?.listeningPort ?: port

    private fun handle(session: NanoHTTPD.IHTTPSession, boundPort: Int): NanoHTTPD.Response {
        val headers = session.headers
        if (headers["host"] !in setOf("127.0.0.1:$boundPort", "localhost:$boundPort")) return response(403)
        val origin = headers["origin"]
        // No browser origin is allowed by default; native clients can omit it.
        if (origin != null && origin !in allowedOrigins) return response(403)
        val authorization = headers["authorization"].orEmpty()
        val candidate = if (authorization.startsWith("Bearer ")) authorization.substring(7) else ""
        val authenticated = MessageDigest.isEqual(expectedTokenHash, digest(candidate))
        if (requireToken && !authenticated) return response(401).apply { addHeader("WWW-Authenticate", "Bearer") }
        if (session.uri != "/mcp" || session.queryParameterString != null) return response(404)
        if (session.method != NanoHTTPD.Method.POST) return response(405).apply { addHeader("Allow", "POST") }
        if (headers["content-type"]?.substringBefore(';')?.trim()?.lowercase() != "application/json") return response(415)
        val accept = headers["accept"].orEmpty().split(',').map { it.substringBefore(';').trim().lowercase() }
        if ("application/json" !in accept || "text/event-stream" !in accept) return response(406)
        if (headers.containsKey("transfer-encoding") || headers.containsKey("content-encoding")) return response(400)
        val lengthText = headers["content-length"] ?: return response(411)
        if (lengthText.isEmpty() || lengthText.any { it !in '0'..'9' }) return response(400)
        val length = lengthText.toLongOrNull() ?: return response(413)
        if (length > maxBodyBytes) return response(413)
        if (length == 0L) return response(400)
        return try {
            // Deliberately bypass parseBody(): bounded memory only, no temporary upload files.
            val bytes = ByteArray(length.toInt())
            var offset = 0
            while (offset < bytes.size) {
                val count = session.inputStream.read(bytes, offset, bytes.size - offset)
                if (count <= 0) return response(400)
                offset += count
            }
            val body = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
            val reply = adapter.handle(body, headers["mcp-protocol-version"])
            response(reply.status, reply.body?.toString().orEmpty())
        } catch (_: Exception) { response(400) }
    }

    private fun response(code: Int, body: String = ""): NanoHTTPD.Response {
        val status = object : NanoHTTPD.Response.IStatus {
            override fun getRequestStatus() = code
            override fun getDescription() = "$code ${when (code) {
                200 -> "OK"; 202 -> "Accepted"; 400 -> "Bad Request"; 401 -> "Unauthorized"
                403 -> "Forbidden"; 404 -> "Not Found"; 405 -> "Method Not Allowed"; 406 -> "Not Acceptable"
                411 -> "Length Required"; 413 -> "Payload Too Large"; 415 -> "Unsupported Media Type"
                else -> "Error"
            }}"
        }
        return NanoHTTPD.newFixedLengthResponse(status, "application/json", body).apply {
            // One message per connection also prevents an unread rejected body becoming a request.
            closeConnection(true)
            addHeader("Cache-Control", "no-store")
            addHeader("X-Content-Type-Options", "nosniff")
        }
    }

    private class BoundedRunner(limit: Int, private val timeout: Int) : NanoHTTPD.AsyncRunner {
        private val slots = Semaphore(limit)
        private val active = ConcurrentHashMap<NanoHTTPD.ClientHandler, ScheduledFuture<*>>()
        private val workers = Executors.newFixedThreadPool(limit) { r -> Thread(r, "mcp-http").apply { isDaemon = true } }
        private val deadlines = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "mcp-deadline").apply { isDaemon = true } }

        override fun exec(clientHandler: NanoHTTPD.ClientHandler) {
            if (!slots.tryAcquire()) { clientHandler.close(); return }
            try {
                active[clientHandler] = deadlines.schedule({ clientHandler.close() }, timeout.toLong(), TimeUnit.MILLISECONDS)
                workers.execute {
                    try { clientHandler.run() }
                    finally { closed(clientHandler); slots.release() }
                }
            } catch (_: RuntimeException) { closed(clientHandler); slots.release(); clientHandler.close() }
        }

        override fun closed(clientHandler: NanoHTTPD.ClientHandler) { active.remove(clientHandler)?.cancel(false) }
        override fun closeAll() {
            active.keys.toList().forEach { it.close() }
            active.values.forEach { it.cancel(false) }
            active.clear()
            deadlines.shutdownNow()
            workers.shutdown() // Do not interrupt a backend already publishing a transaction.
        }
    }

    companion object {
        private fun digest(value: String): ByteArray = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
    }
}
