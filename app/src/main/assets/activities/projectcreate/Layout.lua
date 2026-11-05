local UI = require "mods.ui.Components"
local LinearLayout = luajava.bindClass "android.widget.LinearLayout"
local FrameLayout = luajava.bindClass "android.widget.FrameLayout"
local ScrollView = luajava.bindClass "android.widget.ScrollView"
local TextView = luajava.bindClass "com.google.android.material.textview.MaterialTextView"
local Card = luajava.bindClass "com.google.android.material.card.MaterialCardView"
local Progress = luajava.bindClass "com.google.android.material.progressindicator.LinearProgressIndicator"
local Preview = require "activities.projectcreate.Preview"
local M = {}
function M.build(templates, selectTemplate)
  local colors = this.themeUtil
  local list = { LinearLayout, orientation = "vertical", layout_width = "match",
    layout_height = "wrap", padding = "20dp",
    { TextView, text = res.string.project_choose_template, textSize = "28sp",
      textColor = colors.getColorOnSurface(), layout_marginBottom = "8dp" },
    { TextView, text = res.string.project_template_select_hint, textSize = "16sp",
      textColor = colors.getColorOnSurfaceVariant(), layout_marginBottom = "24dp",
      layout_width = "match", layout_height = "wrap" },
  }
  for _, template in ipairs(templates) do
    local item = template
    list[#list + 1] = { Card, layout_width = "match", layout_height = "wrap",
      layout_marginBottom = "20dp", radius = "16dp", cardElevation = "0dp",
      cardBackgroundColor = colors.getColorSurface(), strokeWidth = "1dp",
      strokeColor = colors.getColorOutlineVariant(),
      clickable = true, focusable = true,
      contentDescription = res.string.project_choose_template .. ": " .. res.string[item.titleKey],
      onClick = function() selectTemplate(item) end,
      { LinearLayout, orientation = "vertical", layout_width = "match", layout_height = "wrap",
        padding = "16dp",
        { TextView, text = res.string[item.titleKey], textSize = "22sp",
          layout_width = "match", layout_height = "wrap", textColor = colors.getColorOnSurface() },
        { TextView, text = res.string[item.descriptionKey], textSize = "16sp",
          layout_width = "match", layout_height = "wrap",
          layout_marginTop = "8dp", textColor = colors.getColorOnSurfaceVariant() },
        Preview.build(item.id),
        { TextView, text = res.string.project_use_template, textSize = "14sp", textStyle = "bold",
          layout_width = "match", layout_height = "wrap", gravity = "end|center_vertical",
          minHeight = "48dp", layout_marginTop = "8dp", textColor = colors.getColorPrimary() },
      },
    }
  end
  -- Reuse shared Material fields inside the full-height page.
  local form = res.layout.new_project
  form.id, form.layout_height, form.visibility = "configuration", "match", "gone"
  form[2][#form[2] + 1] = { TextView, id = "review", visibility = "gone",
    textSize = "16sp", textColor = colors.getColorOnSurface(), textIsSelectable = true,
    backgroundColor = colors.getColorSurfaceContainer(), padding = "16dp",
    layout_width = "match", layout_height = "wrap", layout_marginTop = "20dp",
    accessibilityLiveRegion = 1 }
  return { LinearLayout, orientation = "vertical", layout_width = "match", layout_height = "match",
    background = colors.getColorBackground(),
    { FrameLayout, layout_width = "match", layout_height = "0dp", layout_weight = 1,
      { ScrollView, id = "templates", layout_width = "match", layout_height = "match", list },
      form,
    },
    { LinearLayout, id = "footer", orientation = "vertical", visibility = "gone",
      layout_width = "match", layout_height = "wrap", padding = "20dp",
      background = colors.getColorSurface(),
      { Progress, id = "progress", indeterminate = true, visibility = "gone",
        layout_width = "match", layout_height = "wrap" },
      { TextView, id = "status", visibility = "gone", textSize = "14sp",
        accessibilityLiveRegion = 1, textColor = colors.getColorOnSurfaceVariant() },
      UI.button { id = "primary", text = res.string.project_review,
        props = { layout_width = "match" } },
    },
  }
end
return M
