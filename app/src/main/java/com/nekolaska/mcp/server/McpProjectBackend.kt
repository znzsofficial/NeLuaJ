package com.nekolaska.mcp.server

import com.nekolaska.io.FileMutationEngine
import org.json.JSONArray
import org.json.JSONObject
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Path
import java.nio.file.Paths
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/** Protocol-independent, bounded project tools. All writes delegate to the shared Lua facade. */
class McpProjectBackend(
    private val project: McpProjectRegistry,
    private val storageDir: String,
    private val mutate: (String, JSONObject, () -> Boolean) -> JSONObject,
    private val document: (String) -> String,
    private val record: (String, Boolean) -> Unit = { _, _ -> }
) : McpProtocolAdapter.Backend {
    private val inFlight = ConcurrentHashMap<Any, AtomicBoolean>()
    private val cancellation = ThreadLocal<AtomicBoolean>()

    override fun cancel(requestId: Any) { inFlight[requestId]?.set(true) }

    override fun callWithRequestId(requestId: Any, name: String, args: JSONObject): JSONObject {
        val cancelled = AtomicBoolean(false)
        if (inFlight.putIfAbsent(requestId, cancelled) != null) return result(JSONObject().put("error", "Duplicate in-flight JSON-RPC id"), true)
        cancellation.set(cancelled)
        return try { call(name, args) } finally {
            cancellation.remove()
            inFlight.remove(requestId, cancelled)
        }
    }
    private val docs = linkedMapOf(
        "neluaj://docs/agent" to "res/doc/agent_docs.md",
        "neluaj://docs/layout" to "res/doc/layout_ai.md"
    )
    private val writes = linkedMapOf(
        "create_file" to "create_file", "apply_patch" to "apply_patch",
        "replace_in_file" to "replace_in_file", "append_file" to "append_file",
        "create_directory" to "create_folder", "rename_path" to "rename_file",
        "delete_path" to "delete_file", "undo_file_change" to "undo", "redo_file_change" to "redo"
    )

    override fun tools(): JSONArray {
        val tools = JSONArray()
        fun add(name: String, description: String, fields: Map<String, String>, required: List<String>, write: Boolean = false) {
            val properties = JSONObject()
            fields.forEach { (key, type) -> properties.put(key, JSONObject().put("type", type)) }
            tools.put(JSONObject().put("name", name).put("description", description)
                .put("inputSchema", JSONObject().put("type", "object").put("properties", properties)
                    .put("required", JSONArray(required)).put("additionalProperties", false))
                .put("annotations", JSONObject().put("readOnlyHint", !write).put("destructiveHint", write)
                    .put("openWorldHint", false)))
        }
        val handle = mapOf("projectHandle" to "string")
        val path = handle + mapOf("path" to "string")
        add("server_info", "Connection capabilities; call project_info to obtain the explicitly authorized project handle.", emptyMap(), emptyList())
        add("project_info", "Get this connection's authorized project and opaque projectHandle.", emptyMap(), emptyList())
        add("list_files", "List one directory, with bounded offset pagination. Paths are project-relative.", path + mapOf("offset" to "integer", "limit" to "integer"), listOf("projectHandle"))
        add("read_file", "Read a bounded UTF-8 or base64 file and its SHA-256 version. Missing paths also return a version for conditional creation.", path, listOf("projectHandle", "path"))
        add("search_files", "Literal filename search, optionally file content. Bounded to 2000 entries / 4 MiB content; reports truncation.", path + mapOf("query" to "string", "content" to "boolean", "offset" to "integer", "limit" to "integer"), listOf("projectHandle", "query"))
        add("get_transaction", "Query a durable transaction result for this project.", handle + mapOf("transactionId" to "string"), listOf("projectHandle", "transactionId"))
        add("get_history", "Read current undo/redo head IDs for conditional history operations.", handle, listOf("projectHandle"))
        if (project.writable) for (name in writes.keys) {
            var fields = path + mapOf("requestId" to "string", "expectedVersion" to "string")
            val required = mutableListOf("projectHandle", "requestId", "path", "expectedVersion")
            when (name) {
                "create_file", "append_file" -> { fields += "content" to "string"; required += "content" }
                "apply_patch" -> { fields += "patch" to "string"; required += "patch" }
                "replace_in_file" -> { fields += mapOf("old" to "string", "new" to "string", "count" to "integer"); required += listOf("old", "new") }
                "rename_path" -> { fields += mapOf("new_path" to "string", "expectedTargetVersion" to "string"); required += listOf("new_path", "expectedTargetVersion") }
                "undo_file_change", "redo_file_change" -> {
                    fields = handle + mapOf("requestId" to "string", "expectedHead" to "string")
                    required.clear(); required += listOf("projectHandle", "requestId", "expectedHead")
                }
            }
            add(name, "Version-checked project mutation. Reuse requestId only for the identical request; query transaction after disconnect. Changes share IDE undo history.", fields, required, true)
        }
        return tools
    }

    override fun call(name: String, args: JSONObject): JSONObject {
        val response = try {
            check(project.isActive()) { "Project authorization revoked" }
            val schema = (0 until tools().length()).map { tools().getJSONObject(it) }.firstOrNull { it.getString("name") == name }
                ?: error("Unknown or unauthorized tool: $name")
            validate(args, schema.getJSONObject("inputSchema"))
            if (name !in listOf("server_info", "project_info")) project.authorize(args.getString("projectHandle"), name in writes)
            val data = when (name) {
                "server_info" -> JSONObject().put("name", "NeLuaJ+").put("protocolVersion", "2025-11-25")
                    .put("transport", "streamable-http").put("writable", project.writable)
                "project_info" -> JSONObject().put("projectHandle", project.handle).put("name", Paths.get(project.projectRoot).fileName.toString())
                    .put("writable", project.writable).put("pathMode", "project-relative")
                "list_files" -> list(args)
                "read_file" -> read(args.getString("path"))
                "search_files" -> search(args)
                "get_transaction" -> {
                    val result = FileMutationEngine.getResult(storageDir, args.getString("transactionId"))
                    if (result == "null") JSONObject().put("found", false)
                    else JSONObject(result).also { require(it.getString("scopeId") == project.projectRoot) { "Transaction scope mismatch" } }
                }
                "get_history" -> JSONObject().put("undo", jsonOrNull(FileMutationEngine.peek(storageDir, "undo")))
                    .put("redo", jsonOrNull(FileMutationEngine.peek(storageDir, "redo")))
                else -> {
                    val copy = JSONObject(args.toString()).apply { remove("projectHandle") }
                    if (copy.has("path")) project.resolve(copy.getString("path"))
                    if (copy.has("new_path")) project.resolve(copy.getString("new_path"))
                    // The facade resolves relative paths and owns validation, snapshots and publication.
                    val internalName = if (name == "delete_path" && Files.isDirectory(project.resolve(copy.getString("path")), NOFOLLOW_LINKS)) "delete_folder" else writes.getValue(name)
                    val cancelled = cancellation.get()
                    mutate(internalName, copy) { cancelled?.get() == true }
                }
            }
            val failed = data.has("outcome") && data.optString("outcome") !in listOf("committed", "unchanged")
            result(data, failed)
        } catch (e: Exception) {
            result(JSONObject().put("error", JSONObject().put("code", "REQUEST_REJECTED").put("message", e.message ?: "Request rejected")), true)
        }
        record(name, !response.optBoolean("isError"))
        return response
    }

    private fun validate(args: JSONObject, schema: JSONObject) {
        val required = schema.getJSONArray("required")
        for (i in 0 until required.length()) require(args.has(required.getString(i)) && !args.isNull(required.getString(i))) { "Missing ${required.getString(i)}" }
        val props = schema.getJSONObject("properties")
        for (key in args.keys()) {
            require(props.has(key)) { "Unknown argument: $key" }
            val value = args.get(key)
            require(when (props.getJSONObject(key).getString("type")) {
                "string" -> value is String
                "boolean" -> value is Boolean
                "integer" -> value is Number && value.toDouble() == value.toLong().toDouble()
                else -> false
            }) { "Invalid argument type: $key" }
        }
    }

    private fun read(relative: String): JSONObject {
        val absolute = project.resolve(relative)
        return JSONObject(FileMutationEngine.observe(absolute.toString())).apply {
            put("path", project.relative(absolute))
            // Directory observation is a versioned manifest; never expose file contents in a directory listing.
            if (has("manifest")) remove("manifest")
        }
    }

    private fun page(args: JSONObject): Pair<Int, Int> {
        val offset = args.optLong("offset", 0)
        val limit = args.optLong("limit", 100)
        require(offset in 0..2000 && limit in 1..200) { "offset must be 0..2000 and limit 1..200" }
        return offset.toInt() to limit.toInt()
    }

    private fun list(args: JSONObject): JSONObject {
        val path = project.resolve(args.optString("path", ""), true)
        require(Files.isDirectory(path, NOFOLLOW_LINKS)) { "Directory required" }
        val (offset, limit) = page(args)
        val entries = Files.newDirectoryStream(path).use { it.asSequence().take(2001).toList() }
        require(entries.size <= 2000) { "Directory exceeds 2000-entry listing limit" }
        val sorted = entries.sortedBy { it.fileName.toString() }
        val items = JSONArray()
        sorted.drop(offset).take(limit).forEach {
            items.put(JSONObject().put("path", project.relative(it)).put("kind", when {
                Files.isSymbolicLink(it) -> "unsupported"
                Files.isDirectory(it, NOFOLLOW_LINKS) -> "dir"
                Files.isRegularFile(it, NOFOLLOW_LINKS) -> "file"
                else -> "unsupported"
            }))
        }
        return JSONObject().put("entries", items).put("nextOffset", if (offset + limit < sorted.size) offset + limit else JSONObject.NULL)
    }

    private fun search(args: JSONObject): JSONObject {
        val query = args.getString("query")
        require(query.isNotEmpty() && query.length <= 1024) { "query must contain 1..1024 characters" }
        val root = project.resolve(args.optString("path", ""), true)
        val (offset, limit) = page(args)
        val matches = mutableListOf<String>()
        var visited = 0
        var bytes = 0L
        var truncated = false
        Files.walk(root).use { stream ->
            val it = stream.iterator()
            while (it.hasNext()) {
                if (++visited > 2000) { truncated = true; break }
                val path = it.next()
                if (Files.isSymbolicLink(path)) continue
                project.resolve(project.relative(path), true)
                var found = path.fileName.toString().contains(query, ignoreCase = true)
                if (!found && args.optBoolean("content") && Files.isRegularFile(path, NOFOLLOW_LINKS)) {
                    val size = Files.size(path)
                    if (size > 1536 * 1024 || bytes + size > 4 * 1024 * 1024) { truncated = true; continue }
                    bytes += size
                    val observed = JSONObject(FileMutationEngine.observe(path.toString()))
                    found = observed.optString("text", "").contains(query)
                }
                if (found) matches.add(project.relative(path))
            }
        }
        matches.sort()
        return JSONObject().put("paths", JSONArray(matches.drop(offset).take(limit)))
            .put("truncated", truncated).put("visited", visited.coerceAtMost(2000))
            .put("nextOffset", if (offset + limit < matches.size) offset + limit else JSONObject.NULL)
    }

    override fun resources(): JSONArray = JSONArray().apply {
        docs.forEach { (uri, _) -> put(JSONObject().put("uri", uri).put("name", uri.substringAfterLast('/')).put("mimeType", "text/markdown")) }
    }

    override fun readResource(uri: String): JSONObject {
        check(project.isActive()) { "Project authorization revoked" }
        val asset = docs[uri] ?: error("Unknown resource")
        return JSONObject().put("contents", JSONArray().put(JSONObject().put("uri", uri).put("mimeType", "text/markdown").put("text", document(asset))))
    }

    private fun jsonOrNull(value: String): Any = if (value == "null") JSONObject.NULL else JSONObject(value)
    private fun result(data: JSONObject, error: Boolean) = JSONObject().put("isError", error).put("structuredContent", data)
        .put("content", JSONArray().put(JSONObject().put("type", "text").put("text", data.toString())))
}
