import "android.widget.*"
local View = luajava.bindClass "android.view.View"
local themeUtil = this.themeUtil
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
    colorItem("Comment"),
    colorItem("Global"),
    colorItem("Local"),
    colorItem("Upval"),
    {
        TextView,
        paddingLeft = "16dp",
        paddingRight = "16dp",
        paddingBottom = "8dp",
        paddingTop = "8dp",
        text = res.string.debug,
        textSize = "16sp",
        textColor = themeUtil.getColorPrimary(),
    },
    {
        LinearLayout,
        layout_width = "match",
        layout_height = "wrap",
        id = "CustomApp",
        clickable = true,
        focusable = true,
        backgroundResource = rippleRes,
        gravity = "center|start",
        padding = "16dp",
        {
            TextView,
            textSize = "20sp",
            text = res.string.debug_app,
        },
    }
}
