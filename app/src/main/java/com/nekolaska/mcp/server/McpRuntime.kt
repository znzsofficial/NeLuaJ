package com.nekolaska.mcp.server

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.security.SecureRandom
import java.util.Base64

/** User-started process-local connection session. No Activity is retained by the listener. */
object McpRuntime {
    private data class Session(val registry: McpProjectRegistry, val mutations: McpMutationHost,
        val server: McpServerHost, val credential: String, val agentRoot: String, val context: Context,
        val requireToken: Boolean)
    @Volatile private var session: Session? = null
    @Volatile private var lastError: String? = null
    private val recent = ArrayDeque<JSONObject>()

    @JvmOverloads
    @Synchronized fun start(context: Context, projectRoot: String, agentRoot: String, writable: Boolean, requireToken: Boolean = true): String {
        if (session != null) return status()
        var mutations: McpMutationHost? = null
        var registry: McpProjectRegistry? = null
        return try {
            val app = context.applicationContext
            val root = java.nio.file.Paths.get(projectRoot).normalize().toString()
            registry = McpProjectRegistry(root, writable)
            val authorization = registry
            mutations = McpMutationHost(app, root, agentRoot) { authorization.isActive() }
            val host = mutations
            val credential = if (requireToken) newToken() else ""
            val backend = McpProjectBackend(authorization, host.storageDir, { name, args, cancelled -> host.execute(name, args, cancelled) },
                { path -> app.assets.open(path).bufferedReader(Charsets.UTF_8).use { it.readText() } }, ::record)
            val server = McpServerHost(credential, backend, requireToken = requireToken)
            server.start()
            session = Session(authorization, host, server, credential, agentRoot, app, requireToken)
            lastError = null
            status()
        } catch (e: Exception) {
            registry?.revoke()
            mutations?.close()
            lastError = e.message ?: "Unable to start MCP server"
            status()
        }
    }

    @Synchronized fun stop() {
        val previous = session
        session = null
        previous?.registry?.revoke()
        previous?.server?.stop()
        previous?.mutations?.close()
    }

    fun status(): String {
        val current = session
        return JSONObject().put("running", current?.server?.isRunning() == true)
            .put("projectRoot", current?.registry?.projectRoot ?: "")
            .put("writable", current?.registry?.writable ?: false)
            .put("requireToken", current?.requireToken ?: true)
            .put("port", current?.server?.getPort() ?: 8765)
            .put("endpoint", "http://127.0.0.1:${current?.server?.getPort() ?: 8765}/mcp")
            .put("recent", synchronized(recent) { JSONArray(recent.map { JSONObject(it.toString()) }) })
            .apply { lastError?.let { put("error", it) } }.toString()
    }

    fun token(): String = session?.credential ?: ""

    @Synchronized fun rotateToken(): String {
        val old = session ?: return status()
        if (!old.requireToken) return status()
        stop()
        return start(old.context, old.registry.projectRoot, old.agentRoot, old.registry.writable, old.requireToken)
    }

    fun configuration(): String = JSONObject().put("\$schema", "https://opencode.ai/config.json")
        .put("mcp", JSONObject().put("servers", JSONObject().put("neluaj", JSONObject()
            .put("type", "remote").put("url", "http://127.0.0.1:8765/mcp").put("protocol", "legacy")
            .put("oauth", false).apply {
                if (session?.requireToken != false) put("headers", JSONObject().put("Authorization", "Bearer {env:NELUAJ_MCP_TOKEN}"))
            }))).toString(2)

    private fun record(name: String, success: Boolean) = synchronized(recent) {
        recent.addFirst(JSONObject().put("tool", name).put("success", success).put("time", System.currentTimeMillis()))
        while (recent.size > 20) recent.removeLast()
    }

    private fun newToken(): String = Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(32).also { SecureRandom().nextBytes(it) })
}
