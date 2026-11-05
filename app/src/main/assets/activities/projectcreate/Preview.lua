--- Small native View compositions, never execute a template or start a WebView.
--- Children are presentation-only: the containing template row owns the click.
local LinearLayout = luajava.bindClass "android.widget.LinearLayout"
local TextView = luajava.bindClass "com.google.android.material.textview.MaterialTextView"
local CheckBox = luajava.bindClass "androidx.appcompat.widget.AppCompatCheckBox"
local Switch = luajava.bindClass "androidx.appcompat.widget.SwitchCompat"
local UI = require "mods.ui.Components"
local M = {}

function M.build(id)
  local colors, S = this.themeUtil, res.string
  local function text(value, primary)
    return { TextView, text = value, textSize = primary and "20sp" or "16sp",
      textColor = primary and colors.getColorPrimary() or colors.getColorOnSurface(),
      layout_width = "match", layout_height = "wrap", paddingTop = "4dp", paddingBottom = "4dp" }
  end
  local function action(value)
    return UI.button { text = value, variant = "tonal", props = {
      layout_marginTop = "12dp", layout_gravity = "end", minHeight = "48dp",
      clickable = false, focusable = false,
    } }
  end
  local function field(value)
    local row = text(value)
    row.padding, row.layout_marginTop, row.minHeight = "12dp", "8dp", "48dp"
    row.gravity = "center_vertical"
    row.textColor = colors.getColorOnSurfaceVariant()
    row.backgroundColor = colors.getColorSurface()
    return row
  end
  local function toggle(value, checked, useSwitch)
    return { useSwitch and Switch or CheckBox, text = value, checked = checked,
      textSize = "16sp", textColor = colors.getColorOnSurface(),
      clickable = false, focusable = false, minHeight = "48dp", minWidth = 0,
      layout_width = "match", layout_height = "wrap" }
  end
  local panel = { LinearLayout, orientation = "vertical", layout_width = "match",
    layout_height = "wrap", padding = "16dp", layout_marginTop = "16dp",
    backgroundColor = colors.getColorSurfaceContainer(), importantForAccessibility = 4,
    descendantFocusability = 0x60000, clickable = false, focusable = false,
  }
  local rows
  if id == "blank" then
    local body = text(S.project_preview_blank)
    body.gravity, body.minHeight, body.textSize = "center", "120dp", "20sp"
    rows = { body }
  elseif id == "form" then
    rows = { field(S.project_preview_name), action(S.project_preview_greet), text(S.project_preview_greeting) }
  elseif id == "list" then
    rows = { field(S.project_preview_task), toggle(S.project_preview_task_first, false), toggle(S.project_preview_task_done, true) }
  elseif id == "navigation" then
    rows = { field(S.project_preview_message), action(S.project_preview_detail), field(S.project_preview_back) }
  elseif id == "settings" then
    rows = { toggle(S.project_preview_friendly, true, true), field(S.project_preview_size), action(S.project_preview_save) }
  elseif id == "webview" then
    rows = { field("index.html"), text("HTML / CSS / JS", true), field("0"), action(S.project_preview_add) }
  else error("Unknown template preview: " .. tostring(id)) end
  for _, row in ipairs(rows) do panel[#panel + 1] = row end
  return panel
end
return M
