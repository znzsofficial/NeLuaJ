import "android.widget.*"
import "android.widget.ScrollView"
import "androidx.appcompat.widget.AppCompatImageView"
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.divider.MaterialDivider"
import "com.google.android.material.card.MaterialCardView"
import "com.google.android.material.materialswitch.MaterialSwitch"
local View = luajava.bindClass "android.view.View"
local themeUtil = this.themeUtil
local primaryColor = themeUtil.getColorPrimary()
local onSurfaceColor = themeUtil.getColorOnSurface()
local onSurfaceVarColor = themeUtil.getColorOnSurfaceVariant()
local surfaceColor = themeUtil.getColorSurface()
local surfaceContainerColor = themeUtil.getColorSurfaceContainer()
local outlineColor = themeUtil.getColorOutlineVariant()
local rippleRes = activity.obtainStyledAttributes({ android.R.attr.selectableItemBackground }).getResourceId(0, 0)

local function tintedIcon(name)
    local d = nil
    pcall(function()
        d = res.drawable(name, primaryColor)
    end)
    if d == nil then
        pcall(function() d = res.drawable(name, onSurfaceVarColor) end)
    end
    return d
end

local function leadingIcon(iconName)
    if not iconName then return nil end
    return {
        AppCompatImageView,
        layout_width = "24dp",
        layout_height = "24dp",
        layout_marginRight = "16dp",
        src = tintedIcon(iconName),
    }
end

-- MD3 分组标题
local sectionTitle = function(text, iconName)
    local row = {
        LinearLayout,
        layout_width = "match",
        layout_height = "wrap",
        gravity = "center_vertical",
        paddingLeft = "16dp",
        paddingRight = "16dp",
        paddingBottom = "4dp",
        paddingTop = "16dp",
    }
    if iconName then
        row[#row + 1] = {
            AppCompatImageView,
            layout_width = "18dp",
            layout_height = "18dp",
            layout_marginRight = "8dp",
            src = tintedIcon(iconName),
        }
    end
    row[#row + 1] = {
        MaterialTextView,
        text = text,
        textSize = "14sp",
        textStyle = "bold",
        letterSpacing = 0.02,
        textColor = primaryColor,
    }
    return row
end

-- MD3 设置项（带副标题和右侧圆形色块）
local colorItem = function(name, subtitle, iconName)
    local row = {
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
    }
    local lead = leadingIcon(iconName)
    if lead then row[#row + 1] = lead end
    row[#row + 1] = {
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
    }
    row[#row + 1] = {
        View,
        id = name .. "Circle",
        layout_width = "32dp",
        layout_height = "32dp",
        layout_marginLeft = "12dp",
    }
    return row
end

-- MD3 设置项（纯文字，带副标题）
local settingItem = function(id, title, subtitle, iconName)
    local row = {
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
    }
    local lead = leadingIcon(iconName)
    if lead then row[#row + 1] = lead end
    row[#row + 1] = {
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
    }
    return row
end

-- MD3 开关设置项
local switchItem = function(id, title, subtitle, iconName)
    local row = {
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
    }
    local lead = leadingIcon(iconName)
    if lead then row[#row + 1] = lead end
    row[#row + 1] = {
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
    }
    row[#row + 1] = {
        MaterialSwitch,
        id = id .. "Switch",
        layout_marginLeft = "12dp",
        clickable = false,
        focusable = false,
    }
    return row
end

local divider = function()
    return {
        MaterialDivider,
        layout_marginLeft = "56dp",
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
            AppCompatImageView,
            layout_width = "24dp",
            layout_height = "24dp",
            layout_marginRight = "16dp",
            src = tintedIcon("dashboard"),
        },
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
        sectionTitle("外观", "dashboard"),
        card(
            themeItem(),
            divider(),
            switchItem("TabletModeItem", res.string.tablet_mode, res.string.tablet_mode_desc, "layout_helper")
        ),

        -- ── 编辑器 ──
        sectionTitle(res.string.editor, "code"),
        card(
            settingItem("FunctionBarItem", res.string.function_bar, res.string.function_bar_desc, "dashboard"),
            divider(),
            settingItem("SymbolBarItem", res.string.symbol_bar, res.string.symbol_bar_desc, "format"),
            divider(),
            switchItem("SymbolBarTwoRowsItem", res.string.symbol_bar_two_rows, res.string.symbol_bar_two_rows_desc, "format"),
            divider(),
            settingItem("SymbolBarTextSizeItem", res.string.symbol_bar_text_size, res.string.symbol_bar_text_size_desc, "format"),
            divider(),
            settingItem("FunctionTabTextSizeItem", res.string.function_tab_text_size, res.string.function_tab_text_size_desc, "format"),
            divider(),
            switchItem("EditorMagnifierItem", res.string.editor_magnifier, res.string.editor_magnifier_desc, "search"),
            divider(),
            switchItem("CodeMinimapItem", res.string.code_minimap, res.string.code_minimap_desc, "article"),
            divider(),
            settingItem("MinimapCodeAlphaItem", res.string.minimap_code_alpha, res.string.minimap_code_alpha_desc, "article")
        ),

        sectionTitle(res.string.editor_highlight_color, "format"),
        card(
            colorItem("BaseWord", "标识符", "code"),
            divider(),
            colorItem("KeyWord", "关键字", "code"),
            divider(),
            colorItem("String", "字符串", "article"),
            divider(),
            colorItem("UserWord", "用户词", "code"),
            divider(),
            colorItem("Comment", "注释", "format"),
            divider(),
            colorItem("Global", "全局变量", "code"),
            divider(),
            colorItem("Local", "局部变量", "code"),
            divider(),
            colorItem("Upval", "上值", "code"),
            divider(),
            colorItem("MinimapMask", res.string.minimap_mask_desc, "article"),
            divider(),
            colorItem("MinimapBg", res.string.minimap_bg_desc, "article")
        ),

        -- ── 调试 ──
        sectionTitle(res.string.debug, "bug_report"),
        card(
            settingItem("RunWindowModeItem", res.string.run_window_mode, res.string.run_window_mode_desc, "dashboard"),
            divider(),
            settingItem("CustomApp", res.string.debug_app, "设置外部调试应用包名", "android_studio")
        ),

        -- ── 关于 ──
        sectionTitle(res.string.about, "info"),
        card(
            settingItem("AboutItem", "NeLuaJ+", this.getVersionName("unknown"), "info"),
            divider(),
            settingItem("CopyrightItem", res.string.copyright_title, res.string.copyright, "menu_book")
        ),
    },
}
