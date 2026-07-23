import "android.widget.LinearLayout"
import "android.widget.ScrollView"
import "android.widget.HorizontalScrollView"
import "android.widget.ImageView"
import "android.widget.FrameLayout"
import "android.content.res.ColorStateList"
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.button.MaterialButton"
import "vinx.material.textfield.MaterialTextField"
import "com.google.android.material.chip.Chip"
import "com.google.android.material.card.MaterialCardView"
import "com.google.android.material.materialswitch.MaterialSwitch"
import "com.google.android.material.divider.MaterialDivider"

local ColorUtil = this.themeUtil
local primary = ColorUtil.getColorPrimary()
local onSurface = ColorUtil.getColorOnSurface()
local onVar = ColorUtil.getColorOnSurfaceVariant()
local surfaceC = ColorUtil.getColorSurfaceContainer()
local outline = ColorUtil.getColorOutlineVariant()
local MDC_R = luajava.bindClass "com.google.android.material.R"

local function sectionLabel(text, top)
  return {
    MaterialTextView,
    text = text,
    textSize = "13sp",
    textStyle = "bold",
    textColor = primary,
    layout_marginTop = top or "16dp",
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
    paddingTop = "8dp",
    paddingBottom = "8dp",
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
      checked = checked == true,
    },
  }
end

local function field(id, hint, top)
  return {
    MaterialTextField,
    id = id,
    hint = hint,
    layout_width = "match",
    layout_height = "wrap",
    layout_marginTop = top or "8dp",
    textSize = "14sp",
    TintColor = primary,
    style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
    boxBackgroundMode = 2,
    singleLine = true,
  }
end

-- 不用 style=Button_*（loadlayout 对 MaterialButton style 支持差）；用 tint 做 Tonal / Outlined
-- 高度用 wrap，避免固定 40dp 裁切文字底部
local function tonalBtn(id, text, weight)
  return {
    MaterialButton,
    id = id,
    text = text,
    layout_width = weight and "0dp" or "wrap",
    layout_weight = weight,
    layout_height = "wrap",
    minHeight = "48dp",
    paddingTop = "10dp",
    paddingBottom = "10dp",
    paddingLeft = "16dp",
    paddingRight = "16dp",
    textSize = "13sp",
    includeFontPadding = false,
    BackgroundTintList = ColorStateList.valueOf(ColorUtil.getColorSecondaryContainer()),
    textColor = ColorUtil.getColorOnSecondaryContainer(),
  }
end

local function outlineBtn(id, text)
  return {
    MaterialButton,
    id = id,
    text = text,
    layout_width = "match",
    layout_height = "wrap",
    minHeight = "48dp",
    paddingTop = "12dp",
    paddingBottom = "12dp",
    textSize = "14sp",
    includeFontPadding = false,
    BackgroundTintList = ColorStateList.valueOf(0),
    textColor = primary,
    strokeWidth = "1dp",
    strokeColor = ColorStateList.valueOf(outline),
  }
end

local function filledBtn(id, text)
  return {
    MaterialButton,
    id = id,
    text = text,
    layout_width = "match",
    layout_height = "wrap",
    minHeight = "52dp",
    paddingTop = "14dp",
    paddingBottom = "14dp",
    textSize = "15sp",
    includeFontPadding = false,
    BackgroundTintList = ColorStateList.valueOf(primary),
    textColor = ColorUtil.getColorOnPrimary(),
  }
end

local function textBtn(id, text)
  return {
    MaterialButton,
    id = id,
    text = text,
    layout_width = "wrap",
    layout_height = "wrap",
    minHeight = "48dp",
    paddingTop = "10dp",
    paddingBottom = "10dp",
    paddingLeft = "12dp",
    paddingRight = "12dp",
    textSize = "13sp",
    includeFontPadding = false,
    BackgroundTintList = ColorStateList.valueOf(0),
    textColor = primary,
  }
end

return {
  LinearLayout,
  orientation = "vertical",
  layout_width = "match",
  layout_height = "match",
  BackgroundColor = "?attr/colorBackground",
  {
    ScrollView,
    layout_width = "match",
    layout_height = "0dp",
    layout_weight = 1,
    fillViewport = true,
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      paddingLeft = "18dp",
      paddingTop = "8dp",
      paddingRight = "18dp",
      paddingBottom = "12dp",
      Focusable = true,
      FocusableInTouchMode = true,

      sectionLabel(res.string.project_icon, "4dp"),
      {
        MaterialCardView,
        layout_width = "match",
        layout_height = "wrap",
        radius = "14dp",
        CardElevation = 0,
        strokeWidth = "1dp",
        strokeColor = outline,
        CardBackgroundColor = surfaceC,
        {
          LinearLayout,
          orientation = "horizontal",
          layout_width = "match",
          gravity = "center_vertical",
          padding = "14dp",
          {
            MaterialCardView,
            layout_width = "72dp",
            layout_height = "72dp",
            radius = "16dp",
            CardElevation = 0,
            strokeWidth = "1dp",
            strokeColor = outline,
            CardBackgroundColor = "?attr/colorSurface",
            {
              FrameLayout,
              layout_width = "match",
              layout_height = "match",
              {
                ImageView,
                id = "ps_icon",
                layout_width = "match",
                layout_height = "match",
                scaleType = "fitCenter",
                padding = "8dp",
              },
            },
          },
          {
            LinearLayout,
            orientation = "vertical",
            layout_width = "0dp",
            layout_weight = 1,
            layout_marginLeft = "14dp",
            {
              MaterialTextView,
              id = "ps_icon_hint",
              text = res.string.project_icon_hint,
              textSize = "12sp",
              textColor = onVar,
              lineSpacingMultiplier = 1.2,
            },
            {
              LinearLayout,
              orientation = "horizontal",
              layout_width = "match",
              layout_marginTop = "10dp",
              gravity = "center_vertical",
              tonalBtn("ps_pick_icon", res.string.project_pick_icon),
              textBtn("ps_clear_icon", res.string.project_clear_icon),
            },
          },
        },
      },

      sectionLabel(res.string.project_basic_info),
      {
        MaterialTextView,
        id = "ps_path",
        textSize = "11sp",
        textColor = onVar,
        layout_marginBottom = "4dp",
      },
      field("ps_app_name", res.string.project_app_name_hint, "0dp"),
      field("ps_package", res.string.project_package_hint),
      {
        LinearLayout,
        orientation = "horizontal",
        layout_width = "match",
        {
          MaterialTextField,
          id = "ps_ver_name",
          hint = res.string.project_ver_name,
          layout_width = "0dp",
          layout_weight = 1,
          layout_height = "wrap",
          layout_marginTop = "8dp",
          layout_marginRight = "6dp",
          textSize = "14sp",
          TintColor = primary,
          style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
          boxBackgroundMode = 2,
          singleLine = true,
        },
        {
          MaterialTextField,
          id = "ps_ver_code",
          hint = res.string.project_ver_code,
          layout_width = "0dp",
          layout_weight = 1,
          layout_height = "wrap",
          layout_marginTop = "8dp",
          layout_marginLeft = "6dp",
          textSize = "14sp",
          TintColor = primary,
          style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
          boxBackgroundMode = 2,
          singleLine = true,
        },
      },
      {
        LinearLayout,
        orientation = "horizontal",
        layout_width = "match",
        {
          MaterialTextField,
          id = "ps_min_sdk",
          hint = res.string.project_min_sdk,
          layout_width = "0dp",
          layout_weight = 1,
          layout_height = "wrap",
          layout_marginTop = "8dp",
          layout_marginRight = "6dp",
          textSize = "14sp",
          TintColor = primary,
          style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
          boxBackgroundMode = 2,
          singleLine = true,
        },
        {
          MaterialTextField,
          id = "ps_target_sdk",
          hint = res.string.project_target_sdk,
          layout_width = "0dp",
          layout_weight = 1,
          layout_height = "wrap",
          layout_marginTop = "8dp",
          layout_marginLeft = "6dp",
          textSize = "14sp",
          TintColor = primary,
          style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
          boxBackgroundMode = 2,
          singleLine = true,
        },
      },

      sectionLabel(res.string.project_theme),
      {
        MaterialTextView,
        text = res.string.project_theme_hint,
        textSize = "11sp",
        textColor = onVar,
        layout_marginBottom = "6dp",
      },
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
          padding = "12dp",
          {
            MaterialTextView,
            id = "ps_theme_label",
            textSize = "14sp",
            textColor = onSurface,
            textStyle = "bold",
          },
          {
            MaterialTextView,
            id = "ps_theme_value",
            textSize = "11sp",
            textColor = onVar,
            layout_marginTop = "2dp",
          },
          {
            MaterialButton,
            id = "ps_theme_pick",
            text = res.string.project_theme_pick,
            layout_width = "match",
            layout_height = "wrap",
            minHeight = "48dp",
            layout_marginTop = "10dp",
            paddingTop = "10dp",
            paddingBottom = "10dp",
            textSize = "13sp",
            includeFontPadding = false,
            BackgroundTintList = ColorStateList.valueOf(ColorUtil.getColorSecondaryContainer()),
            textColor = ColorUtil.getColorOnSecondaryContainer(),
          },
        },
      },

      sectionLabel(res.string.project_permissions),
      {
        MaterialTextView,
        text = res.string.project_permissions_hint,
        textSize = "11sp",
        textColor = onVar,
        layout_marginBottom = "6dp",
      },
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
          padding = "12dp",
          {
            MaterialTextView,
            id = "ps_perm_summary",
            textSize = "13sp",
            textColor = onSurface,
            lineSpacingMultiplier = 1.25,
          },
          {
            LinearLayout,
            orientation = "horizontal",
            layout_width = "match",
            layout_marginTop = "10dp",
            {
              MaterialButton,
              id = "ps_perm_edit",
              text = res.string.project_permissions_edit,
              layout_width = "0dp",
              layout_weight = 1,
              layout_height = "wrap",
              minHeight = "48dp",
              paddingTop = "10dp",
              paddingBottom = "10dp",
              textSize = "13sp",
              includeFontPadding = false,
              BackgroundTintList = ColorStateList.valueOf(ColorUtil.getColorSecondaryContainer()),
              textColor = ColorUtil.getColorOnSecondaryContainer(),
            },
            {
              MaterialButton,
              id = "ps_perm_add",
              text = res.string.project_permissions_add,
              layout_width = "0dp",
              layout_weight = 1,
              layout_height = "wrap",
              minHeight = "48dp",
              layout_marginLeft = "8dp",
              paddingTop = "10dp",
              paddingBottom = "10dp",
              textSize = "13sp",
              includeFontPadding = false,
              BackgroundTintList = ColorStateList.valueOf(0),
              textColor = primary,
              strokeWidth = "1dp",
              strokeColor = ColorStateList.valueOf(outline),
            },
          },
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
          optionRow(res.string.project_debug_mode, res.string.project_debug_mode_desc, "ps_debug", true),
        },
      },

      {
        MaterialDivider,
        layout_marginTop = "16dp",
        layout_marginBottom = "8dp",
      },
      outlineBtn("ps_open_init", res.string.project_open_init),
    },
  },
  {
    LinearLayout,
    orientation = "horizontal",
    layout_width = "match",
    layout_height = "wrap",
    paddingLeft = "16dp",
    paddingRight = "16dp",
    paddingTop = "8dp",
    paddingBottom = "12dp",
    gravity = "end",
    BackgroundColor = "?attr/colorSurface",
    elevation = "4dp",
    filledBtn("ps_save", res.string.save_file),
  },
}
