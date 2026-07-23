import "android.widget.LinearLayout"
import "vinx.material.textfield.MaterialTextField"
local ColorUtil = this.themeUtil
local MDC_R = luajava.bindClass "com.google.android.material.R"
return {
  LinearLayout,
  orientation = "vertical",
  layout_width = "match",
  layout_height = "wrap",
  paddingLeft = "20dp",
  paddingTop = "12dp",
  paddingRight = "20dp",
  paddingBottom = "4dp",
  Focusable = true,
  FocusableInTouchMode = true,
  {
    MaterialTextField,
    id = "file_name",
    hint = res.string.file_name,
    layout_width = "match",
    layout_height = "wrap",
    textSize = "14sp",
    TintColor = ColorUtil.getColorPrimary(),
    style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
    boxBackgroundMode = 2, -- BOX_BACKGROUND_OUTLINE
    singleLine = true,
  },
}
