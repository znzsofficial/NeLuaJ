---@diagnostic disable: undefined-global
local ColorDrawable = luajava.bindClass "android.graphics.drawable.ColorDrawable"
local MaterialAlertDialogBuilder = luajava.bindClass "com.google.android.material.dialog.MaterialAlertDialogBuilder"
local GradientDrawable = luajava.bindClass "android.graphics.drawable.GradientDrawable"
local Color = luajava.bindClass "android.graphics.Color"
local View = luajava.bindClass "android.view.View"
local MDC_R = luajava.bindClass "com.google.android.material.R"
import "android.widget.LinearLayout"
import "vinx.material.textfield.MaterialTextField"
this.dynamicColor()
local ColorUtil = this.themeUtil

activity {
    title = res.string.setting,
    ContentView = res.layout.setting_layout
}
    .supportActionBar {
        Elevation = 0,
        BackgroundDrawable = ColorDrawable(ColorUtil.getColorBackground()),
        DisplayShowTitleEnabled = true,
        DisplayHomeAsUpEnabled = true
    }

function onOptionsItemSelected(m)
    if m.getItemId() == android.R.id.home then
        this.finish()
    end
end

local input = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
    paddingLeft = "20dp",
    paddingTop = "20dp",
    paddingRight = "20dp",
    Focusable = true,
    FocusableInTouchMode = true,
    {
        MaterialTextField,
        layout_width = "fill",
        layout_height = "wrap",
        textSize = "16dp",
        hint = "#[aa]rrggbb",
        tintColor = ColorUtil.getColorPrimary(),
        style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
        singleLine = true,
        id = "inputField",
    },
}

local input_package = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
    paddingLeft = "20dp",
    paddingTop = "20dp",
    paddingRight = "20dp",
    Focusable = true,
    FocusableInTouchMode = true,
    {
        MaterialTextField,
        layout_width = "fill",
        layout_height = "wrap",
        textSize = "16dp",
        hint = res.string.package_name,
        tintColor = ColorUtil.getColorPrimary(),
        style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
        singleLine = true,
        id = "inputField",
    },
}

local defaultMap = {
    BaseWord = 0xff4477e0,
    KeyWord = 0xffb4002d,
    String = 0xffc2185b,
    UserWord = 0xff5c6bc0,
    Comment = 0xff71787E,
    Global = 0xff689f38,
    Local = 0xffb4b484,
    Upval = 0xff8080c0,
}

local themeColorPresets = {
    { "默认紫", "#FF6750A4" },
    { "天空蓝", "#FF1976D2" },
    { "湖水青", "#FF00897B" },
    { "森林绿", "#FF2E7D32" },
    { "暖橙", "#FFEF6C00" },
    { "玫瑰红", "#FFC2185B" },
    { "深灰", "#FF455A64" },
}

local setCircleColor = function(view, color)
    view.background = GradientDrawable()
        .setShape(GradientDrawable.OVAL)
        .setColor(color)
        .setStroke(4, ColorUtil.getColorOutline())
end

local resolveColorValue = function(value)
    if type(value) == "number" then
        return value
    end

    if type(value) == "string" and value ~= "" then
        local ok, color = pcall(Color.parseColor, value)
        if ok then
            return color
        end
    end

    return nil
end

local formatColorValue = function(value)
    local color = resolveColorValue(value)
    if color then
        return string.format("#%08X", color)
    end
    return "跟随系统动态取色"
end

local resetThemeColor = function()
    local seedColor = this.getSharedData("theme_seed_color", nil)
    local color = resolveColorValue(seedColor)
    ThemeColorDesc.text = formatColorValue(seedColor)
    setCircleColor(ThemeColorCircle, color or ColorUtil.getColorPrimary())
end

local resetColor = function(tag)
    local data = this.getSharedData()
    setCircleColor(_G[tag .. "Circle"], data[tag] and Color.parseColor(data[tag]) or defaultMap[tag])
end

local click = View.OnClickListener {
    onClick = function(view)
        local views = {}
        MaterialAlertDialogBuilder(this)
            .setTitle(view.tag)
            .setView(loadlayout(input, views))
            .setPositiveButton(android.R.string.ok, function()
                local inputColor = views.inputField.text
                local bool, _ = pcall(Color.parseColor, inputColor)
                if not bool then
                    print(res.string.invalid_format)
                    return
                end
                this.setSharedData(view.tag, inputColor)
                resetColor(view.tag)
            end)
            .setNegativeButton(android.R.string.cancel, nil)
            .setNeutralButton(res.string._default, function()
                this.setSharedData(view.tag, nil)
                resetColor(view.tag)
            end)
            .show()
    end
}
BaseWordItem.setOnClickListener(click)
KeyWordItem.setOnClickListener(click)
StringItem.setOnClickListener(click)
UserWordItem.setOnClickListener(click)
CommentItem.setOnClickListener(click)
GlobalItem.setOnClickListener(click)
LocalItem.setOnClickListener(click)
UpvalItem.setOnClickListener(click)

ThemeColorItem.onClick = function()
    local items = { "跟随系统动态取色" }
    for _, item in ipairs(themeColorPresets) do
        table.insert(items, item[1])
    end
    table.insert(items, "自定义颜色...")

    MaterialAlertDialogBuilder(this)
        .setTitle("主题色")
        .setItems(items, function(dialog, which)
            if which == 0 then
                this.setSharedData("theme_seed_color", nil)
                this.dynamicColor()
                this.recreate()
                return
            end

            if which == #items - 1 then
                local views = {}
                MaterialAlertDialogBuilder(this)
                    .setTitle("自定义主题色")
                    .setView(loadlayout(input, views))
                    .setPositiveButton(android.R.string.ok, function()
                        local inputColor = views.inputField.text
                        local bool, color = pcall(Color.parseColor, inputColor)
                        if not bool then
                            print(res.string.invalid_format)
                            return
                        end
                        this.setSharedData("theme_seed_color", color)
                        this.dynamicColor(color)
                        this.recreate()
                    end)
                    .setNegativeButton(android.R.string.cancel, nil)
                    .show()
                local seedColor = this.getSharedData("theme_seed_color", nil)
                local seedText = formatColorValue(seedColor)
                views.inputField.text = seedText ~= "跟随系统动态取色" and seedText or ""
                return
            end

            local seedColor = themeColorPresets[which][2]
            local color = Color.parseColor(seedColor)
            this.setSharedData("theme_seed_color", color)
            this.dynamicColor(color)
            this.recreate()
        end)
        .setNegativeButton(android.R.string.cancel, nil)
        .show()
end

resetThemeColor()
resetColor("BaseWord")
resetColor("KeyWord")
resetColor("String")
resetColor("UserWord")
resetColor("Comment")
resetColor("Global")
resetColor("Local")
resetColor("Upval")

-- ── 调试应用 ──
CustomApp.onClick = function()
    local views = {}
    MaterialAlertDialogBuilder(this)
        .setTitle(res.string.debug_app)
        .setView(loadlayout(input_package, views))
        .setPositiveButton(android.R.string.ok, function()
            local package = views.inputField.text
            if this.packageManager.getLaunchIntentForPackage(package) then
                this.setSharedData("debug_app", views.inputField.text)
            else
                print(res.string.app_not_found)
            end
        end)
        .setNegativeButton(android.R.string.cancel, nil)
        .setNeutralButton(res.string.delete, function()
            this.setSharedData("debug_app", nil)
        end)
        .show()
    views.inputField.text = this.getSharedData("debug_app", "")
end

-- ── 关于 ──
AboutItem.onClick = function()
    MaterialAlertDialogBuilder(this)
        .setTitle("NeLuaJ+")
        .setMessage(res.string.about_this)
        .setPositiveButton(android.R.string.ok, nil)
        .show()
end
