local ColorStateList = bindClass "android.content.res.ColorStateList"
local MaterialTextView = bindClass "com.google.android.material.textview.MaterialTextView"
local MaterialButton = bindClass "com.google.android.material.button.MaterialButton"
local MaterialDivider = bindClass "com.google.android.material.divider.MaterialDivider"
local MaterialCardView = bindClass "com.google.android.material.card.MaterialCardView"
local LinearLayout = bindClass "android.widget.LinearLayout"
local ImageView = bindClass "android.widget.ImageView"
local HorizontalScrollView = bindClass "android.widget.HorizontalScrollView"
local ScrollView = bindClass "android.widget.ScrollView"

local ColorUtil = this.themeUtil
local ColorPrimary = ColorUtil.getColorPrimary()
local ColorOnSurface = ColorUtil.getColorOnSurface()
local ColorText = ColorUtil.getColorOnSurfaceVariant()
local ColorSurface = ColorUtil.getColorSurfaceContainer()
local ColorOutline = ColorUtil.getColorOutlineVariant()

import "androidx.core.graphics.ColorUtils"
local ColorRipple = ColorUtils.blendARGB(ColorPrimary, 0x00ffffff, 0.4)
local res = res

local function actionBtn(id, text, iconName)
  return {
    MaterialButton,
    layout_width = "match",
    layout_height = "wrap",
    BackgroundTintList = ColorStateList.valueOf(0),
    id = id,
    text = text,
    textColor = ColorText,
    icon = res.drawable(iconName),
    iconTint = ColorStateList.valueOf(ColorPrimary),
    RippleColor = ColorStateList.valueOf(ColorRipple),
  }
end

return {
  ScrollView,
  layout_width = "match",
  layout_height = "wrap",
  {
    LinearLayout,
    layout_width = "match",
    layout_height = "wrap",
    orientation = "vertical",
    padding = "20dp",
    paddingBottom = "28dp",

    -- 项目信息卡片
    {
      MaterialCardView,
      layout_width = "match",
      layout_height = "wrap",
      radius = "16dp",
      CardElevation = 0,
      strokeWidth = "1dp",
      strokeColor = ColorOutline,
      CardBackgroundColor = ColorSurface,
      {
        LinearLayout,
        layout_width = "match",
        layout_height = "wrap",
        orientation = "horizontal",
        gravity = "center_vertical",
        padding = "14dp",
        {
          ImageView,
          id = "projectIcon",
          layout_width = "56dp",
          layout_height = "56dp",
          scaleType = "fitCenter",
        },
        {
          LinearLayout,
          layout_width = "0dp",
          layout_weight = 1,
          layout_height = "wrap",
          orientation = "vertical",
          layout_marginLeft = "14dp",
          {
            MaterialTextView,
            id = "nameText",
            textSize = "18sp",
            textStyle = "bold",
            textColor = ColorOnSurface,
          },
          {
            MaterialTextView,
            id = "packageText",
            textSize = "13sp",
            textColor = ColorPrimary,
            layout_marginTop = "2dp",
          },
          {
            MaterialTextView,
            id = "versionText",
            textSize = "12sp",
            textColor = ColorText,
            layout_marginTop = "2dp",
          },
        },
      },
    },

    {
      MaterialTextView,
      id = "pathText",
      textSize = "12sp",
      textColor = ColorText,
      layout_marginTop = "10dp",
    },

    {
      MaterialTextView,
      id = "metaText",
      textSize = "13sp",
      textColor = ColorOnSurface,
      layout_marginTop = "8dp",
      lineSpacingMultiplier = 1.25,
    },

    {
      MaterialTextView,
      id = "permLabel",
      textSize = "12sp",
      textStyle = "bold",
      textColor = ColorPrimary,
      text = res.string.project_permissions,
      layout_marginTop = "10dp",
      visibility = 8,
    },
    {
      HorizontalScrollView,
      layout_width = "match",
      layout_height = "wrap",
      horizontalScrollBarEnabled = false,
      {
        MaterialTextView,
        id = "permText",
        textSize = "12sp",
        textColor = ColorText,
        layout_marginTop = "4dp",
      },
    },

    {
      MaterialDivider,
      layout_marginTop = "12dp",
      layout_marginBottom = "6dp",
      dividerColor = ColorText,
    },

    actionBtn("button_open", res.string.project_open, "folder"),
    actionBtn("button_settings", res.string.project_settings, "settings"),
    actionBtn("button_open_init", res.string.project_open_init, "code"),
    actionBtn("button_run", res.string.run_project, "play"),
    actionBtn("button_backup", res.string.backup, "backup"),
    actionBtn("button_rename", res.string.rename, "rename"),
    actionBtn("button_cdir", res.string.new_dir, "new_folder"),
    actionBtn("button_cfile", res.string.new_file, "new_file"),
    actionBtn("button_delete", res.string.delete, "delete"),
  },
}
