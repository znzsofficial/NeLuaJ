--- Fresh layout tables, not Views. Resolve the current Activity theme at call time.
--- props overrides native layout properties; options itself is never modified.
local M = {}
local MaterialButton = luajava.bindClass("com.google.android.material.button.MaterialButton")
local MaterialTextField = luajava.bindClass("vinx.material.textfield.MaterialTextField")
local MDC_R = luajava.bindClass("com.google.android.material.R")
local buttonStyles = {
  primary = "materialButtonStyle", tonal = "materialButtonTonalStyle",
  outlined = "materialButtonOutlinedStyle", text = "borderlessButtonStyle",
}
local iconStyles = {
  standard = "materialIconButtonStyle", filled = "materialIconButtonFilledStyle",
  tonal = "materialIconButtonFilledTonalStyle", outlined = "materialIconButtonOutlinedStyle",
}
local function finish(layout, options)
  for key, value in pairs(options.props or {}) do layout[key] = value end
  return layout
end
local function style(styles, variant)
  return "?attr/" .. assert(styles[variant], "Unknown UI variant: " .. tostring(variant))
end

function M.button(options)
  options = options or {}
  return finish({ MaterialButton,
    id = options.id, text = options.text, allCaps = false, textSize = "14sp",
    styleAttr = style(buttonStyles, options.variant or "primary"),
    minHeight = "48dp", minWidth = "48dp",
    layout_width = "wrap", layout_height = "wrap",
  }, options)
end

function M.iconButton(options)
  options = options or {}
  return finish({ MaterialButton,
    id = options.id, icon = options.icon,
    styleAttr = style(iconStyles, options.variant or "standard"),
    contentDescription = options.description, tooltipText = options.description,
    layout_width = "wrap", layout_height = "wrap",
  }, options)
end

function M.textField(options)
  options = options or {}
  return finish({ MaterialTextField,
    id = options.id, hint = options.hint, text = options.text,
    singleLine = options.singleLine == nil or options.singleLine,
    textSize = "14sp", layout_width = "match", layout_height = "wrap",
    tintColor = this.themeUtil.getColorPrimary(),
    style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox, boxBackgroundMode = 2,
  }, options)
end

return M
