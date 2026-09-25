--- 会话列表 / 管理器对话框：从 ChatUI 抽出的纯 UI 部分。
--- 状态操作（切换、新建、删除后的重载、重命名后的标题刷新）经 configure 注入：
---   onSwitch(conv) / onNew() / onAfterDelete(convId) / onRenamed(convId)
--- 本模块只 require AgentChat / AgentTurn，不引用 ChatUI。
local _M = {}

local AgentChat = require("mods.agent.AgentChat")
local AgentTurn = require("mods.agent.AgentTurn")

local ColorStateList = luajava.bindClass("android.content.res.ColorStateList")
local MaterialAlertDialogBuilder = luajava.bindClass("com.google.android.material.dialog.MaterialAlertDialogBuilder")
local MaterialButton = luajava.bindClass("com.google.android.material.button.MaterialButton")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local ScrollView = luajava.bindClass("android.widget.ScrollView")
local EditText = luajava.bindClass("android.widget.EditText")
local GradientDrawable = luajava.bindClass("android.graphics.drawable.GradientDrawable")
local Typeface = luajava.bindClass("android.graphics.Typeface")

local ColorUtil = this.themeUtil
local ColorPrimary = ColorUtil.primary.main
local ColorOnPrimary = ColorUtil.primary.on
local ColorPrimaryContainer = ColorUtil.primary.container
local ColorOnPrimaryContainer = ColorUtil.primary.onContainer
local ColorSecondaryContainer = ColorUtil.secondary.container
local ColorOnSecondaryContainer = ColorUtil.secondary.onContainer
local ColorOnSurface = ColorUtil.surface.on
local ColorText = ColorUtil.surface.onVariant
local ColorSurfaceContainerLow = ColorUtil.surface.containerLow
local ColorErrorContainer = ColorUtil.error.container
local ColorOnErrorContainer = ColorUtil.error.onContainer

local res = res
local S = res.string
local dp = function(n) return this.dpToPx(n) end

local VISIBLE = 0
local GONE = 8

local hooks = {}

function _M.configure(options)
  hooks = options or {}
end

local function onSwitch(conv) return hooks.onSwitch and hooks.onSwitch(conv) end
local function onNew() return hooks.onNew and hooks.onNew() end
local function onAfterDelete(convId) return hooks.onAfterDelete and hooks.onAfterDelete(convId) end
local function onRenamed(convId) return hooks.onRenamed and hooks.onRenamed(convId) end

local function convName(conv)
  local n = conv and conv.name or ""
  if n == "" then return S.ai_unnamed_conv end
  return n
end

local CONV_COLORS = {
  0xFF7C4DFF, 0xFF536DFE, 0xFF448AFF, 0xFF00BFA5,
  0xFF00C853, 0xFFFFB300, 0xFFFF6E40, 0xFFE040FB,
  0xFFF50057, 0xFF26A69A,
}

local function convColor(name)
  local s = tostring(name or "")
  local h = 0
  for i = 1, #s do h = (h * 31 + s:byte(i)) % 65536 end
  return CONV_COLORS[(h % #CONV_COLORS) + 1]
end

local function makeAvatar(name, sizeDp)
  local size = dp(sizeDp)
  local tv = MaterialTextView(activity)
  local s = tostring(name or "?")
  local ok, first = pcall(function() return utf8.sub(s, 1, 1) end)
  if not ok or first == nil or first == "" then
    first = s:sub(1, 1) or "?"
  end
  tv.setText(first)
  tv.setTextSize(16)
  tv.setTextColor(0xffffffff)
  tv.setGravity(17)
  tv.setTypeface(Typeface.DEFAULT, 1)
  local gd = GradientDrawable()
  gd.setShape(GradientDrawable.OVAL)
  gd.setColor(convColor(name))
  tv.setBackground(gd)
  tv.setLayoutParams(LinearLayout.LayoutParams(size, size))
  return tv
end

local function convMetaText(conv)
  local project = tostring(conv.projectPath or ""):match("([^/]+)$") or S.ai_project_unknown
  return S.ai_conv_meta:format(tostring(conv.createdAt or ""), #(conv.messages or {})) .. "  ·  " .. project
end

local function showRenameDialog(convId, oldName)
  local dlgViews = {}
  local inputLayout = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    padding = "16dp",
    {
      EditText,
      id = "nameInput",
      layout_width = "match", layout_height = "wrap", minHeight = "48dp",
      textSize = "14sp", singleLine = true,
      text = oldName,
    },
  }
  local content = loadlayout(inputLayout, dlgViews)

  MaterialAlertDialogBuilder(activity)
    .setTitle(S.ai_rename)
    .setView(content)
    .setPositiveButton(S.ai_ok, function()
      local name = tostring(dlgViews.nameInput.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
      if name ~= "" and convId then
        AgentChat.renameConversation(convId, name)
        onRenamed(convId)
      end
    end)
    .setNegativeButton(S.ai_cancel, nil)
    .show()
end

local function buildConvRow(conv, isCurrent, onClick)
  local name = convName(conv)
  local rowViews = {}
  local row = loadlayout({
    LinearLayout,
    layout_width = "match",
    layout_height = "wrap",
    orientation = "horizontal",
    gravity = "center_vertical",
    clickable = true,
    focusable = true,
    layout_marginBottom = "8dp",
    paddingLeft = "14dp",
    paddingRight = "14dp",
    paddingTop = "10dp",
    paddingBottom = "10dp",
    {
      LinearLayout,
      id = "avatarSlot",
      layout_width = "wrap",
      layout_height = "wrap",
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
        textColor = isCurrent and ColorOnPrimaryContainer or ColorOnSurface,
        singleLine = true,
        ellipsize = "end",
      },
      {
        MaterialTextView,
        text = convMetaText(conv),
        textSize = "12sp",
        textColor = isCurrent and ColorOnPrimaryContainer or ColorText,
        singleLine = true,
        ellipsize = "end",
        layout_marginTop = "2dp",
      },
    },
    {
      MaterialTextView,
      id = "badge",
      textSize = "11sp",
      gravity = "center",
      singleLine = true,
      visibility = (isCurrent or conv.running) and VISIBLE or GONE,
      layout_width = "wrap",
      layout_height = "24dp",
    },
  }, rowViews)

  local bg = GradientDrawable()
  bg.setCornerRadius(dp(16))
  bg.setColor(isCurrent and ColorPrimaryContainer or ColorSurfaceContainerLow)
  row.setBackground(bg)

  rowViews.avatarSlot.addView(makeAvatar(name, 40))

  local badge = rowViews.badge
  if isCurrent then
    badge.setText(S.ai_current)
    badge.setTextColor(ColorOnPrimary)
    local bbg = GradientDrawable()
    bbg.setShape(GradientDrawable.OVAL)
    bbg.setColor(ColorPrimary)
    badge.setBackground(bbg)
  elseif conv.running then
    -- 该会话有任务进行中（进程被杀后标记可能残留，仅作提示）
    badge.setText(S.ai_conv_running)
    badge.setTextColor(ColorOnErrorContainer)
    local rbg = GradientDrawable()
    rbg.setCornerRadius(dp(8))
    rbg.setColor(ColorErrorContainer)
    badge.setBackground(rbg)
    badge.setPadding(dp(8), 0, dp(8), 0)
  end

  row.setOnClickListener(function() if onClick then onClick() end end)
  return row
end

local function buildManagerRow(conv, render)
  local name = convName(conv)
  local convId = conv and conv.id
  local rowViews = {}
  local row = loadlayout({
    LinearLayout,
    layout_width = "match",
    layout_height = "wrap",
    orientation = "horizontal",
    gravity = "center_vertical",
    layout_marginBottom = "8dp",
    paddingLeft = "12dp",
    paddingRight = "12dp",
    paddingTop = "8dp",
    paddingBottom = "8dp",
    {
      LinearLayout,
      id = "avatarSlot",
      layout_width = "wrap",
      layout_height = "wrap",
    },
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "0dp",
      layout_weight = 1,
      layout_height = "wrap",
      layout_marginLeft = "10dp",
      layout_marginRight = "4dp",
      {
        MaterialTextView,
        text = name,
        textSize = "15sp",
        textColor = ColorOnSurface,
        singleLine = true,
        ellipsize = "end",
      },
      {
        MaterialTextView,
        text = convMetaText(conv),
        textSize = "12sp",
        textColor = ColorText,
        singleLine = true,
        ellipsize = "end",
        layout_marginTop = "2dp",
      },
      {
        LinearLayout,
        layout_width = "match",
        layout_height = "wrap",
        gravity = "end",
        layout_marginTop = "6dp",
        {
          MaterialButton,
          text = S.ai_rename_btn,
          textSize = "12sp",
          layout_width = "wrap",
          layout_height = "wrap",
          allCaps = false,
          minWidth = 0,
          minHeight = 0,
          paddingLeft = "12dp",
          paddingRight = "12dp",
          BackgroundTintList = ColorStateList.valueOf(ColorSecondaryContainer),
          textColor = ColorOnSecondaryContainer,
          onClick = function() showRenameDialog(convId, name) end,
        },
        {
          MaterialButton,
          text = S.ai_delete,
          textSize = "12sp",
          layout_width = "wrap",
          layout_height = "wrap",
          layout_marginLeft = "8dp",
          allCaps = false,
          minWidth = 0,
          minHeight = 0,
          paddingLeft = "12dp",
          paddingRight = "12dp",
          BackgroundTintList = ColorStateList.valueOf(ColorErrorContainer),
          textColor = ColorOnErrorContainer,
          onClick = function()
            MaterialAlertDialogBuilder(activity)
              .setTitle(S.ai_delete_conv)
              .setMessage(S.ai_confirm_delete_conv:format(name))
              .setPositiveButton(S.ai_delete, function()
                AgentTurn.invalidate()
                if not AgentChat.deleteConversation(convId) then
                  print(S.ai_delete_failed)
                  return
                end
                local current = AgentChat.getCurrentConv()
                if not current then
                  AgentChat.createConversation()
                end
                onAfterDelete(convId)
                print(S.ai_deleted)
                render()
              end)
              .setNegativeButton(S.ai_cancel, nil)
              .show()
          end,
        },
      },
    },
  }, rowViews)

  rowViews.avatarSlot.addView(makeAvatar(name, 36))
  return row
end

--- 会话列表（按最近更新排序）；空列表时直接新建
function _M.showConvList()
  local list = AgentChat.listConversations()
  local currentConv = AgentChat.getCurrentConv()
  local currentId = currentConv and currentConv.id or nil
  -- 会话中心按最近更新排序，进行中的任务自然靠前
  table.sort(list, function(a, b)
    return tostring(a.conversation.updatedAt or "") > tostring(b.conversation.updatedAt or "")
  end)

  if #list == 0 then
    onNew()
    return
  end

  local dlgViews = {}
  local dlg = nil
  local content = loadlayout({
    ScrollView,
    layout_width = "match",
    layout_height = "match",
    fillViewport = true,
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      padding = "12dp",
      {
        LinearLayout,
        orientation = "horizontal",
        gravity = "center_vertical",
        layout_width = "match",
        layout_height = "wrap",
        padding = "8dp",
        paddingBottom = "2dp",
        {
          MaterialTextView,
          text = S.ai_switch_conv,
          textSize = "18sp", textStyle = "bold", textColor = ColorOnSurface,
          layout_width = "0dp", layout_weight = 1,
        },
        {
          MaterialTextView,
          id = "convCount",
          text = S.ai_conv_count:format(#list),
          textSize = "13sp", textColor = ColorText,
        },
      },
      {
        LinearLayout,
        id = "convList",
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        layout_marginTop = "2dp",
      },
      {
        LinearLayout,
        orientation = "horizontal",
        layout_width = "match",
        layout_height = "wrap",
        layout_marginTop = "4dp",
        {
          MaterialButton,
          id = "btnManage",
          text = S.ai_manage_convs,
          textSize = "14sp",
          layout_width = "0dp", layout_weight = 1,
          layout_marginRight = "6dp",
          BackgroundTintList = ColorStateList.valueOf(ColorSecondaryContainer),
          textColor = ColorOnSecondaryContainer,
        },
        {
          MaterialButton,
          id = "btnNew",
          text = S.ai_new_conv_btn,
          textSize = "14sp",
          layout_width = "0dp", layout_weight = 1,
          layout_marginLeft = "6dp",
          BackgroundTintList = ColorStateList.valueOf(ColorPrimary),
          textColor = ColorOnPrimary,
        },
      },
    },
  }, dlgViews)

  local container = dlgViews.convList
  container.removeAllViews()
  for _, item in ipairs(list) do
    local conv = item.conversation
    local row = buildConvRow(conv, conv.id == currentId, function()
      onSwitch(conv)
      if dlg then dlg.dismiss() end
    end)
    container.addView(row)
  end

  dlgViews.btnManage.onClick = function()
    if dlg then dlg.dismiss() end
    _M.showConvManager()
  end
  dlgViews.btnNew.onClick = function()
    onNew()
    if dlg then dlg.dismiss() end
  end

  dlg = MaterialAlertDialogBuilder(activity)
    .setView(content)
    .setNegativeButton(S.ai_close, nil)
    .show()
end

--- 会话管理器（重命名 / 删除 / 新建）
function _M.showConvManager()
  local list = AgentChat.listConversations()
  if #list == 0 then return end

  local dlgViews = {}
  local content = loadlayout({
    ScrollView,
    layout_width = "match",
    layout_height = "match",
    fillViewport = true,
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      padding = "12dp",
      {
        LinearLayout,
        orientation = "horizontal",
        gravity = "center_vertical",
        layout_width = "match",
        layout_height = "wrap",
        padding = "8dp",
        paddingBottom = "2dp",
        {
          MaterialTextView,
          text = S.ai_manage_convs,
          textSize = "18sp", textStyle = "bold", textColor = ColorOnSurface,
          layout_width = "0dp", layout_weight = 1,
        },
        {
          MaterialTextView,
          id = "convCount",
          text = S.ai_conv_count:format(#list),
          textSize = "13sp", textColor = ColorText,
        },
      },
      {
        LinearLayout,
        id = "convList",
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        layout_marginTop = "2dp",
      },
      {
        MaterialButton,
        id = "btnNew",
        text = S.ai_new_conv_btn,
        textSize = "14sp",
        layout_width = "match",
        layout_marginTop = "4dp",
        BackgroundTintList = ColorStateList.valueOf(ColorPrimary),
        textColor = ColorOnPrimary,
      },
    },
  }, dlgViews)

  local container = dlgViews.convList
  local function render()
    local currentList = AgentChat.listConversations()
    container.removeAllViews()
    for _, item in ipairs(currentList) do
      container.addView(buildManagerRow(item.conversation, render))
    end
    if dlgViews.convCount then dlgViews.convCount.setText(S.ai_conv_count:format(#currentList)) end
  end

  dlgViews.btnNew.onClick = function()
    onNew()
    render()
  end

  render()
  MaterialAlertDialogBuilder(activity)
    .setView(content)
    .setNegativeButton(S.ai_close, nil)
    .show()
end

return _M
