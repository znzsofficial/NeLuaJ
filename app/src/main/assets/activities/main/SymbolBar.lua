--- 底部符号栏
import "android.widget.LinearLayout"
import "android.widget.TextView"

local loadlayout = loadlayout
local rippleRes = activity.obtainStyledAttributes({ android.R.attr.selectableItemBackground }).getResourceId(0, 0)

local ORIENTATION_HORIZONTAL = 0
local ORIENTATION_VERTICAL = 1

local DEFAULT_SYMBOL_BAR = {
  "fun", "(", ")", "[", "]", "{", "}",
  "\"", "=", ":", ".", ",", ";", "_",
  "+", "-", "*", "/", "\\", "%",
  "#", "^", "$", "?", "&", "|",
  "<", ">", "~", "'"
}

local DEFAULT_SYMBOL_BAR_TEXT_SIZE = 5
local MIN_BAR_TEXT_SIZE = 5
local MAX_BAR_TEXT_SIZE = 24

local function isSharedTruthy(value)
  return value == true or value == "true" or value == 1
end

local function clampBarTextSize(value, defaultSize)
  local n = tonumber(value)
  if not n then return defaultSize end
  n = math.floor(n + 0.5)
  if n < MIN_BAR_TEXT_SIZE then return MIN_BAR_TEXT_SIZE end
  if n > MAX_BAR_TEXT_SIZE then return MAX_BAR_TEXT_SIZE end
  return n
end

local function getSymbolBarTextSize()
  return clampBarTextSize(
    this.getSharedData("symbol_bar_text_size", DEFAULT_SYMBOL_BAR_TEXT_SIZE),
    DEFAULT_SYMBOL_BAR_TEXT_SIZE
  )
end

local function parseSymbolBar(raw)
  if type(raw) ~= "string" or raw == "" then
    return nil
  end
  local symbols = {}
  for line in (raw .. "\n"):gmatch("(.-)\n") do
    local symbol = line:match("^%s*(.-)%s*$")
    if symbol ~= "" then
      symbols[#symbols + 1] = symbol
    end
  end
  return #symbols > 0 and symbols or nil
end

local function pasteSymbol(symbol)
  if symbol == "fun" then
    mLuaEditor.paste("function()")
  else
    mLuaEditor.paste(symbol)
  end
end

local function createSymbolButton(symbol, textSize)
  textSize = textSize or getSymbolBarTextSize()
  local side = math.max(40, math.floor(textSize * 3.2 + 0.5))
  local height = math.max(36, math.floor(textSize * 2.8 + 0.5))
  if textSize <= 6 then
    side, height = 40, 36
  end
  local sideDp = side .. "dp"
  local heightDp = height .. "dp"
  return loadlayout {
    LinearLayout,
    layout_width = sideDp,
    layout_height = heightDp,
    {
      TextView,
      layout_width = sideDp,
      layout_height = heightDp,
      gravity = "center",
      clickable = true,
      focusable = true,
      TextSize = textSize .. "sp",
      BackgroundResource = rippleRes,
      text = symbol,
      onClick = function()
        pasteSymbol(symbol)
      end,
    },
  }
end

local function createSymbolRow(rowHeightDp)
  return loadlayout {
    LinearLayout,
    orientation = "horizontal",
    layout_width = "wrap",
    layout_height = (rowHeightDp or 36) .. "dp",
  }
end

local function fillSymbolRow(row, symbols, fromIndex, toIndex, textSize)
  for i = fromIndex, toIndex do
    row.addView(createSymbolButton(symbols[i], textSize))
  end
  return row
end

local _M = {}

function _M.init(ps_bar)
  local symbols = parseSymbolBar(this.getSharedData("symbol_bar", nil)) or DEFAULT_SYMBOL_BAR
  local twoRows = isSharedTruthy(this.getSharedData("symbol_bar_two_rows", false))
  local textSize = getSymbolBarTextSize()
  local rowHeight = (textSize <= 6) and 36 or math.max(36, math.floor(textSize * 2.8 + 0.5))
  local count = #symbols

  ps_bar.removeAllViews()

  if twoRows and count > 0 then
    ps_bar.orientation = ORIENTATION_VERTICAL
    local mid = math.ceil(count / 2)
    ps_bar.addView(fillSymbolRow(createSymbolRow(rowHeight), symbols, 1, mid, textSize))
    if mid < count then
      ps_bar.addView(fillSymbolRow(createSymbolRow(rowHeight), symbols, mid + 1, count, textSize))
    end
  else
    ps_bar.orientation = ORIENTATION_HORIZONTAL
    fillSymbolRow(ps_bar, symbols, 1, count, textSize)
  end
end

return _M
