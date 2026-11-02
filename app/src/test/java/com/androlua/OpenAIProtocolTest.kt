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

    @Test
    fun providerCatalogAndBalanceParsing() {
        val assets = sequenceOf(File("src/main/assets"), File("app/src/main/assets"))
            .first { it.isDirectory }
        val globals = JsePlatform.standardGlobals()
        globals.load(json())
        val protocol = globals.load(
            File(assets, "mods/agent/OpenAIProtocol.lua").readText(),
            "@OpenAIProtocol.lua"
        ).call()
        globals.set("OpenAIProtocol", protocol)
        globals.load(File(assets, "mods/agent/AgentChat.lua").readText(), "@AgentChat.lua")

        globals.load(
            """
            assert(OpenAIProtocol.modelsEndpoint("https://api.deepseek.com/v1") == "https://api.deepseek.com/v1/models")
            assert(OpenAIProtocol.modelsEndpoint("https://api.deepseek.com/v1/chat/completions?x=1") == "https://api.deepseek.com/v1/models?x=1")
            local url, kind = OpenAIProtocol.balanceRequest("https://api.deepseek.com/v1")
            assert(url == "https://api.deepseek.com/user/balance")
            assert(kind == "deepseek")
            url, kind = OpenAIProtocol.balanceRequest("https://api.siliconflow.cn/v1")
            assert(url == "https://api.siliconflow.cn/v1/user/info")
            assert(kind == "siliconflow")
            url, kind = OpenAIProtocol.balanceRequest("https://api.moonshot.cn/v1")
            assert(url == "https://api.moonshot.cn/v1/users/me/balance")
            assert(kind == "moonshot")
            url, kind = OpenAIProtocol.balanceRequest("https://openrouter.ai/api/v1")
            assert(url == "https://openrouter.ai/api/v1/credits")
            assert(kind == "openrouter")
            url, kind = OpenAIProtocol.balanceRequest("https://relay.example/v1")
            assert(url == "https://relay.example/v1/dashboard/billing/subscription")
            assert(kind == "subscription")
            assert(OpenAIProtocol.modelsEndpoint("https://token-plan-cn.xiaomimimo.com/v1") == "https://token-plan-cn.xiaomimimo.com/v1/models")
            assert(OpenAIProtocol.balanceRequest("https://api.xiaomimimo.com/v1") == nil)
            assert(OpenAIProtocol.balanceRequest("https://token-plan-sgp.xiaomimimo.com/v1") == nil)
            assert(OpenAIProtocol.balanceRequest("https://token-plan-ams.xiaomimimo.com/v1") == nil)
            local headers = OpenAIProtocol.requestHeaders("https://token-plan-cn.xiaomimimo.com/v1", "tp-test")
            assert(headers["api-key"] == "tp-test")
            assert(headers["Authorization"] == nil)
            headers = OpenAIProtocol.authHeaders("https://api.xiaomimimo.com/v1", "sk-test")
            assert(headers["api-key"] == "sk-test")
            assert(headers["Content-Type"] == nil)
            local cfg = {
              getModel = function() return "mimo-v2.6-pro" end,
              getApiUrl = function() return "https://api.xiaomimimo.com/v1" end,
              getMaxTokens = function() return 1024 end,
              getTemperature = function() return 0.7 end,
              getBuiltinTools = function() return {} end,
              getMcpTools = function() return {} end,
              useResponses = function() return false end,
            }
            local body = OpenAIProtocol.buildRequest(cfg, {
              { role = "user", content = "hi" },
              { role = "assistant", content = "ok", reasoning_content = "think" },
            }, { disableTools = true })
            assert(body.max_completion_tokens == 1024)
            assert(body.max_tokens == nil)
            assert(body.messages[2].reasoning_content == "think")
            assert(OpenAIProtocol.endpoint("https://api.x.ai", true) == "https://api.x.ai/v1/responses")
            assert(OpenAIProtocol.modelsEndpoint("https://api.x.ai") == "https://api.x.ai/v1/models")
            assert(OpenAIProtocol.endpoint("https://api.x.ai/v1/chat/completions", false) == "https://api.x.ai/v1/chat/completions")
            local grok = {
              getModel = function() return "grok-4.6" end,
              getApiUrl = function() return "https://api.x.ai/v1" end,
              getMaxTokens = function() return 2048 end,
              getTemperature = function() return 0.7 end,
              getBuiltinTools = function() return { { type = "function", ["function"] = { name = "read_file", description = "read", parameters = {} } } } end,
              getMcpTools = function() return {} end,
              useResponses = function() return true end,
            }
            local grokBody = OpenAIProtocol.buildRequest(grok, {
              { role = "user", content = "hi" },
            }, {})
            assert(grokBody.max_output_tokens == 2048)
            assert(grokBody.temperature == nil)
            assert(grokBody.include[1] == "reasoning.encrypted_content")
            assert(grokBody.tools[1].name == "read_file")
            assert(grokBody.input[1].role == "user")
            grok.getModel = function() return "grok-3" end
            assert(OpenAIProtocol.buildRequest(grok, { { role = "user", content = "hi" } }, {}).temperature == 0.7)
            json.decode = function(text)
              if text == "models" then
                return { data = { { id = "b" }, { id = "a" }, { id = "a" } } }
              elseif text == "deepseek" then
                return { is_available = true, balance_infos = { { currency = "CNY", total_balance = "10.00", granted_balance = "1.00", topped_up_balance = "9.00" } } }
              elseif text == "openrouter" then
                return { data = { total_credits = 10, total_usage = 2.5 } }
              elseif text == "subscription" then
                return { hard_limit_usd = 3.5 }
              elseif text == "siliconflow" then
                return { data = { balance = "1", chargeBalance = "2", totalBalance = "3" } }
              elseif text == "moonshot" then
                return { data = { available_balance = 4, cash_balance = 3, voucher_balance = 1 } }
              end
              error("unexpected")
            end
            local ids = OpenAIProtocol.parseModelIds("models")
            assert(#ids == 2)
            assert(ids[1] == "a" and ids[2] == "b")
            local balance = OpenAIProtocol.parseBalance("deepseek", "deepseek")
            assert(balance.kind == "deepseek")
            assert(balance.infos[1].currency == "CNY")
            assert(balance.infos[1].total == "10.00")
            assert(balance.infos[1].topped_up == "9.00")
            local credits = OpenAIProtocol.parseBalance("openrouter", "openrouter")
            assert(credits.remaining == "7.5000")
            assert(credits.used == "2.5000")
            local subscription = OpenAIProtocol.parseBalance("subscription", "subscription")
            assert(subscription.amount == "3.5000")
            local silicon = OpenAIProtocol.parseBalance("siliconflow", "siliconflow")
            assert(silicon.total == "3" and silicon.charge == "2" and silicon.gift == "1")
            local moonshot = OpenAIProtocol.parseBalance("moonshot", "moonshot")
            assert(moonshot.available == "4" and moonshot.cash == "3" and moonshot.voucher == "1")
            """.trimIndent(),
            "@provider_catalog_test"
        ).call()
    }

    @Test
    fun cpaGeminiCompatAndSchemaSanitization() {
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
            -- 1. 只有 system 消息时，必须自动补齐 user 消息，避免 Gemini 映射为 system_instruction 后 contents 变成空数组报 400
            local cfgGemini = {
              getModel = function() return "gemini-2.5-flash" end,
              getApiUrl = function() return "https://api.relay.example/v1" end,
              getMaxTokens = function() return 2048 end,
              getTemperature = function() return 0.7 end,
              getBuiltinTools = function() return {} end,
              getMcpTools = function() return {} end,
              useResponses = function() return false end,
            }
            local req1 = OpenAIProtocol.buildRequest(cfgGemini, {
              { role = "system", content = "You are a helpful assistant" },
            }, {})
            assert(#req1.messages == 2, "req1 size: " .. tostring(#req1.messages))
            assert(req1.messages[1].role == "system")
            assert(req1.messages[2].role == "user")
            assert(req1.messages[2].content == "...")

            -- 2. system 消息 + 尾随 assistant（在 Gemini 目标下被裁剪）后，仍然保证有 user 消息
            local req2 = OpenAIProtocol.buildRequest(cfgGemini, {
              { role = "system", content = "You are a helpful assistant" },
              { role = "assistant", content = "previous reply" },
            }, {})
            assert(#req2.messages == 2, "req2 size: " .. tostring(#req2.messages))
            assert(req2.messages[1].role == "system")
            assert(req2.messages[2].role == "user")
            assert(req2.messages[2].content == "...")

            -- 3. tool_calls 中的 arguments 无论为空串、nil、空白或非 object，均规整化为合法的 "{}" JSON 字符串
            -- android.jar's org.json is a stub in local JVM tests. Supply a
            -- deterministic decoder fixture rather than weakening production validation.
            json.decode = function(text)
              if text == '{"k":"v"}' then return { k = "v" } end
              if text == '{}' then return {} end
              error("Invalid JSON fixture: " .. tostring(text))
            end
            local req3 = OpenAIProtocol.buildRequest(cfgGemini, {
              { role = "user", content = "run" },
              {
                role = "assistant",
                tool_calls = {
                  { id = "c1", type = "function", ["function"] = { name = "t1", arguments = "" } },
                  { id = "c2", type = "function", ["function"] = { name = "t2", arguments = "   " } },
                  { id = "c4", type = "function", ["function"] = { name = "t4", arguments = "{\"k\":\"v\"}" } },
                }
              },
              { role = "tool", tool_call_id = "c1", content = "" },
              { role = "tool", tool_call_id = "c2", content = "res2" },
              { role = "tool", tool_call_id = "c4", content = "res4" },
            }, {})
            local tcs = req3.messages[2].tool_calls
            assert(tcs[1]["function"].arguments == "{}", "tc1 args: " .. tostring(tcs[1]["function"].arguments))
            assert(tcs[2]["function"].arguments == "{}", "tc2 args: " .. tostring(tcs[2]["function"].arguments))
            assert(tcs[3]["function"].arguments == "{\"k\":\"v\"}", "tc3 args: " .. tostring(tcs[3]["function"].arguments))
            local invalid = OpenAIProtocol.buildRequest(cfgGemini, {
              { role = "user", content = "run" },
              { role = "assistant", tool_calls = {
                { id = "bad", type = "function", ["function"] = { name = "t", arguments = '{"x":}' } },
              } },
              { role = "tool", tool_call_id = "bad", content = "failed" },
            }, {})
            assert(invalid.messages[2].tool_calls[1]["function"].arguments == '{}')
            local continued = OpenAIProtocol.buildRequest(cfgGemini, {
              { role = "user", content = "question" },
              { role = "assistant", content = "partial answer", continuation_state = "stopped" },
            }, {})
            assert(continued.messages[2].content == "partial answer")
            assert(continued.messages[2].continuation_state == nil)
            assert(continued.messages[3].role == "user")
            -- 验证 role="tool" 自动关联了函数名 name，空 content 规整为 "{}"
            assert(req3.messages[3].role == "tool" and req3.messages[3].name == "t1" and req3.messages[3].content == "{}")
            assert(req3.messages[4].role == "tool" and req3.messages[4].name == "t2" and req3.messages[4].content == "res2")

            -- 4. tools 定义中缺少 properties 或 parameters 为空 table 时，自动加固为包含 type="object" 和 properties={}
            local cfgTools = {
              getModel = function() return "gpt-4o" end,
              getApiUrl = function() return "https://api.relay.example/v1" end,
              getMaxTokens = function() return 2048 end,
              getTemperature = function() return 0.7 end,
              getBuiltinTools = function()
                return {
                  { type = "function", ["function"] = { name = "tool_no_params" } },
                  { type = "function", ["function"] = { name = "tool_empty_params", parameters = {} } },
                  { type = "function", ["function"] = { name = "tool_no_props", parameters = { type = "object" } } },
                }
              end,
              getMcpTools = function() return {} end,
              useResponses = function() return false end,
            }
            local req4 = OpenAIProtocol.buildRequest(cfgTools, {
              { role = "user", content = "hi" }
            }, {})
            assert(#req4.tools == 3)
            for i = 1, 3 do
              local fn = req4.tools[i]["function"]
              assert(fn.parameters ~= nil)
              assert(fn.parameters.type == "object")
              assert(type(fn.parameters.properties) == "table")
            end

            -- 5. 孤立 tool 消息（无对应 assistant tool_calls）平滑降级为 user 消息避免上游 400
            local req5 = OpenAIProtocol.buildRequest(cfgGemini, {
              { role = "tool", tool_call_id = "orphan_call", content = "orphan result" },
            }, {})
            local orphanFound = false
            for _, m in ipairs(req5.messages) do
              if m.role == "user" and tostring(m.content):find("orphan result") ~= nil then
                orphanFound = true
                break
              end
            end
            if not orphanFound then
              local dump = ""
              for i, m in ipairs(req5.messages) do
                dump = dump .. "[" .. i .. "] role=" .. tostring(m.role) .. " content=" .. tostring(m.content) .. "; "
              end
              error("req5 dump: " .. dump)
            end
            assert(orphanFound, "orphan tool message should be downgraded to user turn")
            """.trimIndent(),
            "@cpa_gemini_compat_test"
        ).call()
    }
}
