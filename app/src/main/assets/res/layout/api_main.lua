import "android.widget.LinearLayout"
import "android.widget.ListView"
import "vinx.material.textfield.MaterialTextField"
local ColorUtil = this.globalData.ColorUtil
return {
  LinearLayout;
  layout_heigh="-1";
  id="ll";
  orientation="vertical";
  {
    MaterialTextField,
    layout_width="fill",
    layout_height="wrap",
    textSize="12dp",
    singleLine=true,
    layout_margin="16dp",
    TintColor=ColorUtil.getColorPrimary(),
    style=MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
    id="edit",
  },
  {
    ListView;
    DividerHeight=1;
    layout_width="-1";
    id="clist";
    FastScrollEnabled=true;
  };
};
