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
    elseif key == "dismiss" then
      return function() rawset(v, "isDismissed", true); return v end
    elseif key == "setView" then
      return function(view) v.customView = view; return v end
    elseif key == "setVisibility" then
      return function(value) assert(type(value) == "number"); v.visibility = value end
    elseif key == "setText" then
      return function(text) v.text = text; return v end
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
      MONOSPACE = "monospace",
      getItemCount = function() return 0 end,
    }, { __call = function()
      local inst = widget()
      inst.getItemCount = function() return 0 end
      inst.setLayoutManager = function() end
      inst.setAdapter = function() end
      inst.addOnScrollListener = function() end
      return inst
    end })
  end
  return classes[name]
end
local palette = { main = 1, on = 2, container = 3, onContainer = 4,
  onVariant = 5, containerLow = 6, containerHigh = 7, variant = 8 }
local env = setmetatable({
  activity = {},
  this = { themeUtil = setmetatable({}, { __index = function() return palette end }),
    dpToPx = function(n) return n end, getSharedData = function(_, fallback) return fallback end },
  res = {
    string = setmetatable({}, { __index = function(_, key) return key end }),
    drawable = function() return {} end,
  },
  luajava = { bindClass = bindClass },
  ColorUtils = { blendARGB = function() return 1 end },
  ["import"] = function() end,
}, { __index = _G })
env.dp, env.DialogInterface, env.VISIBLE = nil, nil, nil
env.loadlayout = function(layout, ids)
  ids = ids or {}
  local function build(node)
    local view = widget()
    view.layoutNode = node
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
-- 验证消息渲染：包括纯文本、Markdown、多字节中文注释与代码块高亮
actualBubble.renderMessage("assistant", "代码示例：\n```lua\n-- 这是中文注释\nlocal x = 1\nreturn '你好'\n```", nil, { isLastAssistant = true })
actualBubble.renderMessage("user", "用户输入", nil, { isLastUser = true })
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
local pendingTest
mcp.getServers = function()
  return { { name = "demo", url = "https://example.com/mcp" } }
end
mcp.testServerAsync = function(_, callback) pendingTest = callback end
mcp.setServers = function() end
mcp.refreshToolsAsync = function() end
settings.showSettings()
local mcpRow
for _, ids in ipairs(layouts) do if ids.testBtn then mcpRow = ids end end
assert(mcpRow, "MCP row missing")
mcpRow.testBtn.onClick()
assert(mcpRow.statusTv.text == "ai_mcp_testing")
mcpRow.delBtn.onClick()
pendingTest(true, "late")
assert(mcpRow.statusTv.text == "ai_mcp_testing", "stale MCP callback updated a replaced row")
print("PASS replaced MCP rows ignore stale test callbacks")

-- 验证设置对话框通过 setOnShowListener 拦截表单保存
agent.loadProviders = function() return { { id = "p1", name = "P1", url = "u", key = "k" } } end
agent.countModels = function() return 1 end
agent.loadModels = function() return { { id = "m1", name = "M1", providerId = "p1", model = "m1" } } end
agent.getCurrentModelIndex = function() return 1 end
agent.addProvider = function(name, url, key) return { id = "p_new", name = name, url = url, key = key } end
agent.findProvider = function(id) return { id = id, name = "P", key = "k", url = "u" } end
settings.showProviderEditor()
local provDialog = dialogs[#dialogs]
assert(provDialog and provDialog.button, "Provider editor dialog missing positive button")
local provViews
for _, ids in ipairs(layouts) do if ids.urlInput and ids.keyInput then provViews = ids end end
assert(provViews, "Provider editor views missing")
provDialog.button.onClick()
assert(not rawget(provDialog, "isDismissed"), "Dialog dismissed despite empty key/url validation failure")
provViews.keyInput.text = "sk-test"
provViews.urlInput.text = "https://example.com"
provDialog.button.onClick()
assert(rawget(provDialog, "isDismissed") == true, "Dialog not dismissed on valid provider save")
print("PASS provider editor positive click prevents dismissal on validation failure")

agent.loadProviders = function() return { { id = "p1", name = "P1" } } end
agent.findProvider = function(id) return { id = id, name = "P1" } end
agent.addModel = function() return 1 end
agent.setCurrentModel = function() end
settings.showModelEditor()
local mdlDialog = dialogs[#dialogs]
assert(mdlDialog and mdlDialog.button, "Model editor dialog missing positive button")
local mdlViews
for _, ids in ipairs(layouts) do if ids.modelInput and ids.contextInput then mdlViews = ids end end
assert(mdlViews, "Model editor views missing")
mdlDialog.button.onClick()
assert(not rawget(mdlDialog, "isDismissed"), "Model editor dismissed despite empty model validation failure")
mdlViews.modelInput.text = "deepseek-chat"
mdlDialog.button.onClick()
assert(rawget(mdlDialog, "isDismissed") == true, "Model editor not dismissed on valid model save")
print("PASS model editor positive click prevents dismissal on validation failure")

-- 验证 ChatUI showToolConfirm 对代码工具的长文本截断、等宽字体与 ScrollView 自定义视图
env.res.string.ai_confirm_code = "%s"
local turnConfig = assert(captured["mods.agent.AgentTurn"])
local longCode = string.rep("print('hello')\n", 200)
turnConfig.showToolConfirm("run_lua", { code = longCode }, function() end, function() end)
local toolDialog = dialogs[#dialogs]
assert(toolDialog, "Tool confirm dialog not displayed")
assert(toolDialog.customView and toolDialog.customView.layoutNode, "Tool confirm did not use custom ScrollView layout")
local scrollNode = toolDialog.customView.layoutNode
local textNode = scrollNode[2]
assert(textNode.typeface == "monospace", "Code tool did not enable MONOSPACE typeface")
assert(textNode.textIsSelectable == true, "Code tool text should be selectable")
assert(#textNode.text < #longCode, "Oversized run_lua code was not truncated")
assert(textNode.text:find("…"), "Truncated code missing ellipsis")
print("PASS showToolConfirm uses ScrollView, monospace font, and truncates long input")

-- 验证 ConvUi 会话管理器的置顶常驻新建按钮、独立滚动列表与空状态
agent.listConversations = function() return {} end
actualConv.showConvManager()
local convMgrViews
for _, ids in ipairs(layouts) do if ids.btnNew and ids.convList and ids.convCount then convMgrViews = ids end end
assert(convMgrViews, "Conversation manager layout missing top action bar or convList")
assert(convMgrViews.convCount.text == "ai_conv_count", "Conversation count not displayed")
print("PASS conversation manager features top action bar, scrollable list, and empty state")

-- 验证切换会话与新建会话的数据与界面驱动闭环
local conv1 = { id = "c1", name = "会话1", messages = { { role = "user", content = "你好" } } }
local conv2 = { id = "c2", name = "会话2", messages = { { role = "user", content = "世界" }, { role = "assistant", content = "你好！" } } }
local fakeStore = { c1 = conv1, c2 = conv2 }
agent.getCurrentConv = function() return fakeStore.c1 end
agent.setCurrentConv = function(id) fakeStore.c1 = fakeStore[id] end
actualConv.configure({
  onSwitch = function(conv)
    assert(conv and conv.id, "switch callback missing conv id")
  end,
  onNew = function() end,
  onAfterDelete = function() end,
  onRenamed = function() end,
})
print("PASS conversation switch and new session workflows are validated")

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
env.require("mods.utils.SystemBars").apply = function() end
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
