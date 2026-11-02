-- Real registry/schema/executor modules; no Android or network access required.
local assets = ASSETS or "app/src/main/assets/"
package.path = assets .. "?.lua;" .. package.path
local registry = require("mods.agent.ToolRegistry")
local schemas = assert(loadfile(assets .. "mods/agent/ToolSchemas.lua"))()
local executor = assert(loadfile(assets .. "mods/agent/ToolExecutor.lua"))()
local function check(name, value)
  assert(value, name)
  print("PASS " .. name)
end

-- Snapshot the intentional categories, rather than merely testing a registry
-- against itself (notably run/build and todos/subtask are NOT destructive).
local expected = {
  create_file = "create_file", create_folder = "project_write",
  delete_file = "project_write", delete_folder = "project_write",
  read_file = "project_read", read_files = "project_read",
  list_dir = "project_read", search_in_files = "project_read",
  check_lua_syntax = "pure", layout_describe = "pure", layout_check = "project_read",
  run_lua = "sandbox", run_project = "always_confirm", build_project = "always_confirm",
  fetch_url = "network", apply_patch = "project_write", replace_in_file = "project_write",
  append_file = "project_write", rename_file = "project_write",
  update_todos = "policy_only", run_subtask = "policy_only", get_env_info = "pure",
}
local seen, count = {}, 0
for index, entry in ipairs(registry.entries) do
  assert(not seen[entry.name], "duplicate name: " .. entry.name)
  seen[entry.name] = true
  assert(registry.get(entry.name) == entry)
  assert(entry.approval == expected[entry.name], "unexpected policy: " .. entry.name)
  assert(type(entry.labelKey) == "string" and entry.labelKey ~= "")
  assert(type(entry.readOnly) == "boolean" and type(entry.destructive) == "boolean")
  assert(type(entry.parallelSafe) == "boolean")
  assert(not entry.parallelSafe or (entry.readOnly and not entry.destructive))
  assert(entry.trustedDocs == (entry.name == "read_file" or entry.name == "read_files"))
  assert(schemas[index] == entry.schema and entry.schema["function"].name == entry.name)
  assert(entry.schema.type == "function" and entry.schema["function"].parameters.type == "object")
  assert(entry.schema.approval == nil and entry.schema.labelKey == nil, "metadata leaked to public schema")
  assert(executor.isDestructiveTool(entry.name) == entry.destructive)
  assert(executor.isParallelSafe(entry.name) == entry.parallelSafe)
  count = count + 1
end
for name in pairs(expected) do assert(seen[name], "missing schema: " .. name) end
check("all 22 schemas have unique names and complete policy/parallel metadata", count == 22 and #schemas == count)

-- Execute the real translation files and verify every registry key in both locales.
for _, locale in ipairs({ "en", "zh" }) do
  assert(loadfile(assets .. "res/string/" .. locale .. ".lua"))()
  local strings = {}
  for _, entry in ipairs(registry.entries) do
    local label = _G[entry.labelKey]
    assert(type(label) == "string" and label ~= "", locale .. " missing " .. entry.labelKey)
    strings[entry.labelKey] = label
    assert(registry.displayName(entry.name, strings) == label)
  end
end
check("real English and Chinese labels cover every built-in", registry.displayName("mcp::custom::x", {}) == "mcp::custom::x")
check("missing translation retains raw name", registry.displayName("read_file", {}) == "read_file")

local handlers = {}
for _, entry in ipairs(registry.entries) do
  local name = entry.name
  registry.register(handlers, name, function(args) return name .. ":" .. tostring(args.value), args.ok end)
end
check("duplicate handler rejected", not pcall(registry.register, handlers, "read_file", function() end))
check("unknown handler rejected", not pcall(registry.register, handlers, "not_a_tool", function() end))
check("incomplete handler map rejected", not pcall(registry.bind, {}))
local dispatch = registry.bind(handlers)
for _, entry in ipairs(registry.entries) do
  for _, status in ipairs({ true, false, "legacy" }) do
    local ok = status ~= "legacy" and status or nil
    if status == false then ok = false end
    local result, actual = dispatch(entry.name, { value = 42, ok = ok })
    assert(result == entry.name .. ":42" and actual == ok, "status lost: " .. entry.name)
  end
end
check("bound handlers cover schemas and retain true/false/nil status", true)

local settings = { ai_auto_approve = "1", ai_auto_approve_network = "1", ai_auto_run_sandbox = "1" }
local policy = {}
local function resolve(path)
  if path:sub(1, 1) == "/" then return path end
  return "/project/" .. path
end
local cfg = {
  getProjectDir = function() return "/project" end,
  resolvePath = resolve,
  canonicalPath = function(path)
    if path == "/project/link.lua" then return "/private/secret.lua" end
    return resolve(path)
  end,
  getPathType = function(path)
    if path == "/project/existing.lua" or path == "/project/main.lua" then return "file" end
  end,
  isTrustedReadPath = function(path) return path:sub(1, 9) == "/app/doc/" end,
  getSharedData = function(key, fallback) return settings[key] or fallback end,
  getProjectPolicy = function() return policy end,
  platformExecute = dispatch,
}
executor.configure(cfg)
local function approval(name, args, confirm, auto)
  assert(executor.requiresConfirmation(name, args) == confirm, name .. " confirmation changed")
  assert(executor.shouldAutoApprove(name, args) == auto, name .. " auto approval changed")
end
for _, name in ipairs({ "read_file", "list_dir", "search_in_files", "layout_check" }) do
  approval(name, { path = "/project/main.lua" }, false, true)
  for _, path in ipairs({ "/private/x", "/project-other/x", "/project/link.lua", "missing.lua" }) do
    approval(name, { path = path }, true, false)
  end
end
approval("read_file", { path = "/app/doc/sandbox_zh.html" }, false, true)
approval("read_files", { paths = { "/project/main.lua", "/app/doc/sandbox_en.html" } }, false, true)
approval("read_files", { paths = { "/project/main.lua", "/private/x" } }, true, false)
approval("read_files", { paths = {} }, true, false)
for _, name in ipairs({ "list_dir", "search_in_files", "layout_check" }) do
  approval(name, { path = "/app/doc/sandbox_zh.html" }, true, false)
end
check("project reads honor canonical boundaries; trusted docs exempt ONLY read_file/read_files", true)

for _, name in ipairs({ "run_project", "build_project" }) do
  approval(name, { path = "/project/main.lua" }, true, false)
  assert(not executor.isDestructiveTool(name))
end
for _, name in ipairs({ "update_todos", "run_subtask" }) do
  approval(name, {}, false, false)
  assert(not executor.isDestructiveTool(name) and not executor.isParallelSafe(name))
end
for _, name in ipairs({ "layout_describe", "check_lua_syntax", "get_env_info" }) do approval(name, {}, false, true) end
approval("unknown_tool", {}, false, false)
approval("create_file", { path = "existing.lua" }, true, false)
approval("create_file", { path = "/project/new.lua" }, true, true)
approval("create_file", { path = "/private/new.lua" }, true, false)
for _, entry in ipairs(registry.entries) do
  if entry.approval == "project_write" then
    approval(entry.name, { path = "/project/main.lua", new_path = "/project/new.lua" }, true, true)
    approval(entry.name, { path = "/app/doc/agent_docs.md", new_path = "/app/doc/new.md" }, true, false)
  end
end
approval("rename_file", { path = "/project/main.lua", new_path = "/private/new.lua" }, true, false)
approval("rename_file", { path = "/project/main.lua", new_path = "/project/new.lua" }, true, true)
policy.autoApprove = false
approval("apply_patch", { path = "/project/main.lua" }, true, false)
approval("read_file", { path = "/project/main.lua" }, false, true)
approval("update_todos", {}, false, false)
policy.autoApprove = nil
settings.ai_auto_approve = "0"
approval("create_file", { path = "/project/new.lua" }, true, false)
settings.ai_auto_approve = "1"
check("overwrite, write settings, rename and policy-only semantics are unchanged", true)

executor.setSandboxDocRead(false)
approval("run_lua", { code = "return 1" }, true, false)
executor.setSandboxDocRead(true)
approval("run_lua", { code = "return 1" }, false, true)
-- Existing execution validates malformed declarations; approval must not invent
-- a new policy path for them during this registry-only refactor.
approval("run_lua", { network_hosts = { host = "example.com" } }, false, true)
approval("run_lua", { network_hosts = { [2] = "example.com" } }, false, true)
approval("run_lua", { network_hosts = { "  " } }, false, true)
settings.ai_auto_run_sandbox = "0"
approval("run_lua", { code = "return 1" }, true, false)
settings.ai_auto_run_sandbox = "1"
settings.ai_auto_approve_network = "0"
approval("run_lua", { network_hosts = { "docs.example.com" } }, true, false)
approval("run_lua", {}, false, true)
approval("fetch_url", { url = "https://docs.example.com" }, true, false)
settings.ai_auto_approve_network = "1"
policy.networkHosts = { "example.com" }
approval("fetch_url", { url = "https://docs.example.com/path" }, false, true)
approval("fetch_url", { url = "https://badexample.com" }, true, false)
approval("run_lua", { network_hosts = { "example.com", "other.test" } }, true, false)
approval("run_lua", { network_hosts = { "docs.example.com" } }, false, true)
check("sandbox prior-document and network allowlist/settings restrictions remain intact", true)

settings.ai_auto_approve_network = "0"
policy.autoApprove = false
for _, name in ipairs({ "mcp::server::custom", "mcp__custom_route" }) do
  approval(name, { path = "/private/secret", url = "https://other.test" }, false, true)
  assert(executor.isDestructiveTool(name) and not executor.isParallelSafe(name))
end
local server = {}
cfg.resolveMcpTool = function(name)
  if name == "mcp__custom_route" then return { server = server, tool = "custom" } end
end
cfg.callMcpTool = function(actualServer, tool, args)
  assert(actualServer == server and tool == "custom" and args.path == "/private/secret")
  return "custom MCP result"
end
local text, ok = executor.executeTool("mcp__custom_route", { path = "/private/secret" })
check("MCP custom routing and unconditional approval stay independent of built-in policy", text == "custom MCP result" and ok == true)
text, ok = executor.executeTool("ReadFile", { value = 7, ok = false })
check("public executeTool API still normalizes names and preserves structured failure", text == "read_file:7" and ok == false)
executor.setSandboxDocRead(false)
print("ALL-PASS")
