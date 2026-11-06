package com.nekolaska.mcp.server

import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

/** Stateless 2025-11-25 adapter. Authorization and HTTP limits belong to the host. */
class McpProtocolAdapter(private val backend: Backend) {
    interface Backend {
        fun tools(): JSONArray
        fun call(name: String, args: JSONObject): JSONObject
        fun callWithRequestId(requestId: Any, name: String, args: JSONObject): JSONObject = call(name, args)
        fun cancel(requestId: Any) {}
        fun resources(): JSONArray
        fun readResource(uri: String): JSONObject
    }

    data class Reply(val status: Int, val body: JSONObject?)

    fun handle(body: String, protocolVersion: String?): Reply {
        val message = try {
            val parser = JSONTokener(body)
            val value = parser.nextValue()
            if (parser.nextClean() != '\u0000') return error(null, -32700, "Parse error", 400)
            value as? JSONObject ?: return error(null, -32600, "Batch and non-object messages are not supported", 400)
        } catch (_: Exception) { return error(null, -32700, "Parse error", 400) }
        val id = message.opt("id")
        if (message.opt("jsonrpc") != "2.0" ||
            (message.has("id") && !validId(id))) {
            return error(null, -32600, "Invalid request", 400)
        }
        val method = message.opt("method") as? String
            ?: return error(id, -32600, "Client responses are not expected", 400)
        if (protocolVersion != null && protocolVersion != VERSION ||
            protocolVersion == null && method != "initialize") {
            return error(id, -32600, "MCP-Protocol-Version must be $VERSION", 400)
        }
        if (message.has("params") && message.opt("params") !is JSONObject) {
            return if (id == null) Reply(400, null) else error(id, -32602, "Invalid params")
        }
        // Never execute request methods presented as notifications.
        if (id == null) {
            if (method == "notifications/cancelled") {
                val requestId = message.optJSONObject("params")?.opt("requestId")
                if (!validId(requestId)) return Reply(400, null)
                try { backend.cancel(requestId!!) }
                catch (_: Exception) { return Reply(500, null) }
            }
            return Reply(202, null)
        }
        val params = message.optJSONObject("params") ?: JSONObject()
        return try {
            val result = when (method) {
                "initialize" -> {
                    require(params.opt("protocolVersion") is String)
                    require(params.opt("capabilities") is JSONObject)
                    val client = params.optJSONObject("clientInfo")
                    require(client?.opt("name") is String && client.opt("version") is String)
                    JSONObject().put("protocolVersion", VERSION)
                        .put("serverInfo", JSONObject().put("name", "NeLuaJ+").put("version", "1"))
                        .put("capabilities", JSONObject().put("tools", JSONObject().put("listChanged", false))
                            .put("resources", JSONObject().put("subscribe", false).put("listChanged", false)))
                }
                "ping" -> JSONObject()
                "tools/list" -> { noCursor(params); JSONObject().put("tools", backend.tools()) }
                "tools/call" -> {
                    val name = requiredString(params, "name")
                    require(!params.has("arguments") || params.opt("arguments") is JSONObject)
                    val tools = backend.tools()
                    if ((0 until tools.length()).none { tools.getJSONObject(it).optString("name") == name })
                        return error(id, -32602, "Unknown tool")
                    try { backend.callWithRequestId(id, name, params.optJSONObject("arguments") ?: JSONObject()) }
                    catch (_: Exception) {
                        JSONObject().put("isError", true).put("content", JSONArray().put(
                            JSONObject().put("type", "text").put("text", "Tool execution failed; query durable result before retrying a mutation.")))
                    }
                }
                "resources/list" -> { noCursor(params); JSONObject().put("resources", backend.resources()) }
                "resources/templates/list" -> { noCursor(params); JSONObject().put("resourceTemplates", JSONArray()) }
                "resources/read" -> backend.readResource(requiredString(params, "uri"))
                else -> return error(id, -32601, "Method not found")
            }
            Reply(200, JSONObject().put("jsonrpc", "2.0").put("id", id).put("result", result))
        } catch (_: IllegalArgumentException) { error(id, -32602, "Invalid params") }
        catch (_: Exception) { error(id, -32603, "Internal error") }
    }

    private fun noCursor(params: JSONObject) { require(!params.has("cursor")) }
    private fun validId(value: Any?): Boolean = value is String || value is Int || value is Long
    private fun requiredString(params: JSONObject, key: String): String {
        val value = params.opt(key)
        require(value is String && value.isNotBlank())
        return value
    }

    private fun error(id: Any?, code: Int, message: String, status: Int = 200) = Reply(status,
        JSONObject().put("jsonrpc", "2.0").put("id", id ?: JSONObject.NULL)
            .put("error", JSONObject().put("code", code).put("message", message)))

    companion object { const val VERSION = "2025-11-25" }
}
