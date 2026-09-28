-- Execute the real UI modules with a small host double, not an Android renderer.
local assets = ASSETS or "app/src/main/assets/"
local captured, modules, layouts, dialogs = {}, {}, {}, {}
local activeChecks = 0
local function widget()
  local v = {}
  return setmetatable(v, { __call = function() return v end, __index = function(_, key)
    if key == "getButton" then
      return function(which) assert(which == -1); v.button = widget(); return v.button end
    elseif key == "setOnShowListener" then
      return function(fn) v.onShow = fn; return v end
    elseif key == "show" then
      return function() dialogs[#dialogs + 1] = v; if v.onShow then v.onShow() end; return v end
    elseif key == "setVisibility" then
      return function(value) assert(type(value) == "number"); v.visibility = value end
    end
    return function() return v end
  end })
end
local classes = {}
local function bindClass(name)
  if not classes[name] then
    classes[name] = setmetatable({
      BUTTON_POSITIVE = -1, valueOf = function(x) return x end,
      LayoutParams = function() return {} end,
    }, { __call = function() return widget() end })
  end
  return classes[name]
end
local palette = { main = 1, on = 2, container = 3, onContainer = 4,
  onVariant = 5, containerLow = 6, containerHigh = 7, variant = 8 }
local env = setmetatable({
  activity = {},
  this = { themeUtil = setmetatable({}, { __index = function() return palette end }),
    dpToPx = function(n) return n end, getSharedData = function(_, fallback) return fallback end },
  res = { string = setmetatable({}, { __index = function(_, key) return key end }) },
  luajava = { bindClass = bindClass },
  ColorUtils = { blendARGB = function() return 1 end },
  ["import"] = function() end,
}, { __index = _G })
env.dp, env.DialogInterface, env.VISIBLE = nil, nil, nil
env.loadlayout = function(layout, ids)
  ids = ids or {}
  local function build(node)
    local view = widget()
    if node.id then ids[node.id] = view end
    for i = 2, #node do build(node[i]) end
    return view
  end
  local view = build(layout)
  layouts[#layouts + 1] = ids
  return view
end
env.require = function(name)
  if not modules[name] then
    modules[name] = { configure = function(options) captured[name] = options end }
  end
  return modules[name]
end
local turn = env.require("mods.agent.AgentTurn")
turn.isActive = function() activeChecks = activeChecks + 1; return true end
local agent = env.require("mods.agent.AgentChat")
agent.loadModels = function() return {} end
agent.getAuxModelIndex = function() return 0 end
local mcp = env.require("mods.agent.MCPClient")
mcp.getServers = function() return {} end
local function loadModule(file)
  -- Each suite runs in its own JVM; install only the explicit host doubles.
  for key, value in pairs(env) do _G[key] = value end
  package.loaded["androidx.core.graphics.ColorUtils"] = env.ColorUtils
  package.loaded["mods.utils.EditorUtil"] = {}
  local chunk = assert(loadfile(assets .. "mods/agent/" .. file .. ".lua"))
  return chunk()
end

-- The real module must inject callbacks that reach its later local functions.
modules["mods.agent.Contracts"] = loadModule("Contracts")
modules["mods.agent.SessionState"] = loadModule("SessionState")
loadModule("ChatUI")
local bubble = assert(captured["mods.agent.BubbleRenderer"])
assert(type(bubble.onRegenerate) == "function", "missing regenerate hook")
assert(type(bubble.onEditRequest) == "function", "missing edit hook")
assert(bubble.onRegenerate() == false)
bubble.onEditRequest({ role = "user", content = "test" })
assert(activeChecks == 2, "hooks did not reach the real handlers")
print("PASS late-defined chat actions are connected")
local actualBubble = loadModule("BubbleRenderer")
actualBubble.configure(bubble)
assert(not pcall(actualBubble.configure, {}))
local actualConv = loadModule("ConvUi")
actualConv.configure(assert(captured["mods.agent.ConvUi"]))
assert(not pcall(actualConv.configure, {}))
print("PASS renderer and conversation UI validate their actual callback contracts")

-- Opening Add MCP must not depend on a global DialogInterface binding.
local settings = loadModule("SettingsUi")
settings.configure(assert(captured["mods.agent.SettingsUi"]))
assert(not pcall(settings.configure, {}))
settings.showSettings()
local settingsViews
for _, ids in ipairs(layouts) do if ids.btnAddMcp then settingsViews = ids end end
assert(settingsViews, "settings layout missing")
settingsViews.btnAddMcp.onClick()
assert(dialogs[#dialogs].button, "Add MCP did not bind the positive button")
assert(type(dialogs[#dialogs].button.onClick) == "function")
print("PASS Add MCP opens without a global DialogInterface")

-- Execute the real standalone activity with two projects and click both rows.
local centerRows, openCenterRow, finished
env.require("mods.agent.ConversationStore").load = function()
  return {
    { id = "current", projectPath = "/projects/current/" },
    { id = "other", projectPath = "/projects/other" },
  }
end
local convList = env.require("mods.agent.ConvList")
convList.renderList = function(_, rows, onOpen) centerRows, openCenterRow = rows, onOpen end
convList.shortProject = function(path) return path end
env.require("mods.utils.ActivityUtil").finishWith = function(action, value)
  finished = { action, value }
end
package.loaded["mods.bootstrap"] = true
env.this.dynamicColor = function() end
env.this.isNightMode = function() return true end
env.activity = widget()
env.bindClass = bindClass
bindClass("android.view.WindowManager").LayoutParams = {
  FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS = 1, FLAG_TRANSLUCENT_STATUS = 2,
}
bindClass("android.view.View").SYSTEM_UI_FLAG_VISIBLE = 0
env.res.layout = { agent_center = { {},
  { {}, id = "centerList" }, { {}, id = "chipAll" },
  { {}, id = "chipCurrent" }, { {}, id = "btnNewConv" },
} }
for key, value in pairs(env) do _G[key] = value end
assert(loadfile(assets .. "activities/agent/AgentCenterActivity.lua"))("/projects/current")
assert(#centerRows == 2)
assert(centerRows[1].projectName == nil, "same project must not request a switch")
assert(centerRows[2].projectName == "/projects/other")
local dialogCount = #dialogs
openCenterRow(centerRows[1].conv, centerRows[1].projectName)
assert(#dialogs == dialogCount, "same project must open without confirmation")
assert(finished[1] == "open_agent_conv" and finished[2] == "current")
openCenterRow(centerRows[2].conv, centerRows[2].projectName)
assert(#dialogs == dialogCount + 1, "other project still needs switch confirmation")
print("PASS conversation center distinguishes current and other projects")
print("ALL-PASS")
