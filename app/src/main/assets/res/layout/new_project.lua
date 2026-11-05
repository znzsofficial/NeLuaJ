import "android.widget.LinearLayout"
import "android.widget.ScrollView"
import "android.widget.Spinner"
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.chip.Chip"
import "com.google.android.material.chip.ChipGroup"
import "com.google.android.material.materialswitch.MaterialSwitch"
local UI = require "mods.ui.Components"
local colors = this.themeUtil
local MDC_R = luajava.bindClass "com.google.android.material.R"

local function label(text)
  return { MaterialTextView, text = text, textSize = "20sp",
    layout_width = "match", layout_height = "wrap",
    textColor = colors.getColorOnSurface(), layout_marginTop = "24dp", layout_marginBottom = "12dp" }
end

local function description(id, text)
  return { MaterialTextView, id = id, text = text, textSize = "14sp",
    layout_width = "match", layout_height = "wrap", layout_marginTop = "8dp",
    textColor = colors.getColorOnSurfaceVariant() }
end

local function dropdown(id, title)
  return { LinearLayout, layout_width = "match", layout_height = "wrap",
    minHeight = "56dp", gravity = "center_vertical", paddingStart = "12dp", paddingEnd = "8dp",
    background = colors.getColorSurface(),
    { Spinner, id = id, layout_width = "match", layout_height = "wrap",
      minHeight = "56dp", contentDescription = title },
  }
end

local function option(title, desc, id, value)
  return { LinearLayout, layout_width = "match", layout_height = "wrap",
    gravity = "center_vertical", paddingTop = "16dp", paddingBottom = "16dp",
    { LinearLayout, orientation = "vertical", layout_width = "0dp", layout_weight = 1,
      { MaterialTextView, text = title, textSize = "16sp", textColor = colors.getColorOnSurface() },
      description(nil, desc),
    },
    { MaterialSwitch, id = id, checked = value, contentDescription = title,
      minWidth = "48dp", minHeight = "48dp", layout_marginStart = "16dp" },
  }
end

local function chip(id, text)
  return { Chip, id = id, text = text, checkable = true, checkedIconEnabled = true,
    textSize = "14sp", minHeight = "48dp", ensureMinTouchTargetSize = true,
    style = MDC_R.style.Widget_Material3_Chip }
end

local moduleGroup = { ChipGroup, layout_width = "match", layout_height = "wrap",
  chipSpacingHorizontal = "8dp", chipSpacingVertical = "8dp", layout_marginTop = "12dp",
  chip("module_vconsole", "vConsole"), chip("module_time", "TimeMeter"),
  chip("module_array", "Array"), chip("module_strings", "Strings"),
  chip("module_anim", "ObjectAnimator"), chip("module_rxlua", "RxLua"),
}

return { ScrollView, layout_width = "match", layout_height = "wrap", fillViewport = true,
  { LinearLayout, orientation = "vertical", layout_width = "match", layout_height = "wrap",
    paddingLeft = "20dp", paddingRight = "20dp", paddingTop = "16dp", paddingBottom = "24dp",
    focusable = true, focusableInTouchMode = true,
    { MaterialTextView, id = "project_template_summary", textSize = "24sp",
      layout_width = "match", layout_height = "wrap", textColor = colors.getColorOnSurface() },
    description("project_template_description"),
    UI.button { id = "project_change_template", text = res.string.project_change_template, variant = "text",
      props = { layout_marginTop = "8dp" } },
    label(res.string.project_basic_info),
    UI.textField { id = "project_appName", hint = res.string.project_app_name_hint,
      props = { textSize = "16sp" } },
    UI.textField { id = "project_packageName", hint = res.string.project_package_hint,
      props = { textSize = "16sp", layout_marginTop = "16dp" } },
    description("project_path_preview"),
    label(res.string.project_theme_family),
    dropdown("project_theme_family", res.string.project_theme_family),
    description("project_theme_description"),
    description("project_theme_compatibility"),
    label(res.string.project_titlebar),
    dropdown("project_titlebar", res.string.project_titlebar),
    description("project_titlebar_description"),
    option(res.string.project_open_after, res.string.project_open_after_desc, "project_open_after", true),
    UI.button { id = "project_advanced_toggle", text = res.string.project_advanced_show, variant = "text",
      props = { layout_marginTop = "8dp" } },
    { LinearLayout, id = "project_advanced", orientation = "vertical", visibility = "gone",
      layout_width = "match", layout_height = "wrap",
      option(res.string.project_internet, res.string.project_internet_desc, "project_internet", false),
      option(res.string.project_debug_mode, res.string.project_debug_mode_desc, "project_debug_mode", true),
      label(res.string.modules), description(nil, res.string.project_modules_hint), moduleGroup,
    },
    { MaterialTextView, id = "project_error", visibility = "gone", textSize = "14sp",
      layout_width = "match", layout_height = "wrap", layout_marginTop = "12dp",
      accessibilityLiveRegion = 1, textColor = colors.getColorError() },
  },
}
