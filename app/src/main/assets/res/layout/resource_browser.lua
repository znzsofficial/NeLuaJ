import "android.widget.LinearLayout"
import "android.widget.ListView"
import "androidx.appcompat.widget.AppCompatSpinner"
import "com.google.android.material.tabs.TabLayout"
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.card.MaterialCardView"
import "android.widget.ImageView"
import "vinx.material.textfield.MaterialTextField"
import "android.graphics.drawable.GradientDrawable"
import "android.util.TypedValue"

local ColorUtil = this.themeUtil
local getDp = lambda i : TypedValue.applyDimension(1, i, activity.getResources().getDisplayMetrics())
local surfaceColorVar = ColorUtil.ColorSurfaceVariant

return {
  LinearLayout,
  orientation = "vertical",
  layout_width = "match",
  layout_height = "match",
  {
    TabLayout,
    id = "sourceTab",
    layout_width = "match",
    layout_height = "wrap",
    TabMode = 0,
    Elevation = "0dp",
    BackgroundColor = ColorUtil.getColorBackground(),
  },
  {
    LinearLayout,
    orientation = "horizontal",
    layout_width = "match",
    layout_height = "wrap",
    gravity = "center_vertical",
    {
      MaterialTextField,
      id = "searchEdit",
      layout_marginLeft = "12dp",
      layout_marginRight = "8dp",
      layout_marginTop = "8dp",
      layout_marginBottom = "4dp",
      layout_height = "wrap",
      layout_width = "0dp",
      layout_weight = 1,
      textSize = "12sp",
      singleLine = true,
      TintColor = ColorUtil.getColorPrimary(),
      style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
    },
    {
      AppCompatSpinner,
      id = "subClassSpinner",
      layout_marginTop = "8dp",
      layout_marginRight = "12dp",
      layout_width = "0dp",
      layout_weight = 1,
      popupBackgroundDrawable = GradientDrawable().setShape(0).setColor(surfaceColorVar).setCornerRadius(getDp(12)),
    },
  },
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
