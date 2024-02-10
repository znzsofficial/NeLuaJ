import "android.widget.LinearLayout"
import "com.google.android.material.textview.MaterialTextView";
import "vinx.material.textfield.MaterialTextField"
import "res"
local ColorUtil = this.globalData.ColorUtil

return {
  LinearLayout,
  orientation="vertical",
  layout_width="match",
  layout_height="match",
  paddingLeft="20dp",
  paddingTop="20dp",
  paddingRight="20dp",
  Focusable=true,
  FocusableInTouchMode=true,
  {
    MaterialTextView,
    layout_width="fill",
    layout_height="wrap",
    text=res.string.build_problem,
  },
  {
    MaterialTextField,
    layout_width="fill",
    layout_height="wrap",
    textSize="12dp",
    hint="工程目录",
    TintColor=ColorUtil.getColorPrimary(),
    style=MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
    singleLine=true,
    id="pro_path",
  },
}
