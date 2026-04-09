import "android.widget.HorizontalScrollView"
import "android.widget.LinearLayout"
import "android.widget.ListView"
import "androidx.appcompat.widget.AppCompatSpinner"
import "com.google.android.material.card.MaterialCardView"
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.divider.MaterialDivider"
import "vinx.material.textfield.MaterialTextField"
import "android.graphics.drawable.GradientDrawable"
import "android.util.TypedValue"
local ColorUtil = this.themeUtil
local getDp = lambda i : TypedValue.applyDimension(1, i, activity.getResources().getDisplayMetrics())

local surfaceColorVar = ColorUtil.ColorSurfaceVariant
local primaryColor = ColorUtil.getColorPrimary()

local function chipCard(id, label)
  return {
    MaterialCardView,
    layout_height = "36dp",
    layout_width = "wrap",
    layout_marginLeft = "4dp",
    layout_marginRight = "4dp",
    layout_gravity = "center",
    radius = "18dp",
    strokeWidth = "1dp",
    strokeColor = ColorUtil.getColorOutline(),
    CardElevation = "0dp",
    id = id,
    {
      MaterialTextView,
      text = label,
      layout_gravity = "center",
      paddingLeft = "14dp",
      paddingRight = "14dp",
      textSize = "13sp",
    },
  }
end

return {
  LinearLayout,
  id = "ll",
  orientation = "vertical",
  layout_width = "match",
  layout_height = "match",
  {
    HorizontalScrollView,
    layout_marginTop = "6dp",
    layout_marginBottom = "2dp",
    layout_height = "48dp",
    horizontalScrollBarEnabled = false,
    paddingLeft = "8dp",
    paddingRight = "8dp",
    {
      LinearLayout,
      layout_height = "match",
      orientation = "horizontal",
      gravity = "center",
      chipCard("aa", "继承"),
      chipCard("bb", "构造"),
      chipCard("cc", "方法"),
      chipCard("dd", "事件"),
      chipCard("ee", "字段"),
      chipCard("ff", "Setter"),
      chipCard("gg", "Getter"),
      chipCard("hh", "R资源"),
    },
  },
  {
    MaterialDivider,
    layout_width = "fill",
    layout_height = "1dp",
  },
  {
    LinearLayout,
    orientation = "horizontal",
    layout_width = "match",
    layout_height = "wrap",
    gravity = "center_vertical",
    {
      MaterialTextField,
      layout_marginLeft = "12dp",
      layout_marginRight = "8dp",
      layout_marginTop = "8dp",
      layout_marginBottom = "4dp",
      layout_height = "wrap",
      layout_width = "0dp",
      layout_weight = 1,
      textSize = "12sp",
      singleLine = true,
      TintColor = primaryColor,
      style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
      id = "ed",
    },
    {
      AppCompatSpinner,
      layout_marginTop = "8dp",
      layout_marginRight = "12dp",
      Visibility = 8,
      layout_width = "0dp",
      layout_weight = 1,
      id = "spc",
      popupBackgroundDrawable = GradientDrawable().setShape(0).setColor(surfaceColorVar).setCornerRadius(getDp(12)),
    },
    {
      AppCompatSpinner,
      layout_marginTop = "8dp",
      layout_marginRight = "12dp",
      Visibility = 8,
      layout_width = "0dp",
      layout_weight = 1,
      id = "sph",
      popupBackgroundDrawable = GradientDrawable().setShape(0).setColor(surfaceColorVar).setCornerRadius(getDp(12)),
    },
  },
  {
    ListView,
    FastScrollEnabled = true,
    id = "li",
    layout_width = "match",
    DividerHeight = 0,
    paddingTop = "4dp",
    paddingBottom = "4dp",
    clipToPadding = false,
  },
}
