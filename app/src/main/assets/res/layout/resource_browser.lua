import "android.widget.LinearLayout"
import "android.widget.ListView"
import "android.widget.HorizontalScrollView"
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.card.MaterialCardView"
import "com.google.android.material.chip.ChipGroup"
import "android.widget.ImageView"
import "vinx.material.textfield.MaterialTextField"

local ColorUtil = this.themeUtil

return {
  LinearLayout,
  orientation = "vertical",
  layout_width = "match",
  layout_height = "match",
  -- R 类来源选择（横向滚动 ChipGroup）
  {
    HorizontalScrollView,
    layout_width = "match",
    layout_height = "wrap",
    HorizontalScrollBarEnabled = false,
    {
      ChipGroup,
      id = "sourceChipGroup",
      layout_width = "wrap",
      layout_height = "wrap",
      SingleSelection = true,
      SelectionRequired = true,
      paddingLeft = "12dp",
      paddingRight = "12dp",
      paddingTop = "8dp",
      paddingBottom = "4dp",
    },
  },
  -- 子类选择（横向滚动 ChipGroup）
  {
    HorizontalScrollView,
    layout_width = "match",
    layout_height = "wrap",
    HorizontalScrollBarEnabled = false,
    {
      ChipGroup,
      id = "subClassChipGroup",
      layout_width = "wrap",
      layout_height = "wrap",
      SingleSelection = true,
      SelectionRequired = true,
      paddingLeft = "12dp",
      paddingRight = "12dp",
      paddingBottom = "4dp",
    },
  },
  -- 搜索框
  {
    MaterialTextField,
    id = "searchEdit",
    layout_marginLeft = "12dp",
    layout_marginRight = "12dp",
    layout_marginBottom = "4dp",
    layout_height = "wrap",
    layout_width = "match",
    textSize = "12sp",
    singleLine = true,
    TintColor = ColorUtil.getColorPrimary(),
    style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox_Dense,
  },
  -- 资源列表
  {
    ListView,
    id = "resourceList",
    layout_width = "match",
    FastScrollEnabled = true,
    DividerHeight = 0,
    paddingTop = "4dp",
    paddingBottom = "4dp",
    clipToPadding = false,
  },
}
