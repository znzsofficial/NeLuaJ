local ColorStateList = bindClass "android.content.res.ColorStateList"
local MaterialTextView = bindClass "com.google.android.material.textview.MaterialTextView"
local MaterialButton = bindClass "com.google.android.material.button.MaterialButton"
local LinearLayout = bindClass "android.widget.LinearLayout"
local ScrollView = bindClass "android.widget.ScrollView"
local HorizontalScrollView = bindClass "android.widget.HorizontalScrollView"

local ColorUtil = this.themeUtil
local ColorPrimary = ColorUtil.primary.main
local ColorOnPrimary = ColorUtil.primary.on
local ColorPrimaryContainer = ColorUtil.primary.container
local ColorOnPrimaryContainer = ColorUtil.primary.onContainer
local ColorSurfaceContainerLow = ColorUtil.surface.containerLow
local ColorOnSurface = ColorUtil.surface.on
local ColorText = ColorUtil.surface.onVariant
local ColorErrorContainer = ColorUtil.error.container
local ColorOnErrorContainer = ColorUtil.error.onContainer

local res = res

return {
  LinearLayout,
  layout_width = "match",
  layout_height = "match",
  orientation = "vertical",
  -- 作用域筛选 + 新建
  {
    HorizontalScrollView,
    layout_width = "match",
    layout_height = "wrap",
    horizontalScrollBarEnabled = false,
    clipToPadding = false,
    paddingTop = "8dp",
    paddingBottom = "4dp",
    {
      LinearLayout,
      layout_width = "wrap",
      layout_height = "wrap",
      orientation = "horizontal",
      gravity = "center_vertical",
      paddingLeft = "12dp",
      paddingRight = "12dp",
      {
        MaterialButton,
        id = "chipCurrent",
        textSize = "12sp",
        layout_width = "wrap",
        layout_height = "32dp",
        cornerRadius = "16dp",
        layout_marginRight = "8dp",
      },
      {
        MaterialButton,
        id = "chipAll",
        textSize = "12sp",
        layout_width = "wrap",
        layout_height = "32dp",
        cornerRadius = "16dp",
        layout_marginRight = "8dp",
      },
      {
        MaterialButton,
        id = "btnNewConv",
        text = res.string.ai_new_conv_btn,
        textSize = "12sp",
        layout_width = "wrap",
        layout_height = "32dp",
        cornerRadius = "16dp",
        icon = res.drawable("add"),
        BackgroundTintList = ColorStateList.valueOf(ColorPrimary),
        textColor = ColorOnPrimary,
        iconTint = ColorStateList.valueOf(ColorOnPrimary),
        contentDescription = res.string.ai_new_conv_btn,
      },
    },
  },
  -- 会话列表
  {
    ScrollView,
    layout_width = "match",
    layout_height = "0dp",
    layout_weight = 1,
    fillViewport = true,
    {
      LinearLayout,
      id = "centerList",
      layout_width = "match",
      layout_height = "wrap",
      orientation = "vertical",
      padding = "12dp",
      paddingTop = "4dp",
    },
  },
}
