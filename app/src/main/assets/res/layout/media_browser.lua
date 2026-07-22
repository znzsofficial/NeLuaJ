import "android.widget.LinearLayout"
import "android.widget.ListView"
import "android.widget.HorizontalScrollView"
import "android.widget.FrameLayout"
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.chip.ChipGroup"
import "com.google.android.material.chip.Chip"
import "com.google.android.material.button.MaterialButton"
import "vinx.material.textfield.MaterialTextField"

local ColorUtil = this.themeUtil
local primary = ColorUtil.getColorPrimary()
local onVar = ColorUtil.getColorOnSurfaceVariant()

local function rootChip(id, text)
  return {
    Chip,
    id = id,
    text = text,
    Checkable = true,
    CheckedIconEnabled = true,
    layout_marginEnd = "6dp",
  }
end

return {
  LinearLayout,
  orientation = "vertical",
  layout_width = "match",
  layout_height = "match",
  BackgroundColor = "?attr/colorSurface",

  {
    HorizontalScrollView,
    layout_width = "match",
    layout_height = "wrap",
    horizontalScrollBarEnabled = false,
    {
      ChipGroup,
      id = "rootChips",
      layout_width = "wrap",
      layout_height = "wrap",
      paddingLeft = "12dp",
      paddingRight = "12dp",
      paddingTop = "10dp",
      paddingBottom = "4dp",
      singleSelection = true,
      selectionRequired = true,
      rootChip("chip_all", res.string.media_root_all or "全部"),
      rootChip("chip_crash", res.string.media_root_crash or "崩溃日志"),
      rootChip("chip_backups", res.string.media_root_backups or "代码备份"),
      rootChip("chip_zip", res.string.media_root_zip or "工程 ZIP"),
    },
  },

  {
    LinearLayout,
    orientation = "horizontal",
    layout_width = "match",
    layout_height = "wrap",
    gravity = "center_vertical",
    paddingLeft = "12dp",
    paddingRight = "8dp",
    paddingBottom = "4dp",
    {
      MaterialTextView,
      id = "pathText",
      layout_width = "0dp",
      layout_weight = 1,
      layout_height = "wrap",
      textSize = "12sp",
      textColor = onVar,
      maxLines = 2,
      text = "…",
    },
    {
      MaterialButton,
      id = "btnUp",
      text = res.string.media_up or "上级",
      layout_width = "wrap",
      layout_height = "wrap",
      minHeight = "40dp",
      textSize = "12sp",
      styleAttr = "?attr/borderlessButtonStyle",
      textColor = primary,
    },
  },

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
    hint = res.string.media_search or "搜索文件名…",
    TintColor = primary,
    style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox_Dense,
  },

  {
    MaterialTextView,
    id = "metaText",
    layout_width = "match",
    layout_height = "wrap",
    paddingLeft = "16dp",
    paddingRight = "16dp",
    paddingBottom = "4dp",
    textSize = "12sp",
    textColor = onVar,
    text = "",
  },

  {
    FrameLayout,
    layout_width = "match",
    layout_height = "0dp",
    layout_weight = 1,
    {
      LinearLayout,
      id = "emptyView",
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      layout_gravity = "center",
      gravity = "center",
      padding = "32dp",
      visibility = "gone",
      {
        MaterialTextView,
        id = "emptyTitle",
        text = res.string.media_empty or "目录为空",
        textSize = "16sp",
        textStyle = "bold",
        textColor = "?attr/colorOnSurface",
        gravity = "center",
      },
      {
        MaterialTextView,
        id = "emptyHint",
        text = res.string.media_empty_hint or "崩溃日志与保存备份会出现在这里",
        textSize = "13sp",
        textColor = onVar,
        gravity = "center",
        layout_marginTop = "8dp",
      },
    },
    {
      ListView,
      id = "fileList",
      layout_width = "match",
      layout_height = "match",
      FastScrollEnabled = true,
      DividerHeight = 0,
      paddingTop = "4dp",
      paddingBottom = "8dp",
      clipToPadding = false,
    },
  },
}
