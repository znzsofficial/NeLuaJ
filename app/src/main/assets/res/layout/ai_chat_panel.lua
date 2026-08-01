local ColorStateList = bindClass "android.content.res.ColorStateList"
local MaterialTextView = bindClass "com.google.android.material.textview.MaterialTextView"
local MaterialButton = bindClass "com.google.android.material.button.MaterialButton"
local MaterialCardView = bindClass "com.google.android.material.card.MaterialCardView"
local MaterialDivider = bindClass "com.google.android.material.divider.MaterialDivider"
local LinearLayout = bindClass "android.widget.LinearLayout"
local ScrollView = bindClass "android.widget.ScrollView"
local EditText = bindClass "android.widget.EditText"
local FrameLayout = bindClass "android.widget.FrameLayout"
local ProgressBar = bindClass "android.widget.ProgressBar"

local ColorUtil = this.themeUtil
local ColorPrimary = ColorUtil.getColorPrimary()
local ColorOnPrimary = ColorUtil.getColorOnPrimary()
local ColorSurface = ColorUtil.getColorSurfaceContainer()
local ColorOnSurface = ColorUtil.getColorOnSurface()
local ColorText = ColorUtil.getColorOnSurfaceVariant()
local ColorOutline = ColorUtil.getColorOutlineVariant()
local ColorBg = ColorUtil.getColorBackground()
local ColorError = ColorUtil.getColorError()

import "androidx.core.graphics.ColorUtils"
local ColorRipple = ColorUtils.blendARGB(ColorPrimary, 0x00ffffff, 0.4)
local res = res

return {
  LinearLayout,
  layout_width = "match",
  layout_height = "match",
  orientation = "vertical",
  -- 标题栏
  {
    LinearLayout,
    layout_width = "match",
    layout_height = "wrap",
    orientation = "horizontal",
    gravity = "center_vertical",
    padding = "12dp",
    paddingLeft = "16dp",
    paddingRight = "8dp",
    {
      MaterialTextView,
      id = "aiTitle",
      text = res.string.ai_chat,
      textSize = "18sp",
      textStyle = "bold",
      textColor = ColorOnSurface,
      layout_width = "0dp",
      layout_weight = 1,
      layout_height = "wrap",
      maxLines = 1,
      ellipsize = "end",
    },
    {
      MaterialCardView,
      id = "modelChip",
      radius = "16dp", CardElevation = 0,
      strokeWidth = "1dp", strokeColor = ColorOutline,
      CardBackgroundColor = ColorSurface,
      layout_marginRight = "8dp",
      {
        MaterialTextView,
        id = "modelLabel", text = "gpt-4o-mini",
        textSize = "11sp", textColor = ColorPrimary,
        padding = "6dp", paddingLeft = "10dp", paddingRight = "10dp",
      },
    },
    {
      MaterialButton,
      id = "btnSettings",
      styleAttr = "?attr/materialIconButtonStyle",
      layout_width = "40dp", layout_height = "40dp",
      BackgroundTintList = ColorStateList.valueOf(0),
      icon = res.drawable("ic_settings"),
      iconTint = ColorStateList.valueOf(ColorText),
      RippleColor = ColorStateList.valueOf(ColorRipple),
      layout_marginRight = "2dp",
    },
    {
      MaterialButton,
      id = "btnClear",
      styleAttr = "?attr/materialIconButtonStyle",
      layout_width = "40dp", layout_height = "40dp",
      BackgroundTintList = ColorStateList.valueOf(0),
      icon = res.drawable("ic_clear"),
      iconTint = ColorStateList.valueOf(ColorText),
      RippleColor = ColorStateList.valueOf(ColorRipple),
    },
  },
  { MaterialDivider, dividerColor = ColorOutline },
  -- 消息列表
  {
    ScrollView,
    id = "msgScroll",
    layout_width = "match",
    layout_height = "0dp",
    layout_weight = 1,
    fillViewport = true,
    {
      LinearLayout,
      id = "msgContainer",
      layout_width = "match",
      layout_height = "wrap",
      orientation = "vertical",
      padding = "12dp",
      paddingBottom = "4dp",
    },
  },
  { MaterialDivider, dividerColor = ColorOutline },
  -- 输入区域
  {
    LinearLayout,
    layout_width = "match",
    layout_height = "wrap",
    orientation = "vertical",
    padding = "12dp",
    paddingTop = "8dp",
    {
      LinearLayout,
      layout_width = "match",
      layout_height = "wrap",
      orientation = "horizontal",
      gravity = "center_vertical",
      {
        MaterialCardView,
        radius = "22dp",
        CardElevation = 0,
        strokeWidth = "1dp",
        strokeColor = ColorOutline,
        CardBackgroundColor = ColorSurface,
        layout_width = "0dp",
        layout_weight = 1,
        layout_height = "wrap",
        {
          EditText,
          id = "msgInput",
          layout_width = "match",
          layout_height = "wrap",
          minHeight = "40dp",
          hint = res.string.ai_input_hint,
          textSize = "14sp",
          textColor = ColorOnSurface,
          hintTextColor = ColorText,
          background = 0,
          padding = "12dp",
          singleLine = false,
          maxLines = 4,
          inputType = 0x00002001,
        },
      },
      {
        MaterialButton,
        id = "btnSend",
        styleAttr = "?attr/materialIconButtonStyle",
        layout_width = "44dp",
        layout_height = "44dp",
        layout_marginLeft = "8dp",
        BackgroundTintList = ColorStateList.valueOf(ColorPrimary),
        icon = res.drawable("ic_send"),
        iconTint = ColorStateList.valueOf(ColorOnPrimary),
        RippleColor = ColorStateList.valueOf(ColorRipple),
        cornerRadius = "22dp",
      },
      {
        MaterialButton,
        id = "btnStop",
        styleAttr = "?attr/materialIconButtonStyle",
        layout_width = "44dp",
        layout_height = "44dp",
        layout_marginLeft = "8dp",
        visibility = 8,
        BackgroundTintList = ColorStateList.valueOf(ColorSurface),
        icon = res.drawable("ic_stop"),
        iconTint = ColorStateList.valueOf(ColorError),
        strokeWidth = "1dp",
        strokeColor = ColorOutline,
        cornerRadius = "22dp",
      },
    },
    {
      LinearLayout,
      id = "loadingBar",
      layout_width = "match",
      layout_height = "wrap",
      orientation = "horizontal",
      gravity = "center_vertical",
      paddingTop = "4dp",
      visibility = 8,
      {
        ProgressBar,
        layout_width = "14dp",
        layout_height = "14dp",
        indeterminate = true,
        indeterminateTintList = ColorStateList.valueOf(ColorPrimary),
      },
      {
        MaterialTextView,
        text = res.string.ai_generating,
        textSize = "12sp",
        textColor = ColorText,
        layout_marginLeft = "6dp",
        layout_width = "0dp",
        layout_weight = 1,
      },
      {
        MaterialTextView,
        id = "ctxUsage",
        text = "",
        textSize = "11sp",
        textColor = ColorText,
        layout_marginLeft = "8dp",
      },
    },
  },
}