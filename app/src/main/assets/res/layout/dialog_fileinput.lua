import "android.widget.LinearLayout"
import "vinx.material.textfield.MaterialTextField"

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
    MaterialTextField,
    layout_width="fill",
    layout_height="wrap",
    textSize="12dp",
    TintColor=ColorUtil.getColorPrimary(),
    style=MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
    singleLine=true,
    id="file_name",
  },
}
