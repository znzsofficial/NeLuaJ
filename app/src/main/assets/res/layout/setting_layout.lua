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

-- MD3 颜色项：tag = SharedData 键；title 可选（默认显示 tag）
local colorItem = function(tag, title, subtitle, iconName)
    local row = {
        LinearLayout,
        layout_width = "match",
        layout_height = "wrap",
        tag = tag,
        id = tag .. "Item",
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
            text = title or tag,
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
        id = tag .. "Circle",
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
                text = res.string.theme_color,
                textColor = onSurfaceColor,
            },
            {
                MaterialTextView,
                textSize = "12sp",
                id = "ThemeColorDesc",
                text = res.string.theme_color_follow_system,
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
        sectionTitle(res.string.appearance, "dashboard"),
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
            switchItem("EditorWordWrapItem", res.string.editor_word_wrap, res.string.editor_word_wrap_desc, "format"),
            divider(),
            switchItem("EditorWhitespaceItem", res.string.editor_show_whitespace, res.string.editor_show_whitespace_desc, "format"),
            divider(),
            settingItem("EditorTabSpacesItem", res.string.editor_tab_spaces, res.string.editor_tab_spaces_desc, "format"),
            divider(),
            switchItem("CodeMinimapItem", res.string.code_minimap, res.string.code_minimap_desc, "article"),
            divider(),
            settingItem("MinimapCodeAlphaItem", res.string.minimap_code_alpha, res.string.minimap_code_alpha_desc, "article")
        ),

        sectionTitle(res.string.editor_highlight_color, "format"),
        card(
            colorItem("BaseWord", res.string.hl_baseword, nil, "code"),
            divider(),
            colorItem("KeyWord", res.string.hl_keyword, nil, "code"),
            divider(),
            colorItem("String", res.string.hl_string, nil, "article"),
            divider(),
            colorItem("UserWord", res.string.hl_userword, nil, "code"),
            divider(),
            colorItem("Comment", res.string.hl_comment, nil, "format"),
            divider(),
            colorItem("Global", res.string.hl_global, nil, "code"),
            divider(),
            colorItem("Local", res.string.hl_local, nil, "code"),
            divider(),
            colorItem("Upval", res.string.hl_upval, nil, "code"),
            divider(),
            switchItem("EditorCustomCaretItem", res.string.editor_custom_caret, res.string.editor_custom_caret_desc, "format"),
            {
                MaterialDivider,
                id = "Caret_LightDivider",
                layout_marginLeft = "56dp",
                layout_marginRight = "16dp",
                layout_marginTop = "4dp",
                layout_marginBottom = "4dp",
            },
            colorItem("Caret_Light", res.string.caret_color_light, nil, "format"),
            {
                MaterialDivider,
                id = "Caret_DarkDivider",
                layout_marginLeft = "56dp",
                layout_marginRight = "16dp",
                layout_marginTop = "4dp",
                layout_marginBottom = "4dp",
            },
            colorItem("Caret_Dark", res.string.caret_color_dark, nil, "format"),
            divider(),
            colorItem("MinimapMask", res.string.minimap_mask_desc, nil, "article"),
            divider(),
            colorItem("MinimapBg", res.string.minimap_bg_desc, nil, "article")
        ),

        -- ── 调试 ──
        sectionTitle(res.string.debug, "bug_report"),
        card(
            settingItem("RunKeyModeItem", res.string.run_key_mode, res.string.run_key_mode_desc, "play"),
            divider(),
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
