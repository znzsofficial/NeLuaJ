--- 跨工程会话列表共享渲染：AgentCenter 独立页与首页「会话」tab 共用。
--- 行为差异（点击打开方式）由调用方经 onOpen 回调注入；
--- 本模块只负责行构建、排序与空态，不持有容器与数据。
local _M = {}

local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
local MaterialCardView = luajava.bindClass("com.google.android.material.card.MaterialCardView")
local GradientDrawable = luajava.bindClass("android.graphics.drawable.GradientDrawable")
local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local TextUtil = require("mods.utils.TextUtil")

local S = res.string

function _M.shortProject(p)
  return tostring(p or ""):gsub("/+$", ""):gsub("^.*/", "")
end

--- projectName 非空时在元信息中追加工程名（跨工程场景）
function _M.buildRow(conv, projectName, onOpen)
  local ColorUtil = this.themeUtil
  local ColorPrimaryContainer = ColorUtil.primary.container
  local ColorOnPrimaryContainer = ColorUtil.primary.onContainer
  local ColorSurfaceContainerLow = ColorUtil.surface.containerLow
  local ColorOnSurface = ColorUtil.surface.on
  local ColorText = ColorUtil.surface.onVariant
  local ColorErrorContainer = ColorUtil.error.container
  local ColorOnErrorContainer = ColorUtil.error.onContainer
  local dp = function(n) return this.dpToPx(n) end

  local name = tostring(conv.name or "")
  if name == "" then name = S.ai_unnamed_conv end
  local firstChar = name:match("[\0-\127\192-\255][\128-\191]*") or "?"

  -- loadIndex 轻量记录只有 messageCount；完整记录（编辑器内）仍有 messages
  local n = tonumber(conv.messageCount) or (type(conv.messages) == "table" and #conv.messages or 0)
  local metaParts = { S.ai_center_msg_count:format(n) }
  local usage = type(conv.usage) == "table" and conv.usage or nil
  if usage and tonumber(usage.tokens) and tonumber(usage.tokens) > 0 then
    metaParts[#metaParts + 1] = S.ai_row_usage:format(TextUtil.fmtTokens(usage.tokens))
  end
  if tostring(conv.updatedAt or "") ~= "" then
    metaParts[#metaParts + 1] = tostring(conv.updatedAt)
  end
  if projectName then
    metaParts[#metaParts + 1] = _M.shortProject(projectName)
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
    if onOpen then onOpen(conv, projectName) end
  end)

  local cardLp = LinearLayout.LayoutParams(-1, -2)
  cardLp.bottomMargin = dp(8)
  card.setLayoutParams(cardLp)
  return card
end

--- 渲染整个列表到 container：rows = { { conv = 记录, projectName = 路径或 nil } }，
--- 按 updatedAt 降序排序；空列表显示占位提示。
function _M.renderList(container, rows, onOpen)
  container.removeAllViews()
  local sorted = {}
  for i, item in ipairs(rows) do sorted[i] = item end
  table.sort(sorted, function(a, b)
    return tostring(a.conv.updatedAt or "") > tostring(b.conv.updatedAt or "")
  end)

  if #sorted == 0 then
    local ColorUtil = this.themeUtil
    local empty = MaterialTextView(activity)
    empty.setText(S.ai_center_empty)
    empty.setTextSize(13)
    empty.setTextColor(ColorUtil.surface.onVariant)
    empty.setGravity(17)
    empty.setPadding(0, this.dpToPx(48), 0, this.dpToPx(48))
    container.addView(empty)
    return
  end

  for _, item in ipairs(sorted) do
    container.addView(_M.buildRow(item.conv, item.projectName, onOpen))
  end
end

return _M
