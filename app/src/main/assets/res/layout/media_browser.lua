import "android.widget.LinearLayout"
import "android.widget.HorizontalScrollView"
import "android.widget.FrameLayout"
import "android.widget.ListView"
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.chip.ChipGroup"
import "com.google.android.material.chip.Chip"
import "com.google.android.material.button.MaterialButton"
import "com.google.android.material.card.MaterialCardView"

local ColorUtil = this.themeUtil
local primary = ColorUtil.getColorPrimary()
local onVar = ColorUtil.getColorOnSurfaceVariant()
local surfaceLow = ColorUtil.getColorSurfaceContainerLow
  and ColorUtil.getColorSurfaceContainerLow()
  or ColorUtil.getColorBackground()

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
      rootChip("chip_all", res.string.media_root_all),
      rootChip("chip_crash", res.string.media_root_crash),
      rootChip("chip_backups", res.string.media_root_backups),
      rootChip("chip_zip", res.string.media_root_zip),
    },
  },

  {
    MaterialCardView,
    layout_width = "match",
    layout_height = "wrap",
    layout_marginLeft = "12dp",
    layout_marginRight = "12dp",
    layout_marginTop = "4dp",
    layout_marginBottom = "8dp",
    cardElevation = "0dp",
    radius = "12dp",
    cardBackgroundColor = surfaceLow,
    {
      LinearLayout,
      orientation = "horizontal",
      layout_width = "match",
      layout_height = "wrap",
      gravity = "center_vertical",
      paddingLeft = "12dp",
      paddingRight = "4dp",
      paddingTop = "8dp",
      paddingBottom = "8dp",
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
        text = res.string.media_up,
        layout_width = "wrap",
        layout_height = "wrap",
        minHeight = "36dp",
        textSize = "12sp",
        styleAttr = "?attr/borderlessButtonStyle",
        textColor = primary,
      },
      {
        MaterialButton,
        id = "btnRefresh",
        text = res.string.media_refresh,
        layout_width = "wrap",
        layout_height = "wrap",
        minHeight = "36dp",
        textSize = "12sp",
        styleAttr = "?attr/borderlessButtonStyle",
        textColor = primary,
      },
    },
  },

  {
    FrameLayout,
    layout_width = "match",
    layout_height = "0dp",
    layout_weight = 1,
    {
      ListView,
      id = "fileList",
      layout_width = "match",
      layout_height = "match",
      dividerHeight = "0dp",
      overScrollMode = 2,
      fastScrollEnabled = true,
    },
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
        text = res.string.media_empty,
        textSize = "16sp",
        textStyle = "bold",
        textColor = "?attr/colorOnSurface",
        gravity = "center",
      },
      {
        MaterialTextView,
        text = res.string.media_empty_hint,
        textSize = "13sp",
        textColor = onVar,
        gravity = "center",
        layout_marginTop = "8dp",
      },
    },
  },
}
