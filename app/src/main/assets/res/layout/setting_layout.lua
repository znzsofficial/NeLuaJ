import "android.widget.*"
local View = luajava.bindClass "android.view.View"
local themeUtil = this.globalData.ColorUtil
local rippleRes = activity.obtainStyledAttributes({ android.R.attr.selectableItemBackground }).getResourceId(0, 0)

local colorItem = function(name)
    return {
        LinearLayout,
        layout_width = "match",
        layout_height = "wrap",
        tag = name,
        id = name .. "Item",
        clickable = true,
        focusable = true,
        backgroundResource = rippleRes,
        gravity = "center",
        padding = "16dp",
        {
            TextView,
            textSize = "20sp",
            text = name,
        },
        {
            View,
            layout_height = "match",
            layout_weight = 1,
        },
        {
            View,
            id = name .. "Circle",
            layout_width = "36dp",
            layout_height = "36dp",
        }
    }
end

return {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
    {
        TextView,
        paddingLeft = "16dp",
        paddingRight = "16dp",
        paddingBottom = "8dp",
        paddingTop = "8dp",
        text = res.string.editor_highlight_color,
        textSize = "16sp",
        textColor = themeUtil.getColorPrimary(),
    },
    colorItem("BaseWord"),
    colorItem("KeyWord"),
    colorItem("String"),
    colorItem("UserWord"),
}