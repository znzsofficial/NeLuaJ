--- AI 会话中心：跨工程聚合浏览全部会话，点击回传主界面打开（必要时自动切换工程）。
--- 注意：本页运行在独立 activity 环境，Bean.Path.this_dir 是默认值，
--- 当前工程必须由启动参数传入；本页对会话数据只读，选中/切换/新建一律回传主界面执行。
require "mods.bootstrap"
local ActivityUtil = require "mods.utils.ActivityUtil"
local AgentChat = require("mods.agent.AgentChat")
local ConversationStore = require("mods.agent.ConversationStore")
local ConvList = require("mods.agent.ConvList")

local MaterialAlertDialogBuilder = bindClass "com.google.android.material.dialog.MaterialAlertDialogBuilder"
local View = bindClass "android.view.View"
local WindowManager = bindClass "android.view.WindowManager"
local ColorDrawable = bindClass "android.graphics.drawable.ColorDrawable"

this.dynamicColor()
local res = res
local S = res.string

-- 当前工程由启动参数传入（独立环境里 Bean.Path.this_dir 不可信）
local currentProject = ...
if type(currentProject) ~= "string" then currentProject = "" end
local function normPath(p)
  p = tostring(p or ""):gsub("/+$", "")
  return p
end
currentProject = normPath(currentProject)

local ui = {}
local content = loadlayout(res.layout.agent_center, ui)

-- 布局表的 local 色值不会泄漏到本环境，这里独立取色
local ColorUtil = this.themeUtil
local ColorPrimaryContainer = ColorUtil.primary.container
local ColorOnPrimaryContainer = ColorUtil.primary.onContainer
local ColorSurfaceContainerLow = ColorUtil.surface.containerLow
local ColorOnSurface = ColorUtil.surface.on
local ColorStateList = bindClass "android.content.res.ColorStateList"

local barColor = ColorUtil.surface.main
activity.setTitle(S.ai_center_title)
  .setContentView(content)
  .getSupportActionBar() {
    Elevation = 0,
    BackgroundDrawable = ColorDrawable(barColor),
    DisplayHomeAsUpEnabled = true
  }

local window = activity.getWindow()
  .setNavigationBarColor(barColor)
  .setStatusBarColor(barColor)
  .addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
  .clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
if this.isNightMode() then
  window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_VISIBLE)
else
  window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR)
end

function onOptionsItemSelected(item)
  if item.getItemId() == android.R.id.home then
    activity.finish()
    return true
  end
end

local scope = "all" -- all | current

local function styleChip(btn, selected)
  btn.setAllCaps(false)
  if selected then
    btn.setBackgroundTintList(ColorStateList.valueOf(ColorPrimaryContainer))
    btn.setTextColor(ColorOnPrimaryContainer)
  else
    btn.setBackgroundTintList(ColorStateList.valueOf(ColorSurfaceContainerLow))
    btn.setTextColor(ColorOnSurface)
  end
end

local function shortProject(p)
  return tostring(p or ""):gsub("/+$", ""):gsub("^.*/", "")
end

--- 行为回调：跨工程确认后回传；同工程直接回传（打开动作一律在主界面环境执行）
local function onOpen(conv, projectName)
  if projectName then
    MaterialAlertDialogBuilder(activity)
      .setTitle(S.ai_center_title)
      .setMessage(S.ai_center_switch_hint:format(ConvList.shortProject(projectName)))
      .setPositiveButton(S.ai_ok, function()
        ActivityUtil.finishWith("open_agent_conv_switch", projectName .. "\n" .. conv.id)
      end)
      .setNegativeButton(S.ai_cancel, nil)
      .show()
  else
    ActivityUtil.finishWith("open_agent_conv", conv.id)
  end
end

local function refresh()
  local all = ConversationStore.load()
  local rows = {}
  for _, record in ipairs(all) do
    local same = normPath(record.projectPath) == currentProject
    if scope == "all" or same then
      rows[#rows + 1] = { conv = record, projectName = same and nil or record.projectPath }
    end
  end
  ConvList.renderList(ui.centerList, rows, onOpen)
end

local function bindScopeChips()
  styleChip(ui.chipAll, scope == "all")
  styleChip(ui.chipCurrent, scope == "current")
  ui.chipAll.setText(S.ai_center_all)
  ui.chipCurrent.setText(S.ai_center_current)
end

ui.chipAll.onClick = function()
  if scope == "all" then return end
  scope = "all"
  bindScopeChips()
  refresh()
end
ui.chipCurrent.onClick = function()
  if scope == "current" then return end
  scope = "current"
  bindScopeChips()
  refresh()
end
ui.btnNewConv.onClick = function()
  -- 新建对话在主界面环境执行（保证选中态/工程归属正确）
  ActivityUtil.finishWith("open_agent_new", currentProject)
end

bindScopeChips()
refresh()
