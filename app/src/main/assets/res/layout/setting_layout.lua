import "android.widget.*"
import "android.widget.ScrollView"
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.divider.MaterialDivider"
import "com.google.android.material.card.MaterialCardView"
import "com.google.android.material.materialswitch.MaterialSwitch"
local View = luajava.bindClass "android.view.View"
local GradientDrawable = luajava.bindClass "android.graphics.drawable.GradientDrawable"
local themeUtil = this.themeUtil
local primaryColor = themeUtil.getColorPrimary()
local onSurfaceColor = themeUtil.getColorOnSurface()
local onSurfaceVarColor = themeUtil.getColorOnSurfaceVariant()
local surfaceColor = themeUtil.getColorSurface()
local surfaceContainerColor = themeUtil.getColorSurfaceContainer()
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

-- MD3 开关设置项
local switchItem = function(id, title, subtitle)
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
                text = title,
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
            MaterialSwitch,
            id = id .. "Switch",
            layout_marginLeft = "12dp",
            clickable = false,
            focusable = false,
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

local card = function(...)
    return {
        MaterialCardView,
        layout_width = "match",
        layout_height = "wrap",
        layout_marginLeft = "16dp",
        layout_marginRight = "16dp",
        layout_marginTop = "8dp",
        layout_marginBottom = "8dp",
        radius = "20dp",
        CardElevation = 0,
        strokeWidth = "1dp",
        strokeColor = outlineColor,
        CardBackgroundColor = surfaceContainerColor,
        {
            LinearLayout,
            orientation = "vertical",
            layout_width = "match",
            layout_height = "wrap",
            ...
        }
    }
end

local themeItem = function()
    return {
        LinearLayout,
        layout_width = "match",
        layout_height = "wrap",
        id = "ThemeColorItem",
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
            layout_width = "0dp",
            layout_weight = 1,
            {
                MaterialTextView,
                textSize = "16sp",
                text = "主题色",
                textColor = onSurfaceColor,
            },
            {
                MaterialTextView,
                textSize = "12sp",
                id = "ThemeColorDesc",
                text = "跟随系统动态取色",
                textColor = onSurfaceVarColor,
            },
        },
        {
            View,
            id = "ThemeColorCircle",
            layout_width = "32dp",
            layout_height = "32dp",
            layout_marginLeft = "12dp",
        },
    }
end

return {
    ScrollView,
    layout_width = "match",
    layout_height = "match",
    backgroundColor = surfaceColor,
    {
        LinearLayout,
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        paddingTop = "8dp",
        paddingBottom = "32dp",

        -- ── 外观 ──
        sectionTitle("外观"),
        card(
            themeItem()
        ),

        -- ── 编辑器 ──
        sectionTitle(res.string.editor),
        card(
            settingItem("SymbolBarItem", res.string.symbol_bar, res.string.symbol_bar_desc),
            divider(),
            switchItem("SymbolBarTwoRowsItem", res.string.symbol_bar_two_rows, res.string.symbol_bar_two_rows_desc),
            divider(),
            switchItem("EditorMagnifierItem", res.string.editor_magnifier, res.string.editor_magnifier_desc)
        ),

        sectionTitle(res.string.editor_highlight_color),
        card(
            colorItem("BaseWord", "标识符"),
            divider(),
            colorItem("KeyWord", "关键字"),
            divider(),
            colorItem("String", "字符串"),
            divider(),
            colorItem("UserWord", "用户词"),
            divider(),
            colorItem("Comment", "注释"),
            divider(),
            colorItem("Global", "全局变量"),
            divider(),
            colorItem("Local", "局部变量"),
            divider(),
            colorItem("Upval", "上值")
        ),

        -- ── 调试 ──
        sectionTitle(res.string.debug),
        card(
            settingItem("CustomApp", res.string.debug_app, "设置外部调试应用包名")
        ),

        -- ── 关于 ──
        sectionTitle(res.string.about),
        card(
            settingItem("AboutItem", "NeLuaJ+", this.getVersionName("unknown"))
        ),
    },
}
