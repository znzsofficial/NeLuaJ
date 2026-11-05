--- Shared home rhythm: 20dp gutters, 24dp sections, 12dp row gaps, 16dp cards.
--- Resolve colors when building each view, never retain a prior Activity's palette.
local M = {}
local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local TextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
local UI = require "mods.ui.Components"
local CoordinatorLayout = luajava.bindClass("androidx.coordinatorlayout.widget.CoordinatorLayout")
local AppBarLayout = luajava.bindClass("com.google.android.material.appbar.AppBarLayout")

function M.action(id, text, kind)
  return UI.button { id = id, text = text, variant = kind == "quiet" and "text" or kind }
end

function M.header(title, action)
  local row = { LinearLayout, orientation = "horizontal", gravity = "center_vertical",
    layout_width = "match", layout_height = "wrap", paddingTop = "16dp", paddingBottom = "16dp",
    { TextView, text = title, textSize = "28sp", textColor = this.themeUtil.getColorOnSurface(),
      layout_width = "0dp", layout_weight = 1, layout_height = "wrap" },
  }
  if action then
    action.layout_marginStart = "12dp"
    action.maxWidth = "160dp"
    row[#row + 1] = action
  end
  return row
end

function M.section(title)
  return { TextView, text = title, textSize = "14sp", textStyle = "bold",
    textColor = this.themeUtil.getColorOnSurfaceVariant(),
    layout_width = "match", layout_height = "wrap", layout_marginTop = "24dp", layout_marginBottom = "12dp" }
end

-- Scroll the chrome away instead of letting it consume the entire list viewport
-- in landscape, split screen or large fonts. RecyclerView remains virtualized.
function M.listPage(header, list)
  header.layout_scrollFlags = 5 -- SCROLL | ENTER_ALWAYS
  list.layout_height, list.layout_weight = "match", nil
  list.layout_behavior = "@string/appbar_scrolling_view_behavior"
  list.paddingLeft, list.paddingRight = "20dp", "20dp"
  return { CoordinatorLayout, layout_width = "match", layout_height = "match",
    backgroundColor = this.themeUtil.getColorSurface(),
    { AppBarLayout, id = "pageHeader", layout_width = "match", layout_height = "wrap",
      backgroundColor = this.themeUtil.getColorSurface(), elevation = 0, targetElevation = 0, liftOnScroll = false,
      header,
    },
    list,
  }
end

return M
