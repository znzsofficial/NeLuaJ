import "android.widget.LinearLayout"
import "android.widget.ScrollView"
import "android.widget.HorizontalScrollView"
import "com.google.android.material.textview.MaterialTextView"
import "vinx.material.textfield.MaterialTextField"
import "com.google.android.material.chip.Chip"
import "com.google.android.material.card.MaterialCardView"
import "com.google.android.material.materialswitch.MaterialSwitch"
local ColorUtil = this.themeUtil
local MDC_R = luajava.bindClass "com.google.android.material.R"
local primary = ColorUtil.getColorPrimary()
local onSurface = ColorUtil.getColorOnSurface()
local onVar = ColorUtil.getColorOnSurfaceVariant()
local surfaceC = ColorUtil.getColorSurfaceContainer()
local outline = ColorUtil.getColorOutlineVariant()

local function sectionLabel(text, top)
  return {
    MaterialTextView,
    text = text,
    textSize = "13sp",
    textStyle = "bold",
    textColor = primary,
    layout_marginTop = top or "14dp",
    layout_marginBottom = "6dp",
  }
end

local function optionRow(title, desc, switchId, checked)
  return {
    LinearLayout,
    layout_width = "match",
    gravity = "center_vertical",
    paddingLeft = "12dp",
    paddingRight = "10dp",
    paddingTop = "6dp",
    paddingBottom = "6dp",
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "0dp",
      layout_weight = 1,
      {
        MaterialTextView,
        text = title,
        textSize = "14sp",
        textColor = onSurface,
      },
      {
        MaterialTextView,
        text = desc,
        textSize = "11sp",
        textColor = onVar,
      },
    },
    {
      MaterialSwitch,
      id = switchId,
      checked = checked ~= false,
    },
  }
end

local function hChip(id, text, checkable)
  return {
    Chip,
    id = id,
    text = text,
    Checkable = checkable ~= false,
    CheckedIconEnabled = true,
    layout_marginRight = "6dp",
    style = MDC_R.style.Widget_Material3_Chip,
  }
end

return {
  ScrollView,
  layout_width = "match",
  layout_height = "wrap",
  {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    paddingLeft = "18dp",
    paddingTop = "6dp",
    paddingRight = "18dp",
    paddingBottom = "6dp",
    Focusable = true,
    FocusableInTouchMode = true,

    sectionLabel(res.string.project_basic_info, "4dp"),
    {
      MaterialTextField,
      id = "project_appName",
      hint = res.string.project_app_name_hint,
      layout_width = "match",
      layout_height = "wrap",
      textSize = "14sp",
      TintColor = primary,
      style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
      boxBackgroundMode = 2,
      singleLine = true,
    },
    {
      MaterialTextField,
      id = "project_packageName",
      layout_marginTop = "10dp",
      hint = res.string.project_package_hint,
      layout_width = "match",
      layout_height = "wrap",
      textSize = "14sp",
      TintColor = primary,
      style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
      boxBackgroundMode = 2,
      singleLine = true,
    },
    {
      MaterialTextView,
      id = "project_path_preview",
      textSize = "11sp",
      textColor = onVar,
      layout_marginTop = "6dp",
      lineSpacingMultiplier = 1.15,
    },

    sectionLabel(res.string.project_theme),
    {
      MaterialTextView,
      text = res.string.project_theme_hint,
      textSize = "11sp",
      textColor = onVar,
      layout_marginBottom = "4dp",
    },
    {
      HorizontalScrollView,
      layout_width = "match",
      layout_height = "wrap",
      horizontalScrollBarEnabled = false,
      {
        LinearLayout,
        orientation = "horizontal",
        layout_width = "wrap",
        layout_height = "wrap",
        id = "project_theme_row",
        hChip("theme_m3", res.string.project_theme_m3, true),
        hChip("theme_dynamic", res.string.project_theme_dynamic, true),
        hChip("theme_actionbar", res.string.project_theme_actionbar, true),
      },
    },

    sectionLabel(res.string.project_options),
    {
      MaterialCardView,
      layout_width = "match",
      layout_height = "wrap",
      radius = "12dp",
      CardElevation = 0,
      strokeWidth = "1dp",
      strokeColor = outline,
      CardBackgroundColor = surfaceC,
      {
        LinearLayout,
        orientation = "vertical",
        layout_width = "match",
        paddingTop = "2dp",
        paddingBottom = "2dp",
        optionRow(res.string.project_open_after, res.string.project_open_after_desc, "project_open_after", true),
        optionRow(res.string.project_sample_ui, res.string.project_sample_ui_desc, "project_sample_ui", true),
        optionRow(res.string.project_internet, res.string.project_internet_desc, "project_internet", true),
        optionRow(res.string.project_debug_mode, res.string.project_debug_mode_desc, "project_debug_mode", true),
      },
    },

    sectionLabel(res.string.modules),
    {
      MaterialTextView,
      text = res.string.project_modules_hint,
      textSize = "11sp",
      textColor = onVar,
      layout_marginBottom = "4dp",
    },
    {
      HorizontalScrollView,
      layout_width = "match",
      layout_height = "wrap",
      horizontalScrollBarEnabled = false,
      {
        LinearLayout,
        orientation = "horizontal",
        layout_width = "wrap",
        layout_height = "wrap",
        id = "project_module_row",
        hChip("module_vconsole", "vConsole", true),
        hChip("module_time", "TimeMeter", true),
        hChip("module_array", "Array", true),
        hChip("module_strings", "Strings", true),
        hChip("module_anim", "ObjectAnimator", true),
        hChip("module_rxlua", "RxLua", true),
      },
    },
  },
}
