import "android.widget.*"
import "android.widget.ScrollView"
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.divider.MaterialDivider"
local View = luajava.bindClass "android.view.View"
local GradientDrawable = luajava.bindClass "android.graphics.drawable.GradientDrawable"
local themeUtil = this.themeUtil
local primaryColor = themeUtil.getColorPrimary()
local onSurfaceColor = themeUtil.getColorOnSurface()
local onSurfaceVarColor = themeUtil.getColorOnSurfaceVariant()
local outlineColor = themeUtil.getColorOutlineVariant()
local rippleRes = activity.obtainStyledAttributes({ android.R.attr.selectableItemBackground }).getResourceId(0, 0)

-- MD3 分组标题
local sectionTitle = function(text)
    return {
        MaterialTextView,
        paddingLeft = "16dp",
        paddingRight = "16dp",
        paddingBottom = "4dp",
        paddingTop = "16dp",
        text = text,
        textSize = "14sp",
        textStyle = "bold",
        letterSpacing = 0.02,
        textColor = primaryColor,
    }
end

-- MD3 设置项（带副标题和右侧圆形色块）
local colorItem = function(name, subtitle)
    return {
        LinearLayout,
        layout_width = "match",
        layout_height = "wrap",
        tag = name,
        id = name .. "Item",
        clickable = true,
        focusable = true,
        backgroundResource = rippleRes,
        gravity = "center_vertical",
        paddingLeft = "16dp",
        paddingRight = "16dp",
        paddingTop = "12dp",
        paddingBottom = "12dp",
        {
            LinearLayout,
            orientation = "vertical",
            layout_width = "0dp",
            layout_weight = 1,
            {
                MaterialTextView,
                textSize = "16sp",
                text = name,
                textColor = onSurfaceColor,
            },
            {
                MaterialTextView,
                textSize = "12sp",
                text = subtitle or "",
                textColor = onSurfaceVarColor,
                Visibility = subtitle and 0 or 8,
            },
        },
        {
            View,
            id = name .. "Circle",
            layout_width = "32dp",
            layout_height = "32dp",
            layout_marginLeft = "12dp",
        },
    }
end

-- MD3 设置项（纯文字，带副标题）
local settingItem = function(id, title, subtitle)
    return {
        LinearLayout,
        layout_width = "match",
        layout_height = "wrap",
        id = id,
        clickable = true,
        focusable = true,
        backgroundResource = rippleRes,
        gravity = "center_vertical",
        paddingLeft = "16dp",
        paddingRight = "16dp",
        paddingTop = "14dp",
        paddingBottom = "14dp",
        {
            LinearLayout,
            orientation = "vertical",
            layout_width = "match",
            {
                MaterialTextView,
                textSize = "16sp",
                text = title,
                textColor = onSurfaceColor,
            },
            {
                MaterialTextView,
                textSize = "12sp",
                text = subtitle or "",
                id = id .. "Desc",
                textColor = onSurfaceVarColor,
                Visibility = subtitle and 0 or 8,
            },
        },
    }
end

local divider = function()
    return {
        MaterialDivider,
        layout_marginLeft = "16dp",
        layout_marginRight = "16dp",
        layout_marginTop = "4dp",
        layout_marginBottom = "4dp",
    }
end

return {
    ScrollView,
    layout_width = "match",
    layout_height = "match",
    {
        LinearLayout,
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        paddingBottom = "24dp",

        -- ── 编辑器 ──
        sectionTitle(res.string.editor_highlight_color),
        colorItem("BaseWord", "标识符"),
        colorItem("KeyWord", "关键字"),
        colorItem("String", "字符串"),
        colorItem("UserWord", "用户词"),
        colorItem("Comment", "注释"),
        colorItem("Global", "全局变量"),
        colorItem("Local", "局部变量"),
        colorItem("Upval", "上值"),

        divider(),

        -- ── 调试 ──
        sectionTitle(res.string.debug),
        settingItem("CustomApp", res.string.debug_app, "设置外部调试应用包名"),

        divider(),

        -- ── 关于 ──
        sectionTitle(res.string.about),
        settingItem("AboutItem", "NeLuaJ+", this.getVersionName("unknown")),
    },
}
