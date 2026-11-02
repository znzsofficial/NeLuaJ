--- 原生自适应表格组件：在移动端呈现带细边框、斑马纹、对齐支持且横向丝滑滑动的现代表格。
--- 彻底替代在单行文本内用“3 个空格”模拟的假表格。
local _M = {}
local Markdown = require("mods.agent.Markdown")

local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local HorizontalScrollView = luajava.bindClass("android.widget.HorizontalScrollView")
local TableLayout = luajava.bindClass("android.widget.TableLayout")
local TableRow = luajava.bindClass("android.widget.TableRow")
local MaterialCardView = luajava.bindClass("com.google.android.material.card.MaterialCardView")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
local MaterialButton = luajava.bindClass("com.google.android.material.button.MaterialButton")
local LinkMovementMethod = luajava.bindClass("android.text.method.LinkMovementMethod")
local Gravity = luajava.bindClass("android.view.Gravity")

import "androidx.core.graphics.ColorUtils"

local ColorUtil = this.themeUtil
local ColorPrimary = ColorUtil.primary.main
local ColorOnPrimaryContainer = ColorUtil.primary.onContainer
local ColorPrimaryContainer = ColorUtil.primary.container
local ColorSurface = ColorUtil.surface.container
local ColorOnSurface = ColorUtil.surface.on
local ColorText = ColorUtil.surface.onVariant
local ColorSurfaceContainerLow = ColorUtil.surface.containerLow
local ColorSurfaceContainerHigh = ColorUtil.surface.containerHigh
local ColorOutline = ColorUtil.outline.variant

local dp = function(n) return this.dpToPx(n) end

--- 创建自适应原生表格 View
--- @param tableNode table 包含 headers, alignments, rows 的 AST 节点
--- @param isUser boolean 是否为用户气泡
function _M.createTableView(tableNode, isUser)
  if not tableNode or not tableNode.headers or #tableNode.headers == 0 then
    return nil
  end

  local headers = tableNode.headers
  local alignments = tableNode.alignments or {}
  local rows = tableNode.rows or {}

  local tableBg = isUser and ColorUtils.blendARGB(ColorPrimaryContainer, ColorOnPrimaryContainer, 0.08) or ColorSurfaceContainerLow
  local headerBg = isUser and ColorUtils.blendARGB(ColorPrimaryContainer, ColorOnPrimaryContainer, 0.16) or ColorSurfaceContainerHigh
  local zebraBg = isUser and ColorUtils.blendARGB(ColorPrimaryContainer, ColorOnPrimaryContainer, 0.04) or ColorUtils.blendARGB(ColorSurface, ColorOnSurface, 0.03)
  local borderColor = isUser and ColorUtils.blendARGB(ColorPrimaryContainer, ColorOnPrimaryContainer, 0.20) or ColorOutline
  local textColor = isUser and ColorOnPrimaryContainer or ColorOnSurface
  local headerTextColor = isUser and ColorOnPrimaryContainer or ColorPrimary
  local function setCellText(tv, text)
    tv.setText(Markdown.renderInline(text, {
      codeColor = textColor, linkColor = headerTextColor,
    }))
    tv.setMovementMethod(LinkMovementMethod.getInstance())
    tv.setLinksClickable(true)
  end

  local views = {}
  local tableCard = loadlayout({
    MaterialCardView,
    radius = "10dp",
    CardElevation = 0,
    strokeWidth = "1dp",
    strokeColor = borderColor,
    CardBackgroundColor = tableBg,
    layout_width = "match",
    layout_height = "wrap",
    {
      HorizontalScrollView,
      layout_width = "match",
      layout_height = "wrap",
      horizontalScrollBarEnabled = false,
      {
        TableLayout,
        id = "tableRoot",
        layout_width = "wrap",
        layout_height = "wrap",
        stretchAllColumns = true,
      },
    },
  }, views)

  local tableRoot = views.tableRoot
  if not tableRoot then return tableCard end

  local function gravityFor(align)
    if align == "center" then return Gravity.CENTER
    elseif align == "right" then return Gravity.RIGHT or Gravity.END
    end
    return Gravity.LEFT or Gravity.START
  end

  -- 1. 渲染表头行
  local headerRow = TableRow(activity)
  headerRow.setBackgroundColor(headerBg)
  for colIdx, headerText in ipairs(headers) do
    local tv = MaterialTextView(activity)
    setCellText(tv, headerText)
    tv.setTextSize(12)
    tv.setTypeface(tv.getTypeface(), 1) -- Bold
    tv.setTextColor(headerTextColor)
    tv.setGravity(gravityFor(alignments[colIdx]))
    tv.setPadding(dp(12), dp(8), dp(12), dp(8))
    headerRow.addView(tv)
  end
  tableRoot.addView(headerRow)

  -- Render in batches so every row remains accessible without a huge initial bind.
  local renderedRows = 0
  local function appendRows()
    local maxRows = math.min(#rows, renderedRows + 30)
    for rowIdx = renderedRows + 1, maxRows do
      local rowData = rows[rowIdx]
      local row = TableRow(activity)
      if rowIdx % 2 == 0 then
        row.setBackgroundColor(zebraBg)
      end
      for colIdx = 1, #headers do
        local cellText = rowData[colIdx] or ""
        local tv = MaterialTextView(activity)
        setCellText(tv, cellText)
        tv.setTextSize(12)
        tv.setTextColor(textColor)
        tv.setGravity(gravityFor(alignments[colIdx]))
        tv.setPadding(dp(12), dp(7), dp(12), dp(7))
        row.addView(tv)
      end
      tableRoot.addView(row)
    end
    renderedRows = maxRows
  end
  appendRows()

  -- 超出保护提示
  if #rows > renderedRows then
    local tipRow = TableRow(activity)
    local tipTv = MaterialButton(activity)
    local function updateLabel()
      tipTv.setText(string.format(res.string.ai_table_more or "Show more (%d rows remaining)", #rows - renderedRows))
    end
    updateLabel()
    tipTv.setTextSize(11)
    tipTv.setTextColor(ColorText)
    tipTv.setPadding(dp(12), dp(6), dp(12), dp(6))
    local tipLp = TableRow.LayoutParams(-2, -2)
    tipLp.span = math.max(1, #headers)
    tipRow.addView(tipTv, tipLp)
    tableRoot.addView(tipRow)
    tipTv.setOnClickListener(function()
      tableRoot.removeView(tipRow)
      appendRows()
      if renderedRows < #rows then
        updateLabel()
        tableRoot.addView(tipRow)
      end
    end)
  end

  return tableCard
end

return _M
