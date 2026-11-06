local ASSETS = ASSETS or "app/src/main/assets/"
package.path = ASSETS .. "?.lua;" .. package.path
-- Execute the real bridge; Android, codec and mutation/editor IO are boundaries.
local messages, serial = {}, 0
local codec = {
  encode = function(value)
    serial = serial + 1
    local key = "encoded:" .. serial
    messages[key] = value
    return key
  end,
  decode = function(key) return assert(messages[key], "invalid JSON") end,
}
package.loaded.json = codec
local registered, unregistered, reconciled, finished, refreshed, invalidated = 0, 0, 0, 0, 0, 0
activity = { invalidateOptionsMenu = function() invalidated = invalidated + 1 end }
MainActivity = { RecyclerView = { update = function() refreshed = refreshed + 1 end } }
luajava = { bindClass = function(name)
  if name == "java.util.UUID" then return { randomUUID = function() return "host-id" end } end
  assert(name == "com.nekolaska.mcp.server.McpMutationHost")
  return {
    registerEditor = function(host) assert(host == activity); registered = registered + 1 end,
    unregisterEditor = function(host) assert(host == activity); unregistered = unregistered + 1 end,
  }
end }
local scope, current, prepareMode = "/p", true, "ok"
local context = {
  snapshot = function() return { scopePath = scope } end,
  isCurrent = function(value, kind) assert(value.scopePath == "/p" and kind == "project"); return current end,
}
package.loaded["mods.project.ProjectContext"] = context
local snapshot = { scope = { scopePath = "/p" }, buffer = "UI-only" }
local result = { outcome = "committed" }
local editor = {
  prepareFileOperation = function(name, args, token)
    assert(name == "write_file" and args.path == "a.lua" and token == "lock")
    if prepareMode == "throw" then error("save failed") end
    if prepareMode == "nil" then return nil end
    return snapshot
  end,
  captureRecovery = function(value) assert(value == result); return snapshot end,
  finishFileOperation = function(value, outcome)
    assert(value == snapshot and outcome == result)
    finished = finished + 1
    return true
  end,
}
package.loaded["mods.utils.EditorUtil"] = editor
package.loaded["mods.agent.AgentStorage"] = {}
package.loaded["mods.files.FileMutationService"] = { new = function(options)
  assert(options.context == context and options.prepareRecovery == editor.captureRecovery)
  return { reconcilePending = function() reconciled = reconciled + 1 end }
end }
local bridge = assert(loadfile(ASSETS .. "mods/mcp/EditorBridge.lua"))()
local function dispatch(request)
  request.scopePath = request.scopePath or "/p"
  return codec.decode(bridge.dispatch(codec.encode(request)))
end
local function prepare()
  return dispatch({ action = "prepare", name = "write_file", args = { path = "a.lua" }, token = "lock" })
end
local function finish(key) return dispatch({ action = "finish", snapshot = key, result = result }) end
bridge.register()
assert(registered == 1 and reconciled == 1)
local captured = prepare()
assert(type(captured.snapshot) == "string" and captured.buffer == nil and captured.scope == nil,
  "only an opaque snapshot identity may cross the worker boundary")
assert(finish(captured.snapshot).synced and finished == 1 and refreshed == 1 and invalidated == 1)
assert(finish(captured.snapshot).message == "editor_binding_stale" and finished == 1,
  "finish must consume the snapshot exactly once")
captured = prepare()
current = false
assert(finish(captured.snapshot).message == "editor_binding_stale" and finished == 1)
current = true
assert(finish(captured.snapshot).message == "editor_binding_stale")
assert(dispatch({ action = "prepare", scopePath = "/other" }).message == "scope_stale")
assert(dispatch({ action = "unknown" }).message == "unknown_editor_action")
assert(codec.decode(bridge.dispatch("broken")).error)
prepareMode = "throw"
assert(prepare().error and finished == 1)
prepareMode = "nil"
assert(prepare().snapshot == nil)
prepareMode = "ok"
captured = dispatch({ action = "recovery", result = result })
assert(finish(captured.snapshot).synced and finished == 2)
captured = prepare()
bridge.unregister()
assert(unregistered == 1 and finish(captured.snapshot).message == "editor_binding_stale")
bridge.register()
assert(registered == 2 and reconciled == 2)
captured = prepare()
for i = 1, 64 do prepare() end
assert(finish(captured.snapshot).message == "editor_binding_stale",
  "unclaimed snapshot retention must be bounded")
assert(finish(prepare().snapshot).synced and finished == 3)
print("ALL-PASS actual MCP editor bridge lifecycle, opaque bounded snapshots, stale/replayed finishes and error responses")
