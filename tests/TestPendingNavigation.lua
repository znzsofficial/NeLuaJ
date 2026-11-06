local assets = ASSETS or "app/src/main/assets/"
package.path = assets .. "?.lua;" .. package.path
local noop = function() end
package.loaded["mods.mcp.EditorBridge"] = { register = noop, unregister = noop, dispatch = noop }
_G["import"] = noop
bindClass = function() return {} end
res = { string = setmetatable({}, { __index = function(_, k) return k end }) }
local data = {}
this = {
  getSharedData = function(key, fallback) local v = data[key]; if v == nil then return fallback end; return v end,
  setSharedData = function(key, value) data[key] = value; return true end,
}
activity = { getLuaDir = function() return "/assets/activities/main" end }
package.loaded["com.google.android.material.dialog.MaterialAlertDialogBuilder"] = {}
local nav = require "mods.utils.ActivityUtil"
assert(nav.path("editor") == "/assets/activities/main/MainActivity.lua")
for _, result in ipairs({ false, "nil", "throw" }) do
  assert(nav.setPending("open_agent_conv", "a"))
  local p = nav.peekPending()
  local calls = 0
  local function handle()
    calls = calls + 1
    if result == "throw" then error("failure") end
    if result == "nil" then return nil end
    return result
  end
  assert(not nav.consumePending(handle))
  assert(nav.peekPending().token == p.token and nav.peekPending().blocked)
  assert(not nav.consumePending(handle) and calls == 1, "failed navigation must not auto-replay")
  assert(not nav.consumePending(handle, nav.peekPending(), true) and calls == 2)
  assert(nav.consumePending(function() return true end, nav.peekPending(), true))
  assert(nav.peekPending() == nil)
end
nav.setPending("open_file", "/p/main.lua")
local p = nav.peekPending()
assert(nav.consumePending(function()
  nav.setPending("open_file", "/p/main.lua") -- identical replacement, different identity
  return true
end))
assert(nav.peekPending() and nav.peekPending().token ~= p.token)
assert(not nav.ackPending(p))
assert(not nav.consumePending(function() error("must not run") end, p))
p = nav.peekPending()
assert(not nav.consumePending(function() nav.setPending("open_file", "/p/new.lua"); return false end))
assert(not nav.peekPending().blocked and nav.peekPending().payload == "/p/new.lua")
assert(not nav.ackPending(p))
assert(nav.takePending().payload == "/p/new.lua" and not nav.peekPending())
data._nav_pending_v1 = "open_agent_conv\nlegacy\nbody"
p = assert(nav.peekPending())
assert(p.action == "open_agent_conv" and p.payload == "legacy\nbody")
assert(nav.consumePending(function() return true end) and nav.peekPending() == nil)
data._nav_pending_v1 = "\30nav2:old\n1\nopen_file\n/p/main.lua"
p = nav.peekPending()
assert(p.expired)
local called = false
local ok, reason = nav.consumePending(function() called = true; return true end)
assert(not ok and reason == "expired" and not called and nav.peekPending().blocked)
assert(nav.consumePending(function() called = true; return true end, nav.peekPending(), true) and called)
print("PASS actual ActivityUtil success-only ack, legacy compatibility, expiry, explicit retry and concurrent replacements")

-- Exercise MainActivity's actual callbacks, not a duplicate of the handler.
local back, dialogs, opened, currentFile, loadSucceeds, chatResult, switched
dialogs, opened, switched = {}, 0, 0
currentFile, loadSucceeds, chatResult = "/p/old.lua", false, false
MaterialAlertDialogBuilder = function()
  local d = {}
  for _, method in ipairs({ "setTitle", "setMessage", "setPositiveButton", "setNegativeButton", "setNeutralButton", "setOnCancelListener" }) do
    local name = method
    d[name] = function(value, callback) d[name .. "Value"] = value; d[name .. "Callback"] = callback; return d end
  end
  d.show = function() dialogs[#dialogs + 1] = d; return d end
  return d
end
package.loaded["com.google.android.material.dialog.MaterialAlertDialogBuilder"] = MaterialAlertDialogBuilder
android = { R = { string = { cancel = "cancel" } } }
GravityCompat = { START = 1 }
File = function(path)
  return { isFile = function() return path == "/p/main.lua" end,
    isDirectory = function() return path == "/p" or path == "/other" end }
end
package.loaded["java.io.File"] = File
package.loaded["androidx.core.view.GravityCompat"] = GravityCompat
package.loaded["androidx.appcompat.widget.PopupMenu"] = {}
local editor = { applyEditorPrefs = noop, currentFile = function() return currentFile end,
  save = function() return true end, load = function(path) if loadSucceeds then currentFile = path end end }
package.loaded["mods.utils.EditorUtil"] = editor
local init = { Actions = { snack = noop }, initBar = noop, initFunctionTab = noop, applyTabletMode = noop }
package.loaded.environment = true
package.loaded["activities.main.Init"] = init
package.loaded["mods.utils.AppInit"] = {}
package.loaded["mods.utils.RunKeyConfig"] = {}
package.loaded["mods.agent.ConversationStore"] = {
  invalidate = noop, get = function(id) if id == "exists" then return {} end end,
}
package.loaded["mods.agent.ChatUI"] = {
  openConversation = function() opened = opened + 1; if chatResult == "throw" then error("unavailable") end; return chatResult end,
  show = function() return chatResult end,
}
package.loaded["mods.utils.PathManager"] = { updateDir = function(path) Bean.Path.this_dir = path; switched = switched + 1 end }
_G["import"] = function(name)
  if name == "mods.utils.ActivityUtil" then ActivityUtil = nav end
  if name == "mods.utils.EditorUtil" then EditorUtil = editor end
end
this.themeUtil = {}
this.addOnBackPressedCallback = function(fn) back = fn end
activity.invalidateOptionsMenu = noop
Bean = { Path = { this_dir = "/p" } }
filetab = { setPath = noop }
MainActivity = { RecyclerView = { update = noop } }
assert(loadfile(assets .. "activities/main/MainActivity.lua"))()
nav.setPending("open_agent_conv", "gone")
onResume()
assert(nav.peekPending().blocked and opened == 1 and #dialogs == 1)
onResume()
assert(opened == 1 and #dialogs == 1)
assert(onResult("child", "open_agent_conv", "gone") == false and opened == 1)
chatResult = true
dialogs[1].setPositiveButtonCallback()
assert(opened == 2 and nav.peekPending() == nil)

nav.setPending("open_file", "/p/main.lua")
onResume()
assert(nav.peekPending() and currentFile == "/p/old.lua", "void load failure must not count as success")
loadSucceeds = true
dialogs[#dialogs].setPositiveButtonCallback()
assert(nav.peekPending() == nil and currentFile == "/p/main.lua")

for _, scenario in ipairs({
  { "open_file", "/missing.lua", "navigation_file_missing" },
  { "open_agent_conv_switch", "/missing\nexists", "navigation_project_missing" },
  { "open_agent_conv_switch", "/other\ngone", "navigation_conversation_missing" },
}) do
  nav.setPending(scenario[1], scenario[2]); onResume()
  local d = dialogs[#dialogs]
  assert(d.setMessageValue == scenario[3] and nav.peekPending().blocked)
  d.setNegativeButtonCallback()
  assert(nav.peekPending() == nil)
end
assert(switched == 0, "missing targets must not mutate project scope")
chatResult = "throw"
nav.setPending("open_agent_conv", "exists"); onResume()
assert(nav.peekPending().blocked)
dialogs[#dialogs].setNegativeButtonCallback()
nav.setPending("open_file", "/p/main.lua")
p = nav.peekPending()
chatResult = true
assert(onResult("legacy", "open_agent_conv", "exists"))
assert(nav.peekPending().token == p.token, "direct results must not clear unrelated pending")
nav.takePending()
local resultArgs
this.result = function(args) resultArgs = args end
nav.finishWith("open_agent_conv", "exists")
p = nav.peekPending()
assert(resultArgs[1] == p.action and resultArgs[2] == p.payload and resultArgs[3] == p.id)
onResume()
assert(nav.peekPending() == nil)
local before = opened
assert(onResult("child", resultArgs[1], resultArgs[2], resultArgs[3]))
assert(opened == before and nav.peekPending() == nil, "late onResult must not replay acknowledged navigation")
nav.setPending("open_file", "/p/main.lua")
p = nav.peekPending()
assert(not onResult("stale", "open_agent_conv", "exists", "old-id"))
assert(nav.peekPending().token == p.token and opened == before)
print("PASS actual MainActivity verifies destination, preserves failed requests, gives retry/dismiss feedback and validates scope")
nav.takePending()
local refreshCount, saves = 0, 0
MainActivity.RecyclerView.update = function() refreshCount = refreshCount + 1 end
editor.save = function() saves = saves + 1 return false end
nav.setPending("open_project", "/p")
onResume()
assert(nav.peekPending().blocked and switched == 0 and saves == 1,
  "creator open must save before changing project scope")
editor.save = function() saves = saves + 1 return true end
dialogs[#dialogs].setPositiveButtonCallback()
assert(not nav.peekPending() and switched == 1 and currentFile == "/p/main.lua")
local previousScope = Bean.Path.this_dir
local previousSaves, previousRefresh = saves, refreshCount
nav.setPending("project_created", "/other")
p = nav.peekPending()
onResume()
assert(not nav.peekPending() and Bean.Path.this_dir == previousScope and saves == previousSaves)
assert(refreshCount == previousRefresh + 1, "creation without opening only refreshes the file list")
assert(onResult("creator", "project_created", "/other", p.id))
assert(refreshCount == previousRefresh + 1, "late creator result is deduplicated")
nav.setPending("open_file", "/p/main.lua")
p = nav.peekPending()
assert(not onResult("creator", "open_project", "/p"))
assert(nav.peekPending().token == p.token and switched == 1)
print("PASS creator results preserve save guard, scope, pending ownership and deduplication")
print("ALL-PASS")
