package com.androlua

import org.junit.Test
import org.luaj.android.json
import org.luaj.lib.jse.JsePlatform
import java.io.File

class OpenAIProtocolTest {

    @Test
    fun legacyFunctionCallsUseFunctionResultHistory() {
        val assets = sequenceOf(File("src/main/assets"), File("app/src/main/assets"))
            .first { it.isDirectory }
        val globals = JsePlatform.standardGlobals()
        globals.load(json())
        val protocol = globals.load(
            File(assets, "mods/agent/OpenAIProtocol.lua").readText(),
            "@OpenAIProtocol.lua"
        ).call()
        globals.set("OpenAIProtocol", protocol)

        globals.load(
            """
            local cfg = {
              getModel = function() return "compat-model" end,
              getApiUrl = function() return "https://relay.example/v1" end,
              getMaxTokens = function() return 1024 end,
              getTemperature = function() return 0.7 end,
              getBuiltinTools = function() return { { type = "function", ["function"] = { name = "read_file", parameters = {} } } } end,
              getMcpTools = function() return {} end,
              useResponses = function() return false end,
            }
            local messages = {
              { role = "system", content = "system" },
              {
                role = "assistant",
                legacy_function_call = true,
                tool_calls = {
                  { id = "call_0", type = "function", ["function"] = { name = "read_file", arguments = "{\"path\":\"main.lua\"}" } },
                },
              },
              { role = "tool", tool_call_id = "call_0", content = "file contents" },
            }
            local body = OpenAIProtocol.buildRequest(cfg, messages, {})
            assert(#body.messages == 3)
            assert(body.messages[2].role == "assistant")
            assert(body.messages[2].function_call.name == "read_file")
            assert(body.messages[2].tool_calls == nil)
            assert(body.messages[3].role == "function")
            assert(body.messages[3].name == "read_file")
            assert(body.messages[3].content == "file contents")
            assert(body.functions[1].name == "read_file")
            assert(body.tools == nil)
            assert(body.function_call == "auto")
            """.trimIndent(),
            "@legacy_function_call_protocol_test"
        ).call()
    }

    @Test
    fun modernToolCallsKeepToolResultHistory() {
        val assets = sequenceOf(File("src/main/assets"), File("app/src/main/assets"))
            .first { it.isDirectory }
        val globals = JsePlatform.standardGlobals()
        globals.load(json())
        val protocol = globals.load(
            File(assets, "mods/agent/OpenAIProtocol.lua").readText(),
            "@OpenAIProtocol.lua"
        ).call()
        globals.set("OpenAIProtocol", protocol)

        globals.load(
            """
            local cfg = {
              getModel = function() return "compat-model" end,
              getApiUrl = function() return "https://relay.example/v1" end,
              getMaxTokens = function() return 1024 end,
              getTemperature = function() return 0.7 end,
              getBuiltinTools = function() return { { type = "function", ["function"] = { name = "read_file", parameters = {} } } } end,
              getMcpTools = function() return {} end,
              useResponses = function() return false end,
            }
            local messages = {
              { role = "system", content = "system" },
              {
                role = "assistant",
                tool_calls = {
                  { id = "call_0", type = "function", ["function"] = { name = "read_file", arguments = "{\"path\":\"main.lua\"}" } },
                },
              },
              { role = "tool", tool_call_id = "call_0", content = "file contents" },
            }
            local body = OpenAIProtocol.buildRequest(cfg, messages, {})
            assert(#body.messages == 3)
            assert(body.messages[2].role == "assistant")
            assert(body.messages[2].tool_calls[1].id == "call_0")
            assert(body.messages[3].role == "tool")
            assert(body.messages[3].tool_call_id == "call_0")
            assert(body.functions == nil)
            assert(body.function_call == nil)
            """.trimIndent(),
            "@modern_tool_call_protocol_test"
        ).call()
    }

}
