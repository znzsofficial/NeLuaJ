-- Agent policy, schema and dispatch regression; Android rendering belongs in device tests.
local assets = ASSETS or "app/src/main/assets/"
package.path = assets .. "?.lua;" .. package.path
local executor = assert(loadfile(assets .. "mods/agent/ToolExecutor.lua"))()
executor.configure({
  getProjectDir = function() return "/project" end,
  canonicalPath = function(path)
    if path == "/project/link.lua" then return "/private/secret.lua" end
    if path:sub(1, 1) == "/" then return path end
    return "/project/" .. path
  end,
  getPathType = function(path) if path == "/project/main.lua" then return "file" end end,
})
assert(executor.shouldAutoApprove("layout_describe", { widget = "TextView" }))
assert(not executor.requiresConfirmation("layout_describe", {}))
assert(executor.shouldAutoApprove("layout_check", { path = "/project/main.lua" }))
assert(not executor.requiresConfirmation("layout_check", { path = "/project/main.lua" }))
for _, path in ipairs({ "/private/secret.lua", "/project-other/main.lua", "/project/link.lua" }) do
  assert(executor.requiresConfirmation("layout_check", { path = path }))
  assert(not executor.shouldAutoApprove("layout_check", { path = path }))
end
assert(executor.isParallelSafe("layout_describe"))
assert(executor.isParallelSafe("layout_check"))
assert(not executor.isDestructiveTool("layout_check"))
print("PASS layout tools follow read-only project approval including canonical paths")

local schemas = assert(loadfile(assets .. "mods/agent/ToolSchemas.lua"))()
local names = {}
for _, tool in ipairs(schemas) do names[tool["function"].name] = tool["function"] end
assert(names.layout_describe.parameters.required[1] == "widget")
assert(names.layout_check.parameters.required[1] == "path")
assert(names.layout_check.parameters.properties.code == nil, "file check must not silently switch to executing inline code")
print("PASS layout tool schemas expose actual supported arguments")

-- Compose the real AgentChat with inert service doubles and capture its platform dispatch.
local captured = {}
local noop = function() end
for _, name in ipairs({ "MCPClient", "ChangeSet", "AgentStorage", "ConversationStore", "ContextManager",
    "OpenAIClient", "OpenAIProtocol", "SkillManager", "TodoManager", "PatchEngine", "SubagentRunner", "ModelRegistry" }) do
  package.loaded["mods.agent." .. name] = { configure = noop }
end
package.loaded["mods.agent.ToolSchemas"] = schemas
package.loaded["mods.agent.ToolExecutor"] = {
  configure = function(config) captured = config end,
  normalizeToolName = executor.normalizeToolName,
}
local calls, lastReport = {}, nil
local layoutTools = {
  describe = function(widget, parent)
    calls[#calls + 1] = { "describe", widget, parent }
    return { knownWidget = true }
  end,
  checkFile = function(path, parent)
    calls[#calls + 1] = { "checkFile", path, parent }
    return { hasErrors = path:find("bad", 1, true) ~= nil, complete = false }
  end,
}
luajava = { bindClass = function(name)
  if name == "com.androlua.layout.LayoutTools" then return layoutTools end
  return setmetatable({}, { __call = function() return {} end })
end, kotlinObject = function() return {} end }
activity = { getLuaDir = function() return "/project" end }
this = { getSharedData = function(_, fallback) return fallback end }
Bean = { Path = { this_dir = "/project" } }
res = { string = {} }
json = { encode = function(report) lastReport = report; return "encoded report" end }
assert(loadfile(assets .. "mods/agent/AgentChat.lua"))()
local text, ok = captured.platformExecute("layout_describe", { widget = "TextView", parent = "LinearLayout" })
assert(ok and text == "encoded report" and calls[1][1] == "describe" and calls[1][2] == "TextView")
text, ok = captured.platformExecute("layout_check", { path = "main.lua" })
assert(ok and calls[2][2] == "/project/main.lua" and calls[2][3] == "")
assert(lastReport.complete == false, "unknown result must stay visible in JSON")
text, ok = captured.platformExecute("layout_check", { path = "bad.lua" })
assert(ok == false and lastReport.hasErrors)
local before = #calls
text, ok = captured.platformExecute("layout_check", {})
assert(ok == false and #calls == before)
print("PASS real AgentChat dispatch returns structured status without running layout source")
print("ALL-PASS")
