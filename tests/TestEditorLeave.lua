local assets = ASSETS or "app/src/main/assets/"
package.path = assets .. "?.lua;" .. package.path
local LeaveGuard = require "mods.editor.LeaveGuard"

local function fixture(result)
  local f = { text = "unsaved", file = "/p/main.lua", saves = 0, finishes = 0, prompts = 0 }
  f.guard = LeaveGuard.new({
    currentFile = function() return f.file end,
    save = function()
      f.saves = f.saves + 1
      if result == "throw" then error("disk unavailable") end
      if result == "nil" then return nil end
      return result
    end,
    snapshot = function() return f.file .. ":" .. f.text end,
    closeTransient = function()
      if f.transient then f.transient = false; return true end
      return false
    end,
    finish = function() f.finishes = f.finishes + 1 end,
    onFailure = function(choice) f.choice = choice; f.prompts = f.prompts + 1 end,
    confirmDiscard = function(confirm) f.confirm = confirm end,
  })
  return f
end

for _, result in ipairs({ true, "same" }) do
  local f = fixture(result)
  assert(f.guard.request() and f.finishes == 1 and f.prompts == 0)
  assert(not f.guard.request() and f.finishes == 1)
end
for _, result in ipairs({ false, "nil", "throw" }) do
  local f = fixture(result)
  assert(not f.guard.request() and f.finishes == 0 and f.text == "unsaved")
  assert(not f.guard.request() and f.saves == 1, "repeat Back must not bypass a failed save")
  local old = f.choice
  assert(not old.retry() and f.saves == 2 and f.finishes == 0)
  old.discard()
  assert(f.confirm == nil, "callbacks from an obsolete prompt must be inert")
  f.choice.discard()
  assert(f.finishes == 0, "discard selection is not confirmation")
  f.confirm(false)
  assert(f.finishes == 0 and not f.guard.isLeaving())
  f.guard.request()
  f.choice.cancel()
  assert(f.finishes == 0)
  f.guard.request()
  f.choice.discard()
  f.confirm(true)
  assert(f.finishes == 1 and f.guard.isLeaving())
end
local f = fixture(false)
f.guard.request(); f.choice.discard(); f.text = "newer buffer"; f.confirm(true)
assert(f.finishes == 0 and f.prompts == 2, "stale confirmation cannot discard newer edits")
f = fixture(true)
f.transient = true
assert(not f.guard.request() and f.saves == 0 and f.finishes == 0)
assert(f.guard.request())
f = fixture("throw"); f.file = ""
assert(f.guard.request() and f.saves == 0)
print("PASS actual LeaveGuard success, failure, cancel, stale callbacks and explicit discard")

-- MainActivity integration: real menu/Back/lifecycle wiring, Android boundary doubles.
local noop = function() end
-- MCP lifecycle is a separate native boundary from the leave/save guard.
package.loaded["mods.mcp.EditorBridge"] = { register = noop, unregister = noop, dispatch = noop }
res = { string = setmetatable({}, { __index = function(_, k) return k end }), drawable = function() end }
android = { R = { string = { cancel = "cancel" }, id = { home = 1 } } }
GravityCompat = { START = 1 }
local dialogs, back, finished, saves, saveResult, buffer, drawerOpen, searchVisible
local function dialogBuilder()
  local d = {}
  for _, name in ipairs({ "setTitle", "setMessage", "setPositiveButton", "setNegativeButton", "setNeutralButton", "setOnCancelListener" }) do
    local method = name
    d[method] = function(value, callback) d[method .. "Value"] = value; d[method .. "Callback"] = callback; return d end
  end
  d.show = function() dialogs[#dialogs + 1] = d; return d end
  return d
end
MaterialAlertDialogBuilder = dialogBuilder
package.loaded["com.google.android.material.dialog.MaterialAlertDialogBuilder"] = dialogBuilder
package.loaded["androidx.core.view.GravityCompat"] = GravityCompat
package.loaded["androidx.appcompat.widget.PopupMenu"] = {}
local editor = {
  currentFile = function() return "/p/main.lua" end,
  save = function()
    saves = saves + 1
    if saveResult == "throw" then error("disk") end
    if saveResult == "nil" then return nil end
    return saveResult
  end,
}
local actions = { hideSearchBar = function() searchVisible = false end }
local init = { Actions = actions, VISIBLE = 0, isTabletMode = function() return false end }
package.loaded.environment = true
package.loaded["activities.main.Init"] = init
package.loaded["mods.utils.AppInit"] = {}
package.loaded["mods.utils.RunKeyConfig"] = {}
package.loaded["activities.main.Workspace"] = { saveFor = noop }
package.loaded["mods.agent.ChatUI"] = { saveCurrentConversation = noop }
local nav = { peekPending = function() end }
package.loaded["mods.utils.ActivityUtil"] = nav
package.loaded["mods.utils.EditorUtil"] = editor
_G["import"] = function(name)
  if name == "mods.utils.EditorUtil" then EditorUtil = editor end
  if name == "mods.utils.ActivityUtil" then ActivityUtil = nav end
end
local function start(result)
  dialogs, finished, saves, saveResult = {}, 0, 0, result
  buffer, drawerOpen, searchVisible = "unsaved buffer", false, false
  this = { themeUtil = { getColorOnBackground = function() return 0 end },
    addOnBackPressedCallback = function(fn) back = fn end }
  activity = { finish = function(...) assert(select("#", ...) == 0); finished = finished + 1 end }
  mLuaEditor = { getText = function() return { toString = function() return buffer end } end }
  drawer = { isDrawerOpen = function() return drawerOpen end, closeDrawer = function() drawerOpen = false end }
  mSearch = { getVisibility = function() return searchVisible and 0 or 8 end }
  Bean = { Path = { this_dir = "/p" } }
  assert(loadfile(assets .. "activities/main/MainActivity.lua"))()
end
start(true)
drawerOpen = true; searchVisible = true
back(); assert(not drawerOpen and saves == 0)
back(); assert(not searchVisible and saves == 0)
back(); assert(finished == 1 and saves == 1 and #dialogs == 0)
for _, result in ipairs({ false, "throw", "nil" }) do
  start(result)
  back(); back()
  assert(finished == 0 and saves == 1 and #dialogs == 1 and buffer == "unsaved buffer")
  dialogs[1].setNeutralButtonCallback()
  assert(finished == 0 and #dialogs == 2)
  dialogs[2].setPositiveButtonCallback()
  assert(finished == 1)
  onPause()
  assert(saves == 1, "explicit discard must not trigger another lifecycle save")
end
start(false)
onPause()
assert(#dialogs == 0 and saves == 1 and finished == 0, "onPause must never show a modal")
start(false)
local menuActions = {}
local function menu()
  return { addSubMenu = menu, add = function(title)
    local item = { setIcon = noop, setShowAsAction = noop }
    menuActions[title] = item
    return item
  end }
end
assert(onCreateOptionsMenu(menu()))
menuActions.exit.onMenuItemClick()
assert(finished == 0 and saves == 1 and #dialogs == 1, "menu exit must use the same guard")
saveResult = "same"
dialogs[1].setPositiveButtonCallback()
assert(finished == 1 and saves == 2)
print("PASS actual MainActivity menu/Back share guard; saved Back returns once; onPause is non-modal")
print("ALL-PASS")
