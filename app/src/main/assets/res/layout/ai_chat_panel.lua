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
local ColorPrimary = ColorUtil.primary.main
local ColorOnPrimary = ColorUtil.primary.on
local ColorPrimaryContainer = ColorUtil.primary.container
local ColorOnPrimaryContainer = ColorUtil.primary.onContainer
local ColorSurface = ColorUtil.surface.container
local ColorSurfaceContainerLow = ColorUtil.surface.containerLow
local ColorSurfaceContainerHigh = ColorUtil.surface.containerHigh
local ColorOnSurface = ColorUtil.surface.on
local ColorText = ColorUtil.surface.onVariant
local ColorOutline = ColorUtil.outline.variant
local ColorBg = ColorUtil.surface.main
local ColorError = ColorUtil.error.main
local ColorErrorContainer = ColorUtil.error.container
local ColorOnErrorContainer = ColorUtil.error.onContainer

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
    padding = "10dp",
    paddingLeft = "16dp",
    paddingRight = "8dp",
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "0dp",
      layout_weight = 1,
      layout_height = "wrap",
      layout_marginRight = "6dp",
      {
        LinearLayout,
        orientation = "horizontal",
        gravity = "center_vertical",
        layout_width = "wrap",
        layout_height = "wrap",
        {
          MaterialTextView,
          id = "aiTitle",
          text = res.string.ai_chat,
          textSize = "17sp", textStyle = "bold", textColor = ColorOnSurface,
          maxLines = 1, ellipsize = "end",
        },
        {
          MaterialTextView,
          text = "  ⌄",
          textSize = "13sp", textStyle = "bold", textColor = ColorText,
        },
      },
      {
        MaterialTextView,
        id = "aiProject",
        text = res.string.ai_project_unknown,
        textSize = "11sp", textColor = ColorText,
        maxLines = 1, ellipsize = "end",
        layout_marginTop = "1dp",
      },
    },
    {
      MaterialCardView,
      id = "modelChip",
      contentDescription = res.string.ai_cd_switch_model,
      layout_width = "wrap",
      layout_height = "wrap",
      radius = "8dp", CardElevation = 0,
      strokeWidth = "1dp", strokeColor = ColorOutline,
      CardBackgroundColor = ColorSurfaceContainerLow,
      layout_marginRight = "6dp",
      {
        MaterialTextView,
        id = "modelLabel", text = res.string.ai_add_model,
        textSize = "11sp", textColor = ColorPrimary,
        padding = "6dp", paddingLeft = "10dp", paddingRight = "10dp",
        maxLines = 1, ellipsize = "end", maxWidth = "104dp",
      },
    },
    {
      MaterialButton,
      id = "btnSettings",
      contentDescription = res.string.ai_cd_settings,
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
      contentDescription = res.string.ai_cd_new_conv,
      styleAttr = "?attr/materialIconButtonStyle",
      layout_width = "40dp", layout_height = "40dp",
      BackgroundTintList = ColorStateList.valueOf(0),
      icon = res.drawable("add"),
      iconTint = ColorStateList.valueOf(ColorText),
      RippleColor = ColorStateList.valueOf(ColorRipple),
    },
  },
  { MaterialDivider, dividerColor = ColorOutline },
  -- 任务计划置顶条（有计划时显示，点击展开完整清单）
  {
    MaterialCardView,
    id = "planStrip",
    visibility = 8,
    radius = "10dp",
    CardElevation = 0,
    CardBackgroundColor = ColorSurface,
    clickable = true,
    focusable = true,
    layout_marginLeft = "12dp",
    layout_marginRight = "12dp",
    layout_marginTop = "6dp",
    {
      LinearLayout,
      orientation = "horizontal",
      gravity = "center_vertical",
      padding = "10dp",
      paddingLeft = "12dp",
      paddingRight = "12dp",
      {
        MaterialTextView,
        id = "planLabel",
        text = res.string.ai_todo,
        textSize = "12sp", textStyle = "bold", textColor = ColorPrimary,
      },
      {
        MaterialTextView,
        id = "planProgress",
        text = "",
        textSize = "12sp", textColor = ColorText,
        layout_marginLeft = "8dp",
        layout_width = "0dp", layout_weight = 1,
      },
      {
        MaterialTextView,
        text = "▾",
        textSize = "12sp", textColor = ColorText,
      },
    },
  },
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
        radius = "24dp",
        CardElevation = 0,
        strokeWidth = "0dp",
        CardBackgroundColor = ColorSurfaceContainerHigh,
        layout_width = "0dp",
        layout_weight = 1,
        layout_height = "wrap",
        {
          EditText,
          id = "msgInput",
          layout_width = "match",
          layout_height = "wrap",
          minHeight = "46dp",
          hint = res.string.ai_input_hint,
          textSize = "14sp",
          textColor = ColorOnSurface,
          hintTextColor = ColorText,
          background = 0,
          padding = "12dp",
          paddingLeft = "16dp",
          paddingRight = "16dp",
          singleLine = false,
          maxLines = 4,
          inputType = 0x00002001,
        },
      },
      {
        MaterialButton,
        id = "btnCommands",
        contentDescription = res.string.ai_cd_commands,
        styleAttr = "?attr/materialIconButtonStyle",
        layout_width = "46dp",
        layout_height = "46dp",
        layout_marginLeft = "6dp",
        BackgroundTintList = ColorStateList.valueOf(0),
        icon = res.drawable("ic_command"),
        iconTint = ColorStateList.valueOf(ColorText),
        RippleColor = ColorStateList.valueOf(ColorRipple),
      },
      {
        MaterialButton,
        id = "btnSend",
        contentDescription = res.string.ai_cd_send,
        styleAttr = "?attr/materialIconButtonStyle",
        layout_width = "46dp",
        layout_height = "46dp",
        layout_marginLeft = "6dp",
        BackgroundTintList = ColorStateList.valueOf(ColorPrimary),
        icon = res.drawable("ic_send"),
        iconTint = ColorStateList.valueOf(ColorOnPrimary),
        RippleColor = ColorStateList.valueOf(ColorRipple),
        cornerRadius = "23dp",
      },
      {
        MaterialButton,
        id = "btnStop",
        contentDescription = res.string.ai_cd_stop,
        styleAttr = "?attr/materialIconButtonStyle",
        layout_width = "46dp",
        layout_height = "46dp",
        layout_marginLeft = "6dp",
        visibility = 8,
        BackgroundTintList = ColorStateList.valueOf(ColorErrorContainer),
        icon = res.drawable("ic_stop"),
        iconTint = ColorStateList.valueOf(ColorOnErrorContainer),
        strokeWidth = "0dp",
        cornerRadius = "23dp",
      },
    },
    {
      LinearLayout,
      id = "loadingBar",
      layout_width = "match",
      layout_height = "wrap",
      orientation = "horizontal",
      gravity = "center_vertical",
      paddingTop = "6dp",
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
        id = "loadingText",
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
