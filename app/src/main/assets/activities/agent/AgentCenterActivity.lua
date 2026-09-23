--- AI 会话中心：跨工程聚合浏览全部会话，点击回传主界面打开（必要时自动切换工程）。
--- 注意：本页运行在独立 activity 环境，Bean.Path.this_dir 是默认值，
--- 当前工程必须由启动参数传入；本页对会话数据只读，选中/切换/新建一律回传主界面执行。
require "mods.bootstrap"
local ActivityUtil = require "mods.utils.ActivityUtil"
local AgentChat = require("mods.agent.AgentChat")
local ConversationStore = require("mods.agent.ConversationStore")

local MaterialTextView = bindClass "com.google.android.material.textview.MaterialTextView"
local MaterialAlertDialogBuilder = bindClass "com.google.android.material.dialog.MaterialAlertDialogBuilder"
local MaterialCardView = bindClass "com.google.android.material.card.MaterialCardView"
local GradientDrawable = bindClass "android.graphics.drawable.GradientDrawable"
local LinearLayout = bindClass "android.widget.LinearLayout"
local View = bindClass "android.view.View"
local WindowManager = bindClass "android.view.WindowManager"
local ColorDrawable = bindClass "android.graphics.drawable.ColorDrawable"
local Typeface = bindClass "android.graphics.Typeface"
local TextUtils = bindClass "android.text.TextUtils"
local TruncateAt = TextUtils and TextUtils.TruncateAt or nil

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
local ColorText = ColorUtil.surface.onVariant
local ColorOutline = ColorUtil.outline.variant
local ColorErrorContainer = ColorUtil.error.container
local ColorOnErrorContainer = ColorUtil.error.onContainer
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

local function dp(n) return this.dpToPx(n) end

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

local function buildRow(conv, projectName)
  local name = tostring(conv.name or "")
  if name == "" then name = S.ai_unnamed_conv end
  local firstChar = name:match("[\0-\127\192-\255][\128-\191]*") or "?"

  local n = type(conv.messages) == "table" and #conv.messages or 0
  local metaParts = { S.ai_center_msg_count:format(n) }
  if tostring(conv.updatedAt or "") ~= "" then
    metaParts[#metaParts + 1] = tostring(conv.updatedAt)
  end
  if projectName then
    metaParts[#metaParts + 1] = shortProject(projectName)
  end

  local rowViews = {}
  local card = loadlayout({
    MaterialCardView,
    radius = "16dp",
    cardElevation = 0,
    strokeWidth = "0dp",
    CardBackgroundColor = ColorSurfaceContainerLow,
    clickable = true,
    focusable = true,
    layout_width = "match",
    layout_height = "wrap",
    {
      LinearLayout,
      orientation = "horizontal",
      gravity = "center_vertical",
      layout_width = "match",
      layout_height = "wrap",
      padding = "14dp",
      paddingTop = "12dp",
      paddingBottom = "12dp",
      {
        MaterialTextView,
        id = "avatar",
        text = firstChar:upper(),
        textSize = "13sp",
        textStyle = "bold",
        textColor = ColorOnPrimaryContainer,
        gravity = "center",
        layout_width = "38dp",
        layout_height = "38dp",
      },
      {
        LinearLayout,
        orientation = "vertical",
        layout_width = "0dp",
        layout_weight = 1,
        layout_height = "wrap",
        layout_marginLeft = "12dp",
        layout_marginRight = "6dp",
        {
          MaterialTextView,
          text = name,
          textSize = "15sp",
          textStyle = "bold",
          textColor = ColorOnSurface,
          singleLine = true,
          ellipsize = "end",
        },
        {
          MaterialTextView,
          text = table.concat(metaParts, " · "),
          textSize = "12sp",
          textColor = ColorText,
          singleLine = true,
          ellipsize = "end",
          layout_marginTop = "2dp",
        },
      },
      {
        MaterialTextView,
        id = "badge",
        text = S.ai_conv_running,
        textSize = "11sp",
        textColor = ColorOnErrorContainer,
        gravity = "center",
        visibility = conv.running and 0 or 8,
        paddingLeft = "8dp",
        paddingRight = "8dp",
        layout_width = "wrap",
        layout_height = "24dp",
      },
    },
  }, rowViews)

  local ag = GradientDrawable()
  ag.setShape(GradientDrawable.OVAL)
  ag.setColor(ColorPrimaryContainer)
  rowViews.avatar.setBackground(ag)

  if conv.running then
    local rbg = GradientDrawable()
    rbg.setCornerRadius(dp(8))
    rbg.setColor(ColorErrorContainer)
    rowViews.badge.setBackground(rbg)
  end

  card.setOnClickListener(function()
    if projectName then
      -- 跨工程：确认后回传主界面切换工程并打开
      MaterialAlertDialogBuilder(activity)
        .setTitle(S.ai_center_title)
        .setMessage(S.ai_center_switch_hint:format(shortProject(projectName)))
        .setPositiveButton(S.ai_ok, function()
          ActivityUtil.finishWith("open_agent_conv_switch", projectName .. "\n" .. conv.id)
        end)
        .setNegativeButton(S.ai_cancel, nil)
        .show()
    else
      ActivityUtil.finishWith("open_agent_conv", conv.id)
    end
  end)

  local cardLp = LinearLayout.LayoutParams(-1, -2)
  cardLp.bottomMargin = dp(8)
  card.setLayoutParams(cardLp)
  return card
end

local function refresh()
  ui.centerList.removeAllViews()
  local all = ConversationStore.load()
  local rows = {}
  for _, record in ipairs(all) do
    local same = normPath(record.projectPath) == currentProject
    if scope == "all" or same then
      rows[#rows + 1] = { conv = record, same = same }
    end
  end
  table.sort(rows, function(a, b)
    return tostring(a.conv.updatedAt or "") > tostring(b.conv.updatedAt or "")
  end)

  if #rows == 0 then
    local empty = MaterialTextView(activity)
    empty.setText(S.ai_center_empty)
    empty.setTextSize(13)
    empty.setTextColor(ColorText)
    empty.setGravity(17)
    empty.setPadding(0, dp(48), 0, dp(48))
    ui.centerList.addView(empty)
    return
  end

  for _, item in ipairs(rows) do
    ui.centerList.addView(buildRow(item.conv, item.same and nil or item.conv.projectPath))
  end
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
