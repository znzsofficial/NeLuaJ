package com.androlua

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.luaj.lib.jse.JsePlatform
import java.io.File

class AgentToolExecutorVerificationTest {
    @Test
    fun sandboxDocumentationIsRequiredBeforeRunLua() {
        val assets = sequenceOf(File("src/main/assets"), File("app/src/main/assets"))
            .first { it.isDirectory }
        val source = File(assets, "mods/agent/AgentChat.lua").readText()
        val systemPrompt = source.substringBefore("function _M.getSystemPrompt")
        val runLuaTool = source.substringAfter("name = \"run_lua\"")
            .substringBefore("name = \"fetch_url\"")

        for (section in listOf(systemPrompt, runLuaTool)) {
            assertTrue(section.contains("read_file"))
            assertTrue(section.contains("res/doc/sandbox_zh.html"))
            assertTrue(section.contains("res/doc/sandbox_en.html"))
        }
        assertTrue(systemPrompt.contains("当前会话上下文尚未包含沙盒文档"))
        assertTrue(runLuaTool.contains("不得猜测 API"))
    }

    @Test
    fun trustedDocumentationApprovalIsLimitedToReadTools() {
        val assets = sequenceOf(File("src/main/assets"), File("app/src/main/assets"))
            .first { it.isDirectory }
        val globals = JsePlatform.standardGlobals()
        val toolExecutor = globals.load(
            File(assets, "mods/agent/ToolExecutor.lua").readText(),
            "@ToolExecutor.lua"
        ).call()
        globals.set("ToolExecutor", toolExecutor)

        globals.load(
            File(assets, "mods/agent/AgentChat.lua").readText(),
            "@AgentChat.lua"
        )
        globals.load(
            File(assets, "mods/agent/ChatUI.lua").readText(),
            "@ChatUI.lua"
        )
        globals.load(
            """
            local networkAutoApprove = "1"
            ToolExecutor.configure({
              canonicalPath = function(path)
                if path:sub(1, 1) == "/" then return path end
                return "/project/" .. path
              end,
              normalizePath = function(path) return path end,
              getProjectDir = function() return "/project" end,
              getPathType = function(path)
                if path == "/project/main.lua" then return "file" end
              end,
              isTrustedReadPath = function(path)
                return path == "res/doc/agent_docs.md"
                  or path == "/app/res/doc/agent_docs.md"
              end,
              getSharedData = function(key, defaultValue)
                if key == "ai_auto_approve_network" then return networkAutoApprove end
                return defaultValue or "0"
              end,
            })

            local doc = { path = "res/doc/agent_docs.md" }
            assert(ToolExecutor.shouldAutoApprove("read_file", doc))
            assert(not ToolExecutor.requiresConfirmation("read_file", doc))
            assert(ToolExecutor.shouldAutoApprove("read_files", {
              paths = { "/app/res/doc/agent_docs.md", "/project/main.lua" },
            }))
            assert(not ToolExecutor.shouldAutoApprove("read_files", {
              paths = { "/app/res/doc/agent_docs.md", "/private/secret" },
            }))
            assert(ToolExecutor.requiresConfirmation("read_files", {
              paths = { "/app/res/doc/agent_docs.md", "/private/secret" },
            }))
            assert(not ToolExecutor.shouldAutoApprove("list_dir", {
              path = "/app/res/doc",
            }))
            assert(ToolExecutor.requiresConfirmation("list_dir", {
              path = "/app/res/doc",
            }))
            assert(ToolExecutor.requiresConfirmation("create_file", {
              path = "/app/res/doc/new.md",
            }))
            local fetch = {
              url = "https://example.com",
            }
            local networkedLua = {
              code = "return http.request('https://example.com')",
              network_hosts = { "example.com" },
            }
            local localLua = { code = "return 1" }
            local malformedNetworkedLua = {
              code = "return 1",
              network_hosts = { host = "example.com" },
            }
            local sparseNetworkedLua = {
              code = "return 1",
              network_hosts = { [2] = "example.com" },
            }
            local blankNetworkedLua = {
              code = "return 1",
              network_hosts = { "  " },
            }
            local mcp = "mcp::context7::query"

            local normalizedHosts = ToolExecutor.normalizeNetworkHosts({ " example.com ", "", "api.example.com" })
            assert(#normalizedHosts == 2)
            assert(normalizedHosts[1] == "example.com")
            assert(normalizedHosts[2] == "api.example.com")
            assert(ToolExecutor.normalizeNetworkHosts({ host = "example.com" }) == nil)
            assert(ToolExecutor.normalizeNetworkHosts({ [2] = "example.com" }) == nil)

            assert(ToolExecutor.shouldAutoApprove("fetch_url", fetch))
            assert(not ToolExecutor.requiresConfirmation("fetch_url", fetch))
            assert(ToolExecutor.shouldAutoApprove("run_lua", networkedLua))
            assert(not ToolExecutor.requiresConfirmation("run_lua", networkedLua))
            assert(not ToolExecutor.shouldAutoApprove("run_lua", localLua))
            assert(ToolExecutor.requiresConfirmation("run_lua", localLua))
            assert(not ToolExecutor.shouldAutoApprove("run_lua", malformedNetworkedLua))
            assert(ToolExecutor.requiresConfirmation("run_lua", malformedNetworkedLua))
            assert(not ToolExecutor.shouldAutoApprove("run_lua", sparseNetworkedLua))
            assert(ToolExecutor.requiresConfirmation("run_lua", sparseNetworkedLua))
            assert(not ToolExecutor.shouldAutoApprove("run_lua", blankNetworkedLua))
            assert(ToolExecutor.requiresConfirmation("run_lua", blankNetworkedLua))
            assert(ToolExecutor.shouldAutoApprove(mcp, {}))
            assert(not ToolExecutor.requiresConfirmation(mcp, {}))

            networkAutoApprove = "0"
            assert(not ToolExecutor.shouldAutoApprove("fetch_url", fetch))
            assert(ToolExecutor.requiresConfirmation("fetch_url", fetch))
            assert(not ToolExecutor.shouldAutoApprove("run_lua", networkedLua))
            assert(ToolExecutor.requiresConfirmation("run_lua", networkedLua))
            assert(not ToolExecutor.shouldAutoApprove(mcp, {}))
            assert(ToolExecutor.requiresConfirmation(mcp, {}))
            """.trimIndent(),
            "@trusted_doc_policy_test"
        ).call()
    }

    @Test
    fun documentationCatalogListsEveryBundledFile() {
        val docs = sequenceOf(File("src/main/assets/res/doc"), File("app/src/main/assets/res/doc"))
            .first { it.isDirectory }
        val catalog = File(docs, "agent_docs.md").readText()
        val documented = Regex("`res/doc/([^`]+)`")
            .findAll(catalog)
            .map { it.groupValues[1] }
            .toSet()
        val bundled = docs.walkTopDown()
            .filter(File::isFile)
            .map { it.relativeTo(docs).invariantSeparatorsPath }
            .toSet()

        assertEquals(bundled, documented)
    }

}
