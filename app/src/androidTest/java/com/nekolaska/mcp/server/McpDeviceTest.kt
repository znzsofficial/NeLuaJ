package com.nekolaska.mcp.server

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Exercises the standalone Lua mutation host through the real loopback listener; no Activity. */
@RunWith(AndroidJUnit4::class)
class McpDeviceTest {
    @Test
    fun runtimeAndVersionedMutationsOverHttp() = withRuntime { project ->
        val client = Client(McpRuntime.token())
        val initialized = client.rpc("initialize", JSONObject()
            .put("protocolVersion", McpProtocolAdapter.VERSION)
            .put("capabilities", JSONObject())
            .put("clientInfo", JSONObject().put("name", "device-test").put("version", "1")))
        assertEquals(McpProtocolAdapter.VERSION, initialized.getString("protocolVersion"))
        assertTrue(initialized.getJSONObject("capabilities").has("tools"))
        client.initialized()

        val tools = client.rpc("tools/list").getJSONArray("tools")
        val names = (0 until tools.length()).map { tools.getJSONObject(it).getString("name") }.toSet()
        assertTrue(names.containsAll(listOf("project_info", "read_file", "create_file",
            "append_file", "delete_path", "undo_file_change", "get_history", "get_transaction")))
        val info = client.tool("project_info")
        assertTrue(info.getBoolean("writable"))
        assertEquals("project-relative", info.getString("pathMode"))
        val handle = info.getString("projectHandle")
        assertTrue(handle.isNotBlank())
        fun scoped() = JSONObject().put("projectHandle", handle)
        fun pathArgs() = scoped().put("path", "device.txt")
        fun read() = client.tool("read_file", pathArgs())
        fun history() = client.tool("get_history", scoped())

        assertTrue(history().isNull("undo"))
        assertTrue(history().isNull("redo"))
        val missing = read()
        assertEquals("missing", missing.getString("kind"))
        assertTrue(missing.getString("version").isNotBlank())

        val created = client.tool("create_file", pathArgs().put("requestId", "create-once")
            .put("expectedVersion", missing.getString("version")).put("content", "hello 世界\n"))
        assertEquals("committed", created.getString("outcome"))
        val original = read()
        assertEquals("file", original.getString("kind"))
        assertEquals("hello 世界\n", original.getString("text"))
        assertNotEquals(missing.getString("version"), original.getString("version"))

        val appendArgs = pathArgs().put("requestId", "append-once")
            .put("expectedVersion", original.getString("version")).put("content", "one append\n")
        val appended = client.tool("append_file", appendArgs)
        assertEquals("committed", appended.getString("outcome"))
        val appendedRead = read()
        val expectedText = "hello 世界\none append\n"
        assertEquals(expectedText, appendedRead.getString("text"))
        assertNotEquals(original.getString("version"), appendedRead.getString("version"))

        // A fresh JSON-RPC id with the identical mutation requestId must replay the transaction.
        val replay = client.tool("append_file", appendArgs)
        assertEquals("committed", replay.getString("outcome"))
        assertEquals(appended.getString("transactionId"), replay.getString("transactionId"))
        assertEquals(expectedText, read().getString("text"))
        assertEquals(appendedRead.getString("version"), read().getString("version"))
        assertEquals(appended.getString("transactionId"), history().getJSONObject("undo").getString("id"))

        val conflict = client.tool("append_file", pathArgs().put("requestId", "stale-append")
            .put("expectedVersion", original.getString("version")).put("content", "must not appear"), true)
        assertEquals("rejected", conflict.getString("outcome"))
        assertTrue(conflict.getJSONObject("error").getString("code").contains("conflict", ignoreCase = true))
        assertEquals(expectedText, read().getString("text"))
        assertEquals(appended.getString("transactionId"), history().getJSONObject("undo").getString("id"))

        val transaction = client.tool("get_transaction", scoped()
            .put("transactionId", appended.getString("transactionId")))
        assertEquals("committed", transaction.getString("outcome"))
        assertEquals(appended.getString("transactionId"), transaction.getString("transactionId"))

        val deleted = client.tool("delete_path", pathArgs().put("requestId", "delete-once")
            .put("expectedVersion", appendedRead.getString("version")))
        assertEquals("committed", deleted.getString("outcome"))
        assertEquals("missing", read().getString("kind"))
        assertFalse(File(project, "device.txt").exists())
        val deleteHead = history().getJSONObject("undo").getString("id")
        assertEquals(deleted.getString("transactionId"), deleteHead)
        val undone = client.tool("undo_file_change", scoped().put("requestId", "undo-delete")
            .put("expectedHead", deleteHead))
        assertEquals("committed", undone.getString("outcome"))
        assertEquals(expectedText, read().getString("text"))
        assertEquals(expectedText, File(project, "device.txt").readText(Charsets.UTF_8))
        val finalHistory = history()
        assertEquals(appended.getString("transactionId"), finalHistory.getJSONObject("undo").getString("id"))
        assertEquals(deleteHead, finalHistory.getJSONObject("redo").getString("id"))
    }

    /** Opt-in bridge for a desktop client; the credential is never logged or asserted as text. */
    @Test
    fun externalClient() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("externalClient") == "true")
        withRuntime {
            val tokenFile = File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,
                "mcp-device-token")
            assertTrue("A token handoff file already exists", tokenFile.createNewFile())
            try {
                tokenFile.writeText(McpRuntime.token(), Charsets.UTF_8)
                CountDownLatch(1).await(120, TimeUnit.SECONDS)
            } finally {
                assertTrue("Unable to remove test token handoff", tokenFile.delete())
            }
        }
    }

    private fun withRuntime(block: (File) -> Unit) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertFalse("An MCP runtime is already active", JSONObject(McpRuntime.status()).getBoolean("running"))
        val root = File(context.cacheDir.canonicalFile, "mcp-device-test-${UUID.randomUUID()}")
        try {
            val project = File(root, "project")
            val agentRoot = File(root, "agent")
            assertTrue(project.mkdirs())
            assertTrue(agentRoot.mkdirs())
            val started = JSONObject(McpRuntime.start(context, project.absolutePath, agentRoot.absolutePath, true))
            assertTrue("Runtime failed to start: ${started.optString("error")}", started.getBoolean("running"))
            val status = JSONObject(McpRuntime.status())
            assertTrue(status.getBoolean("running"))
            assertTrue(status.getBoolean("writable"))
            assertEquals(project.absolutePath, status.getString("projectRoot"))
            assertEquals(8765, status.getInt("port"))
            assertEquals("http://127.0.0.1:8765/mcp", status.getString("endpoint"))
            assertTrue("Expected a generated credential", McpRuntime.token().length >= 32)
            block(project)
        } finally {
            try {
                McpRuntime.stop()
            } finally {
                assertTrue("Unable to remove isolated test directories", root.deleteRecursively())
            }
        }
        assertFalse(JSONObject(McpRuntime.status()).getBoolean("running"))
        assertTrue("Credential must be cleared after stop", McpRuntime.token().isEmpty())
    }

    private class Client(private val token: String) {
        private var nextId = 0

        fun rpc(method: String, params: JSONObject = JSONObject()): JSONObject {
            val id = ++nextId
            val response = post(JSONObject().put("jsonrpc", "2.0").put("id", id)
                .put("method", method).put("params", params), 200)
            val envelope = JSONObject(response)
            assertEquals("2.0", envelope.getString("jsonrpc"))
            assertEquals(id, envelope.getInt("id"))
            assertFalse("Unexpected JSON-RPC error: $response", envelope.has("error"))
            return envelope.getJSONObject("result")
        }

        fun initialized() {
            assertEquals("", post(JSONObject().put("jsonrpc", "2.0")
                .put("method", "notifications/initialized"), 202))
        }

        fun tool(name: String, args: JSONObject = JSONObject(), error: Boolean = false): JSONObject {
            val result = rpc("tools/call", JSONObject().put("name", name).put("arguments", args))
            assertEquals("Unexpected tool outcome for $name: $result", error, result.getBoolean("isError"))
            return result.getJSONObject("structuredContent")
        }

        private fun post(body: JSONObject, expectedStatus: Int): String {
            val connection = URL("http://127.0.0.1:8765/mcp").openConnection() as HttpURLConnection
            try {
                connection.requestMethod = "POST"
                connection.connectTimeout = 5_000
                connection.readTimeout = 35_000
                connection.instanceFollowRedirects = false
                connection.doOutput = true
                connection.setRequestProperty("Authorization", "Bearer $token")
                connection.setRequestProperty("Content-Type", "application/json")
                connection.setRequestProperty("Accept", "application/json, text/event-stream")
                connection.setRequestProperty("MCP-Protocol-Version", McpProtocolAdapter.VERSION)
                val bytes = body.toString().toByteArray(Charsets.UTF_8)
                connection.setFixedLengthStreamingMode(bytes.size)
                connection.outputStream.use { it.write(bytes) }
                val status = connection.responseCode
                val stream = if (status >= 400) connection.errorStream else connection.inputStream
                val response = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
                assertEquals("Unexpected HTTP status", expectedStatus, status)
                return response
            } finally {
                connection.disconnect()
            }
        }
    }
}
