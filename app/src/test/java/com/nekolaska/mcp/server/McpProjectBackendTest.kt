package com.nekolaska.mcp.server

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files

class McpProjectBackendTest {
    @Test fun projectBoundaryAndRevocation() {
        val root = Files.createTempDirectory("mcp-scope")
        val scope = McpProjectRegistry(root.toString(), false)
        assertEquals(root.resolve("a.lua"), scope.resolve("a.lua"))
        for (path in listOf("../secret", "/tmp/secret", "a/../../secret", "C:/secret", "a\\secret")) {
            assertTrue(path, runCatching { scope.resolve(path) }.isFailure)
        }
        assertTrue(runCatching { scope.authorize(scope.handle, true) }.isFailure)
        scope.revoke()
        assertTrue(runCatching { scope.resolve("a.lua") }.isFailure)
    }

    @Test fun readVersionsAndConditionalArgumentsReachSharedFacade() {
        val root = Files.createTempDirectory("mcp-files")
        Files.write(root.resolve("main.lua"), "print('hello')".toByteArray())
        val scope = McpProjectRegistry(root.toString(), true)
        var received: JSONObject? = null
        val backend = McpProjectBackend(scope, Files.createTempDirectory("mcp-history").toString(), { _, args, _ ->
            received = args
            JSONObject().put("outcome", "rejected").put("error", "CONFLICT")
        }, { "docs" })
        val args = JSONObject().put("projectHandle", scope.handle).put("path", "main.lua")
        val read = backend.call("read_file", args)
        assertFalse(read.getBoolean("isError"))
        val content = read.getJSONObject("structuredContent")
        assertEquals("main.lua", content.getString("path"))
        assertEquals(64, content.getString("version").length)
        val write = backend.call("append_file", JSONObject(args.toString()).put("requestId", "once")
            .put("expectedVersion", content.getString("version")).put("content", "\n"))
        assertTrue(write.getBoolean("isError"))
        assertEquals(content.getString("version"), received!!.getString("expectedVersion"))
        assertFalse(received!!.has("projectHandle"))
        assertEquals("print('hello')", String(Files.readAllBytes(root.resolve("main.lua"))))
    }

    @Test fun readOnlyCannotInvokeOrListMutationTools() {
        val scope = McpProjectRegistry(Files.createTempDirectory("mcp-readonly").toString(), false)
        val backend = McpProjectBackend(scope, Files.createTempDirectory("mcp-history").toString(), { _, _, _ -> error("Must not execute") }, { "docs" })
        assertFalse(backend.tools().toString().contains("append_file"))
        assertTrue(backend.call("append_file", JSONObject().put("projectHandle", scope.handle)).getBoolean("isError"))
        assertTrue(backend.call("read_file", JSONObject().put("projectHandle", "wrong").put("path", "file")).getBoolean("isError"))
        assertTrue(backend.call("server_info", JSONObject().put("unknown", true)).getBoolean("isError"))
    }
}
