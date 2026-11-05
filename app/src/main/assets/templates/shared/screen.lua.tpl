-- This helper ships with the generated application; it has no IDE dependencies.
local bindClass = luajava.bindClass
local LinearLayout = bindClass "android.widget.LinearLayout"
local CompatToolbar = bindClass "androidx.appcompat.widget.Toolbar"
local MaterialToolbar = bindClass "com.google.android.material.appbar.MaterialToolbar"
local AppCompatAttr = bindClass "androidx.appcompat.R$attr"
local MaterialAttr = bindClass "com.google.android.material.R$attr"
local TypedValue = bindClass "android.util.TypedValue"

local function booleanAttribute(theme, attribute)
  local value = TypedValue()
  local found = theme.resolveAttribute(attribute, value, true)
  return found and value.type == TypedValue.TYPE_INT_BOOLEAN and value.data ~= 0
end

local M = {}

-- Compat and Material Components do not define every M3 color role.
-- Keep the blank starter usable when init.lua changes after generation.
function M.colors()
  local theme = activity.getTheme()
  local m3 = booleanAttribute(theme, MaterialAttr.isMaterial3Theme)
  local material = m3 or booleanAttribute(theme, MaterialAttr.isMaterialTheme)
  return {
    text = material and "?attr/colorOnSurface" or "?android:attr/textColorPrimary",
    secondary = m3 and "?attr/colorOnSurfaceVariant" or "?android:attr/textColorSecondary",
  }
end

function M.wrap(content, showToolbar)
  -- LuaActivity already applied init.lua. Read its active theme, not a frozen
  -- generator choice or a second evaluation of the project's configuration.
  -- Resolve on each wrap so even a cached helper follows the current activity.
  local theme = activity.getTheme()
  local hasSystemActionBar = booleanAttribute(theme, AppCompatAttr.windowActionBar)
  local material = booleanAttribute(theme, MaterialAttr.isMaterialTheme)
    or booleanAttribute(theme, MaterialAttr.isMaterial3Theme)
  local layout = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
  }
  if material then layout.BackgroundColor = "?attr/colorSurface" end
  if not hasSystemActionBar and showToolbar ~= false then
    layout[#layout + 1] = {
      material and MaterialToolbar or CompatToolbar,
      id = "toolbar",
      layout_width = "match",
      layout_height = "?attr/actionBarSize",
      titleTextColor = M.colors().text,
    }
  end
  layout[#layout + 1] = content
  return layout
end

function M.show(layout, title)
  local views = {}
  local content = loadlayout(layout, views)
  activity.setContentView(content)
  if views.toolbar then activity.setSupportActionBar(views.toolbar) end
  local actionBar = activity.getSupportActionBar()
  if actionBar then actionBar.setTitle(title) end
  activity.setTitle(title)
  return views
end

return M
