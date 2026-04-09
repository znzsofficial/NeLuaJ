import "android.widget.LinearLayout"
import "android.widget.ListView"
import "vinx.material.textfield.MaterialTextField"
import "com.google.android.material.divider.MaterialDivider"
local ColorUtil = this.themeUtil
return {
  LinearLayout,
  layout_height = "match",
  layout_width = "match",
  id = "ll",
  orientation = "vertical",
  {
    MaterialTextField,
    layout_width = "fill",
    layout_height = "wrap",
    textSize = "12sp",
    singleLine = true,
    layout_marginLeft = "16dp",
    layout_marginRight = "16dp",
    layout_marginTop = "8dp",
    layout_marginBottom = "4dp",
    TintColor = ColorUtil.getColorPrimary(),
    style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
    id = "edit",
  },
  {
    MaterialDivider,
    layout_width = "fill",
    layout_height = "1dp",
  },
  {
    ListView,
    DividerHeight = 0,
    layout_width = "match",
    id = "clist",
    FastScrollEnabled = true,
    paddingTop = "4dp",
    paddingBottom = "4dp",
    clipToPadding = false,
  },
}
