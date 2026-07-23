---@diagnostic disable: undefined-global
local ColorDrawable = luajava.bindClass "android.graphics.drawable.ColorDrawable"
local MaterialAlertDialogBuilder = luajava.bindClass "com.google.android.material.dialog.MaterialAlertDialogBuilder"
local GradientDrawable = luajava.bindClass "android.graphics.drawable.GradientDrawable"
local Color = luajava.bindClass "android.graphics.Color"
local View = luajava.bindClass "android.view.View"
local WindowManager = luajava.bindClass "android.view.WindowManager"
local MDC_R = luajava.bindClass "com.google.android.material.R"
import "android.widget.LinearLayout"
import "android.widget.FrameLayout"
import "android.widget.SeekBar"
import "android.widget.ScrollView"
import "android.widget.CheckBox"
import "android.widget.Button"
import "android.graphics.Bitmap"
import "android.graphics.Canvas"
import "android.graphics.Paint"
import "android.graphics.drawable.BitmapDrawable"
import "vinx.material.textfield.MaterialTextField"
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.card.MaterialCardView"
this.dynamicColor()
local ColorUtil = this.themeUtil
local barColor = ColorUtil.getColorBackground()
local onSurfaceColor = ColorUtil.getColorOnSurface()
local onSurfaceVarColor = ColorUtil.getColorOnSurfaceVariant()
local primaryColor = ColorUtil.getColorPrimary()

activity {
    title = res.string.setting,
    ContentView = res.layout.setting_layout
}
    .supportActionBar {
        Elevation = 0,
        BackgroundDrawable = ColorDrawable(barColor),
        DisplayShowTitleEnabled = true,
        DisplayHomeAsUpEnabled = true
    }

local window = activity.getWindow()
    .setStatusBarColor(barColor)
    .setNavigationBarColor(barColor)
    .addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
    .clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
if this.isNightMode() then
    window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_VISIBLE)
else
    window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR)
end

function onOptionsItemSelected(m)
    if m.getItemId() == android.R.id.home then
        this.finish()
    end
end

local function sliderRow(label, seekId, valueId)
    return {
        LinearLayout,
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        layout_marginTop = "6dp",
        {
            LinearLayout,
            orientation = "horizontal",
            layout_width = "match",
            layout_height = "wrap",
            gravity = "center_vertical",
            {
                MaterialTextView,
                text = label,
                textSize = "13sp",
                textColor = onSurfaceColor,
                layout_width = "0dp",
                layout_weight = 1,
            },
            {
                MaterialTextView,
                id = valueId,
                text = "0",
                textSize = "12sp",
                textColor = onSurfaceVarColor,
            },
        },
        {
            SeekBar,
            id = seekId,
            layout_width = "match",
            layout_height = "wrap",
            max = 1000,
        },
    }
end

local input = {
    ScrollView,
    layout_width = "match",
    layout_height = "wrap",
    fillViewport = true,
    {
        LinearLayout,
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        paddingLeft = "20dp",
        paddingTop = "12dp",
        paddingRight = "20dp",
        paddingBottom = "8dp",
        Focusable = true,
        FocusableInTouchMode = true,
        {
            MaterialCardView,
            id = "colorPreviewHost",
            layout_width = "match",
            layout_height = "56dp",
            layout_marginBottom = "12dp",
            radius = "12dp",
            CardElevation = 0,
            strokeWidth = "1dp",
            strokeColor = ColorUtil.getColorOutline(),
            CardBackgroundColor = Color.argb(0, 0, 0, 0),
            {
                FrameLayout,
                layout_width = "match",
                layout_height = "match",
                {
                    View,
                    id = "colorPreviewChecker",
                    layout_width = "match",
                    layout_height = "match",
                },
                {
                    View,
                    id = "colorPreview",
                    layout_width = "match",
                    layout_height = "match",
                },
            },
        },
        sliderRow("H", "seekH", "valueH"),
        sliderRow("S", "seekS", "valueS"),
        sliderRow("V", "seekV", "valueV"),
        sliderRow("A", "seekA", "valueA"),
        {
            MaterialTextField,
            layout_width = "fill",
            layout_height = "wrap",
            layout_marginTop = "12dp",
            textSize = "16dp",
            hint = "#[aa]rrggbb",
            tintColor = primaryColor,
            style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
            singleLine = true,
            id = "inputField",
        },
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

local input_symbol_bar = {
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
        textSize = "14dp",
        hint = res.string.symbol_bar_hint,
        tintColor = ColorUtil.getColorPrimary(),
        style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
        singleLine = false,
        minLines = 8,
        id = "inputField",
    },
}

local defaultSymbolBar = {
    "fun", "(", ")", "[", "]", "{", "}",
    "\"", "=", ":", ".", ",", ";", "_",
    "+", "-", "*", "/", "\\", "%",
    "#", "^", "$", "?", "&", "|",
    "<", ">", "~", "'"
}

local defaultSymbolBarText = table.concat(defaultSymbolBar, "\n")

local formatSymbolBarPreview = function(raw)
    if type(raw) ~= "string" or raw == "" then
        return res.string._default
    end
    local symbols = {}
    for line in (raw .. "\n"):gmatch("(.-)\n") do
        local symbol = line:match("^%s*(.-)%s*$")
        if symbol and symbol ~= "" then
            table.insert(symbols, symbol)
        end
    end
    if #symbols == 0 then
        return res.string._default
    end
    if #symbols > 8 then
        local preview = {}
        for i = 1, 8 do
            preview[i] = symbols[i]
        end
        return table.concat(preview, " ") .. " …"
    end
    return table.concat(symbols, " ")
end

local normalizeSymbolBarText = function(raw)
    if type(raw) ~= "string" then
        return nil
    end
    local symbols = {}
    for line in (raw .. "\n"):gmatch("(.-)\n") do
        local symbol = line:match("^%s*(.-)%s*$")
        if symbol and symbol ~= "" then
            table.insert(symbols, symbol)
        end
    end
    if #symbols == 0 then
        return nil
    end
    return table.concat(symbols, "\n")
end

local resetSymbolBarDesc = function()
    SymbolBarItemDesc.text = formatSymbolBarPreview(this.getSharedData("symbol_bar", nil))
end

-- 必须用 Color.argb：0xff...... 在 LuaJ 里是超大 number，传给 Java Color.* 会错
local defaultMap = {
    BaseWord = Color.argb(255, 0x44, 0x77, 0xe0),
    KeyWord = Color.argb(255, 0xb4, 0x00, 0x2d),
    String = Color.argb(255, 0xc2, 0x18, 0x5b),
    UserWord = Color.argb(255, 0x5c, 0x6b, 0xc0),
    Comment = Color.argb(255, 0x71, 0x78, 0x7e),
    Global = Color.argb(255, 0x68, 0x9f, 0x38),
    Local = Color.argb(255, 0xb4, 0xb4, 0x84),
    Upval = Color.argb(255, 0x80, 0x80, 0xc0),
    MinimapMask = Color.argb(0x28, 0x21, 0x96, 0xf3),
    MinimapBg = Color.argb(0, 0, 0, 0),
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
        .setStroke(math.floor(this.dpToPx(1.5) + 0.5), ColorUtil.getColorOutline())
end

local checkerBitmapCache
local function getCheckerBitmap()
    if checkerBitmapCache and not checkerBitmapCache.isRecycled() then
        return checkerBitmapCache
    end
    local cell = math.max(4, math.floor(this.dpToPx(8) + 0.5))
    local size = cell * 8
    local bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    local canvas = Canvas(bmp)
    local paint = Paint()
    paint.setAntiAlias(false)
    -- 用 Color.argb，避免 0xFF...... 大整数被当成 long 调到 setColor(long)
    local light = Color.argb(255, 224, 224, 224)
    local dark = Color.argb(255, 189, 189, 189)
    for y = 0, 7 do
        for x = 0, 7 do
            paint.setColor(((x + y) % 2 == 0) and light or dark)
            canvas.drawRect(x * cell, y * cell, (x + 1) * cell, (y + 1) * cell, paint)
        end
    end
    checkerBitmapCache = bmp
    return bmp
end

local function setPreviewColor(views, color)
    -- 圆角/描边由 MaterialCardView 宿主负责，子层铺满即可，避免直角棋盘漏出
    if views.colorPreviewChecker then
        local checker = BitmapDrawable(this.getResources(), getCheckerBitmap())
        local TileMode = luajava.bindClass "android.graphics.Shader$TileMode"
        checker.setTileModeXY(TileMode.REPEAT, TileMode.REPEAT)
        views.colorPreviewChecker.background = checker
    end
    if views.colorPreview then
        local fill = GradientDrawable()
        fill.setColor(color)
        views.colorPreview.background = fill
    end
end

local resolveColorValue = function(value)
    if type(value) == "number" then
        return value
    end
    if type(value) == "string" and value ~= "" then
        local ok, color = pcall(Color.parseColor, value)
        if ok and type(color) == "number" then
            return color
        end
    end
    return nil
end

--- 当前 SharedData 颜色；未设置 / 无效时用 defaultMap（打开取色器的初值）
local function getColorOrDefault(tag)
    local raw
    pcall(function()
        raw = this.getSharedData(tag, nil)
    end)
    if raw == nil then
        local data = this.getSharedData()
        if data then
            pcall(function() raw = data[tag] end)
        end
    end
    local color = resolveColorValue(raw)
    if color ~= nil then
        return color
    end
    return defaultMap[tag] or Color.argb(255, 0, 0, 0)
end

local function colorToArgb(color)
    color = color or 0
    return Color.alpha(color), Color.red(color), Color.green(color), Color.blue(color)
end

local formatColorValue = function(value)
    local color = resolveColorValue(value)
    if color then
        local a, r, g, b = colorToArgb(color)
        return string.format("#%02X%02X%02X%02X", a, r, g, b)
    end
    return "跟随系统动态取色"
end

local function rgbToHsv(r, g, b)
    r, g, b = r / 255, g / 255, b / 255
    local maxc = math.max(r, g, b)
    local minc = math.min(r, g, b)
    local v = maxc
    local d = maxc - minc
    local s = (maxc == 0) and 0 or (d / maxc)
    local h = 0
    if d > 1e-6 then
        if maxc == r then
            h = (g - b) / d + (g < b and 6 or 0)
        elseif maxc == g then
            h = (b - r) / d + 2
        else
            h = (r - g) / d + 4
        end
        h = h / 6
    end
    return h, s, v
end

local function hsvToRgb(h, s, v)
    h = h % 1
    if h < 0 then h = h + 1 end
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    local r, g, b
    local m = i % 6
    if m == 0 then r, g, b = v, t, p
    elseif m == 1 then r, g, b = q, v, p
    elseif m == 2 then r, g, b = p, v, t
    elseif m == 3 then r, g, b = p, q, v
    elseif m == 4 then r, g, b = t, p, v
    else r, g, b = v, p, q
    end
    return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
end

local function colorToHex(color)
    local a, r, g, b = colorToArgb(color)
    return string.format("#%02X%02X%02X%02X", a, r, g, b)
end

local function argbToColor(a, r, g, b)
    a = math.max(0, math.min(255, math.floor(a + 0.5)))
    r = math.max(0, math.min(255, math.floor(r + 0.5)))
    g = math.max(0, math.min(255, math.floor(g + 0.5)))
    b = math.max(0, math.min(255, math.floor(b + 0.5)))
    return Color.argb(a, r, g, b)
end

local function parseHexColor(text)
    if type(text) ~= "string" then return nil end
    text = text:match("^%s*(.-)%s*$") or ""
    if text == "" then return nil end
    local ok, color = pcall(Color.parseColor, text)
    if ok then return color end
    return nil
end

--- Bind HSV+A SeekBars + hex field + preview. Returns getColor()
local function bindColorPicker(views, initialColor)
    local state = {
        h = 0, s = 0, v = 0, a = 1,
        updating = false,
    }

    local function currentColor()
        local r, g, b = hsvToRgb(state.h, state.s, state.v)
        return argbToColor(state.a * 255, r, g, b)
    end

    local function syncLabels()
        views.valueH.text = string.format("%d°", math.floor(state.h * 360 + 0.5))
        views.valueS.text = string.format("%d%%", math.floor(state.s * 100 + 0.5))
        views.valueV.text = string.format("%d%%", math.floor(state.v * 100 + 0.5))
        views.valueA.text = string.format("%d%%", math.floor(state.a * 100 + 0.5))
    end

    local function pushUiFromState(writeHex)
        local color = currentColor()
        setPreviewColor(views, color)
        syncLabels()
        if writeHex then
            state.updating = true
            pcall(function()
                views.inputField.text = colorToHex(color)
            end)
            state.updating = false
        end
        return color
    end

    local function setFromColor(color, preserveHue)
        local a, r, g, b = colorToArgb(color)
        local h, s, v = rgbToHsv(r, g, b)
        -- 灰阶时保留原色相，避免 H 被重置为 0
        if preserveHue and s < 0.01 then
            h = state.h
        end
        state.h, state.s, state.v, state.a = h, s, v, a / 255
        state.updating = true
        views.seekH.progress = math.floor(state.h * 1000 + 0.5)
        views.seekS.progress = math.floor(state.s * 1000 + 0.5)
        views.seekV.progress = math.floor(state.v * 1000 + 0.5)
        views.seekA.progress = math.floor(state.a * 1000 + 0.5)
        views.inputField.text = colorToHex(color)
        setPreviewColor(views, color)
        syncLabels()
        state.updating = false
    end

    local function onSeek(which)
        return {
            onProgressChanged = function(seekBar, progress, fromUser)
                if state.updating then return end
                if fromUser == false then return end
                local p = progress / 1000
                if which == "h" then
                    state.h = p
                elseif which == "s" then
                    state.s = p
                elseif which == "v" then
                    state.v = p
                else
                    state.a = p
                end
                pushUiFromState(true)
            end,
            onStartTrackingTouch = function() end,
            onStopTrackingTouch = function() end,
        }
    end

    views.seekH.setOnSeekBarChangeListener(onSeek("h"))
    views.seekS.setOnSeekBarChangeListener(onSeek("s"))
    views.seekV.setOnSeekBarChangeListener(onSeek("v"))
    views.seekA.setOnSeekBarChangeListener(onSeek("a"))

    views.inputField.addTextChangedListener {
        afterTextChanged = function(s)
            if state.updating then return end
            local color = parseHexColor(tostring(s or ""))
            if not color then return end
            setFromColor(color, true)
        end,
    }

    setFromColor(initialColor or 0xFF000000, false)

    return currentColor
end

local function hideAlphaRow(views)
    -- sliderRow: vertical LinearLayout → [label row, SeekBar]
    -- seekA 的 parent 就是 A 行本身，绝不能再 getParent()（那是整块内容）
    pcall(function()
        views.seekA.progress = 1000
        views.seekA.setEnabled(false)
        local row = views.seekA.getParent()
        if row and row.setVisibility then
            row.setVisibility(View.GONE)
        else
            views.seekA.setVisibility(View.GONE)
            if views.valueA then views.valueA.setVisibility(View.GONE) end
        end
    end)
end

--- options: { hideAlpha = bool, defaultLabel = string }
local function showColorPickerDialog(title, initialColor, onOk, onDefault, options)
    options = options or {}
    local views = {}
    local content = loadlayout(input, views)

    local startColor = initialColor
    if type(startColor) ~= "number" then
        startColor = ColorUtil.getColorPrimary()
    end
    if type(startColor) ~= "number" then
        startColor = Color.argb(255, 103, 80, 164)
    end
    if options.hideAlpha then
        local _, r, g, b = colorToArgb(startColor)
        startColor = argbToColor(255, r, g, b)
    end

    local getColor
    local okBind, errBind = pcall(function()
        getColor = bindColorPicker(views, startColor)
        if options.hideAlpha then
            hideAlphaRow(views)
        end
    end)
    if not okBind then
        print("color picker bind failed: " .. tostring(errBind))
        -- 至少保证输入框有初值
        pcall(function()
            views.inputField.text = colorToHex(startColor)
        end)
        getColor = function()
            return startColor
        end
    end

    local builder = MaterialAlertDialogBuilder(this)
        .setTitle(title)
        .setView(content)
        .setPositiveButton(android.R.string.ok, function()
            local text = tostring(views.inputField.text or "")
            local trimmed = (text:match("^%s*(.-)%s*$") or "")
            local color = parseHexColor(trimmed)
            if trimmed ~= "" and not color then
                print(res.string.invalid_format)
                return
            end
            if not color and getColor then
                color = getColor()
            end
            if not color then
                print(res.string.invalid_format)
                return
            end
            if options.hideAlpha then
                local _, r, g, b = colorToArgb(color)
                color = argbToColor(255, r, g, b)
            end
            if onOk then onOk(color, colorToHex(color)) end
        end)
        .setNegativeButton(android.R.string.cancel, nil)
    if onDefault then
        builder.setNeutralButton(options.defaultLabel or res.string._default, function()
            onDefault()
        end)
    end
    builder.show()
end

local resetThemeColor = function()
    local seedColor = this.getSharedData("theme_seed_color", nil)
    local color = resolveColorValue(seedColor)
    ThemeColorDesc.text = formatColorValue(seedColor)
    setCircleColor(ThemeColorCircle, color or ColorUtil.getColorPrimary())
end

local resetColor = function(tag)
    setCircleColor(_G[tag .. "Circle"], getColorOrDefault(tag))
end

local click = View.OnClickListener {
    onClick = function(view)
        local tag = view.tag
        -- 未自定义时 initial = defaultMap，取色器滑块/预览/hex 均为默认色
        local initial = getColorOrDefault(tag)
        showColorPickerDialog(tag, initial, function(color, hex)
            this.setSharedData(tag, hex)
            resetColor(tag)
        end, function()
            this.setSharedData(tag, nil)
            resetColor(tag)
        end)
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
MinimapMaskItem.setOnClickListener(click)
MinimapBgItem.setOnClickListener(click)

local function applyThemeSeedColor(color)
    if color == nil then
        this.setSharedData("theme_seed_color", nil)
        this.dynamicColor()
    else
        local _, r, g, b = colorToArgb(color)
        color = argbToColor(255, r, g, b)
        this.setSharedData("theme_seed_color", color)
        this.dynamicColor(color)
    end
    this.recreate()
end

local function openThemeHsvPicker()
    local seedColor = this.getSharedData("theme_seed_color", nil)
    local initial = resolveColorValue(seedColor)
    -- 默认主题色：当前 Material primary（与圆点预览一致）
    if type(initial) ~= "number" then
        pcall(function()
            initial = ColorUtil.getColorPrimary()
        end)
    end
    if type(initial) ~= "number" then
        initial = Color.argb(255, 103, 80, 164)
    end
    showColorPickerDialog(
        "主题色",
        initial,
        function(color, hex)
            applyThemeSeedColor(color)
        end,
        function()
            applyThemeSeedColor(nil)
        end,
        {
            hideAlpha = true,
            defaultLabel = "跟随系统",
        }
    )
end

ThemeColorItem.onClick = function()
    local items = { "HSV 取色…", "跟随系统动态取色" }
    for _, item in ipairs(themeColorPresets) do
        table.insert(items, item[1])
    end

    MaterialAlertDialogBuilder(this)
        .setTitle("主题色")
        .setItems(items, function(dialog, which)
            if which == 0 then
                -- 列表对话框 dismiss 后再开，避免嵌套被吞；多延迟一帧更稳
                local decor = activity.getWindow().getDecorView()
                decor.post(function()
                    decor.post(function()
                        openThemeHsvPicker()
                    end)
                end)
                return
            end
            if which == 1 then
                applyThemeSeedColor(nil)
                return
            end
            local seedColor = themeColorPresets[which - 1][2]
            local ok, color = pcall(Color.parseColor, seedColor)
            if ok then
                applyThemeSeedColor(color)
            end
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
resetColor("MinimapMask")
resetColor("MinimapBg")

-- ── 符号栏 ──
SymbolBarItem.onClick = function()
    local views = {}
    MaterialAlertDialogBuilder(this)
        .setTitle(res.string.symbol_bar)
        .setView(loadlayout(input_symbol_bar, views))
        .setPositiveButton(android.R.string.ok, function()
            local normalized = normalizeSymbolBarText(views.inputField.text)
            this.setSharedData("symbol_bar", normalized)
            resetSymbolBarDesc()
        end)
        .setNegativeButton(android.R.string.cancel, nil)
        .setNeutralButton(res.string._default, function()
            this.setSharedData("symbol_bar", nil)
            resetSymbolBarDesc()
        end)
        .show()
    views.inputField.text = this.getSharedData("symbol_bar", defaultSymbolBarText)
end

resetSymbolBarDesc()

-- ── 功能栏自定义（轻量模块，勿 require activities.main.Init）──
local FunctionBarConfig = require "mods.utils.FunctionBarConfig"

local function formatFunctionBarPreview(raw)
    local catalog = FunctionBarConfig.getCatalog()
    local titleOf = {}
    for _, item in ipairs(catalog) do
        titleOf[item.id] = item.title
    end
    local ids = FunctionBarConfig.parseIds(raw)
    if not ids then
        ids = FunctionBarConfig.getDefaultIds()
    end
    if #ids == 0 then
        return res.string._default
    end
    local labels = {}
    for i = 1, math.min(6, #ids) do
        labels[i] = titleOf[ids[i]] or ids[i]
    end
    local text = table.concat(labels, " · ")
    if #ids > 6 then
        text = text .. " …"
    end
    return text
end

local function resetFunctionBarDesc()
    FunctionBarItemDesc.text = formatFunctionBarPreview(this.getSharedData("function_bar", nil))
end

FunctionBarItem.onClick = function()
    local catalog = FunctionBarConfig.getCatalog()
    local defaultIds = FunctionBarConfig.getDefaultIds()
    local currentIds = FunctionBarConfig.parseIds(this.getSharedData("function_bar", nil)) or defaultIds

    local titleOf = {}
    local catalogIds = {}
    for _, item in ipairs(catalog) do
        titleOf[item.id] = item.title
        catalogIds[#catalogIds + 1] = item.id
    end

    local selected = {}
    for _, id in ipairs(currentIds) do
        selected[id] = true
    end

    -- 列表顺序：已启用项按当前顺序，其余按目录顺序接在后面
    local order = {}
    local inOrder = {}
    for _, id in ipairs(currentIds) do
        if titleOf[id] and not inOrder[id] then
            inOrder[id] = true
            order[#order + 1] = id
        end
    end
    for _, id in ipairs(catalogIds) do
        if not inOrder[id] then
            inOrder[id] = true
            order[#order + 1] = id
        end
    end

    local scrollViews = {}
    local listHost

    local function swap(i, j)
        order[i], order[j] = order[j], order[i]
    end

    local function rebuildList()
        if not listHost then return end
        listHost.removeAllViews()
        for i, id in ipairs(order) do
            local idx = i
            local itemId = id
            listHost.addView(loadlayout({
                LinearLayout,
                orientation = "horizontal",
                layout_width = "match",
                layout_height = "wrap",
                gravity = "center_vertical",
                paddingTop = "4dp",
                paddingBottom = "4dp",
                {
                    CheckBox,
                    layout_width = "wrap",
                    layout_height = "wrap",
                    checked = selected[itemId] == true,
                    onClick = function(v)
                        selected[itemId] = v.isChecked()
                    end,
                },
                {
                    MaterialTextView,
                    text = titleOf[itemId] or itemId,
                    textSize = "15sp",
                    textColor = onSurfaceColor,
                    layout_width = "0dp",
                    layout_weight = 1,
                    paddingLeft = "4dp",
                    paddingRight = "4dp",
                },
                {
                    Button,
                    text = "↑",
                    layout_width = "40dp",
                    layout_height = "40dp",
                    minWidth = 0,
                    minHeight = 0,
                    onClick = function()
                        if idx > 1 then
                            swap(idx, idx - 1)
                            rebuildList()
                        end
                    end,
                },
                {
                    Button,
                    text = "↓",
                    layout_width = "40dp",
                    layout_height = "40dp",
                    minWidth = 0,
                    minHeight = 0,
                    onClick = function()
                        if idx < #order then
                            swap(idx, idx + 1)
                            rebuildList()
                        end
                    end,
                },
            }))
        end
    end

    local content = loadlayout({
        LinearLayout,
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        paddingLeft = "12dp",
        paddingRight = "12dp",
        paddingTop = "8dp",
        {
            MaterialTextView,
            text = res.string.function_bar_hint,
            textSize = "12sp",
            textColor = onSurfaceVarColor,
            paddingBottom = "8dp",
        },
        {
            ScrollView,
            layout_width = "match",
            layout_height = "360dp",
            {
                LinearLayout,
                orientation = "vertical",
                layout_width = "match",
                layout_height = "wrap",
                id = "listHost",
            },
        },
    }, scrollViews)

    listHost = scrollViews.listHost
    rebuildList()

    MaterialAlertDialogBuilder(this)
        .setTitle(res.string.function_bar)
        .setView(content)
        .setPositiveButton(android.R.string.ok, function()
            local out = {}
            for _, id in ipairs(order) do
                if selected[id] then
                    out[#out + 1] = id
                end
            end
            if #out == 0 then
                this.setSharedData("function_bar", nil)
            else
                this.setSharedData("function_bar", table.concat(out, "\n"))
            end
            resetFunctionBarDesc()
        end)
        .setNegativeButton(android.R.string.cancel, nil)
        .setNeutralButton(res.string._default, function()
            this.setSharedData("function_bar", nil)
            resetFunctionBarDesc()
        end)
        .show()
end

resetFunctionBarDesc()

local function isSharedTruthy(value)
    return value == true or value == "true" or value == 1
end

-- ── 平板模式 ──
local function isLargeScreenDevice()
    local ok, large = pcall(function()
        local dm = this.getResources().getDisplayMetrics()
        local sw = math.min(dm.widthPixels, dm.heightPixels) / dm.density
        return sw >= 600
    end)
    return ok and large
end

TabletModeItemSwitch.checked = isSharedTruthy(this.getSharedData("tablet_mode", false))
-- 大屏设备补充说明
pcall(function()
    if isLargeScreenDevice() then
        TabletModeItemDesc.text = res.string.tablet_mode_desc .. " · " .. res.string.tablet_mode_large_hint
    end
end)
TabletModeItem.onClick = function()
    local enabled = not TabletModeItemSwitch.isChecked()
    TabletModeItemSwitch.checked = enabled
    this.setSharedData("tablet_mode", enabled)
    print(enabled and res.string.tablet_mode_on_hint or res.string.tablet_mode_off_hint)
    -- 主界面 onResume 会 invalidateOptionsMenu 刷新工具栏
end

-- ── 双行符号栏 ──
SymbolBarTwoRowsItemSwitch.checked = isSharedTruthy(this.getSharedData("symbol_bar_two_rows", false))
SymbolBarTwoRowsItem.onClick = function()
    local enabled = not SymbolBarTwoRowsItemSwitch.isChecked()
    SymbolBarTwoRowsItemSwitch.checked = enabled
    this.setSharedData("symbol_bar_two_rows", enabled)
end

local BAR_TEXT_SIZE_MIN = 3
local BAR_TEXT_SIZE_MAX = 24
local DEFAULT_SYMBOL_BAR_TEXT_SIZE = 5
local DEFAULT_FUNCTION_TAB_TEXT_SIZE = 5

local function clampBarTextSize(value, defaultSize)
    local n = tonumber(value)
    if not n then return defaultSize end
    n = math.floor(n + 0.5)
    if n < BAR_TEXT_SIZE_MIN then return BAR_TEXT_SIZE_MIN end
    if n > BAR_TEXT_SIZE_MAX then return BAR_TEXT_SIZE_MAX end
    return n
end

local function formatBarTextSizeDesc(value, defaultSize)
    return string.format("%dsp", clampBarTextSize(value, defaultSize))
end

local function refreshBarTextSizeDescs()
    SymbolBarTextSizeItemDesc.text = formatBarTextSizeDesc(
        this.getSharedData("symbol_bar_text_size", DEFAULT_SYMBOL_BAR_TEXT_SIZE),
        DEFAULT_SYMBOL_BAR_TEXT_SIZE
    )
    FunctionTabTextSizeItemDesc.text = formatBarTextSizeDesc(
        this.getSharedData("function_tab_text_size", DEFAULT_FUNCTION_TAB_TEXT_SIZE),
        DEFAULT_FUNCTION_TAB_TEXT_SIZE
    )
end

local function showBarTextSizeDialog(title, key, defaultSize)
    local sizes = {}
    local labels = {}
    local current = clampBarTextSize(this.getSharedData(key, defaultSize), defaultSize)
    local checked = 0
    for size = BAR_TEXT_SIZE_MIN, BAR_TEXT_SIZE_MAX do
        sizes[#sizes + 1] = size
        labels[#labels + 1] = string.format("%dsp", size)
        if size == current then
            checked = #sizes - 1
        end
    end
    MaterialAlertDialogBuilder(this)
        .setTitle(title)
        .setSingleChoiceItems(labels, checked, function(dialog, which)
            this.setSharedData(key, sizes[which + 1])
            refreshBarTextSizeDescs()
            dialog.dismiss()
        end)
        .setNegativeButton(android.R.string.cancel, nil)
        .setNeutralButton(res.string._default, function()
            this.setSharedData(key, nil)
            refreshBarTextSizeDescs()
        end)
        .show()
end

SymbolBarTextSizeItem.onClick = function()
    showBarTextSizeDialog(
        res.string.symbol_bar_text_size,
        "symbol_bar_text_size",
        DEFAULT_SYMBOL_BAR_TEXT_SIZE
    )
end

FunctionTabTextSizeItem.onClick = function()
    showBarTextSizeDialog(
        res.string.function_tab_text_size,
        "function_tab_text_size",
        DEFAULT_FUNCTION_TAB_TEXT_SIZE
    )
end

refreshBarTextSizeDescs()

-- ── 编辑器放大镜 ──
EditorMagnifierItemSwitch.checked = isSharedTruthy(this.getSharedData("editor_magnifier", true))
EditorMagnifierItem.onClick = function()
    local enabled = not EditorMagnifierItemSwitch.isChecked()
    EditorMagnifierItemSwitch.checked = enabled
    this.setSharedData("editor_magnifier", enabled)
end

-- ── 代码缩略图 ──
CodeMinimapItemSwitch.checked = isSharedTruthy(this.getSharedData("code_minimap", true))
CodeMinimapItem.onClick = function()
    local enabled = not CodeMinimapItemSwitch.isChecked()
    CodeMinimapItemSwitch.checked = enabled
    this.setSharedData("code_minimap", enabled)
end

local DEFAULT_MINIMAP_CODE_ALPHA = 200

local function clampCodeAlpha(value)
    local n = tonumber(value)
    if not n then return DEFAULT_MINIMAP_CODE_ALPHA end
    n = math.floor(n + 0.5)
    if n < 0 then return 0 end
    if n > 255 then return 255 end
    return n
end

local function formatCodeAlphaDesc(value)
    local a = clampCodeAlpha(value)
    return string.format("%d%% (%d)", math.floor(a * 100 / 255 + 0.5), a)
end

local function refreshMinimapCodeAlphaDesc()
    MinimapCodeAlphaItemDesc.text = formatCodeAlphaDesc(
        this.getSharedData("code_minimap_alpha", DEFAULT_MINIMAP_CODE_ALPHA)
    )
end

local input_code_alpha = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    paddingLeft = "20dp",
    paddingRight = "20dp",
    paddingTop = "12dp",
    paddingBottom = "8dp",
    {
        MaterialTextView,
        id = "alphaValueLabel",
        textSize = "14sp",
        textColor = onSurfaceColor,
        text = "78%",
    },
    {
        SeekBar,
        id = "alphaSeek",
        layout_width = "match",
        layout_height = "wrap",
        layout_marginTop = "8dp",
        max = 255,
    },
    {
        MaterialTextView,
        text = "0 = 全透明 · 255 = 不透明 · 默认 200",
        textSize = "12sp",
        textColor = onSurfaceVarColor,
        paddingTop = "8dp",
    },
}

MinimapCodeAlphaItem.onClick = function()
    local views = {}
    local current = clampCodeAlpha(this.getSharedData("code_minimap_alpha", DEFAULT_MINIMAP_CODE_ALPHA))
    MaterialAlertDialogBuilder(this)
        .setTitle(res.string.minimap_code_alpha)
        .setView(loadlayout(input_code_alpha, views))
        .setPositiveButton(android.R.string.ok, function()
            local a = clampCodeAlpha(views.alphaSeek.getProgress())
            this.setSharedData("code_minimap_alpha", a)
            refreshMinimapCodeAlphaDesc()
        end)
        .setNegativeButton(android.R.string.cancel, nil)
        .setNeutralButton(res.string._default, function()
            this.setSharedData("code_minimap_alpha", nil)
            refreshMinimapCodeAlphaDesc()
        end)
        .show()
    views.alphaSeek.progress = current
    views.alphaValueLabel.text = formatCodeAlphaDesc(current)
    views.alphaSeek.setOnSeekBarChangeListener {
        onProgressChanged = function(seekBar, progress, fromUser)
            views.alphaValueLabel.text = formatCodeAlphaDesc(progress)
        end,
        onStartTrackingTouch = function() end,
        onStopTrackingTouch = function() end,
    }
end

refreshMinimapCodeAlphaDesc()

-- ── 运行键行为（工具栏 ▶）──
local RunKeyConfig = require "mods.utils.RunKeyConfig"

local function refreshRunKeyModeDesc()
    local mode = RunKeyConfig.getMode(this)
    RunKeyModeItemDesc.setText(
        RunKeyConfig.label(mode) .. " · " .. res.string.run_key_mode_desc
    )
end

refreshRunKeyModeDesc()

RunKeyModeItem.onClick = function()
    RunKeyConfig.showPicker(this, refreshRunKeyModeDesc)
end

-- ── 运行窗口模式（与 Init 共用 RunWindowConfig）──
local RunWindowConfig = require "mods.utils.RunWindowConfig"

local function refreshRunWindowModeDesc()
    pcall(function()
        local mode = RunWindowConfig.getMode(this)
        RunWindowModeItemDesc.setText(
            RunWindowConfig.label(mode) .. " · " .. (res.string.run_window_mode_desc or "")
        )
    end)
end

refreshRunWindowModeDesc()

RunWindowModeItem.onClick = function()
    local current = RunWindowConfig.getMode(this)
    local labels = RunWindowConfig.labels()
    local checked = RunWindowConfig.indexOf(current) - 1
    MaterialAlertDialogBuilder(this)
        .setTitle(res.string.run_window_mode)
        .setSingleChoiceItems(labels, checked, function(_, which)
            checked = which
        end)
        .setPositiveButton(android.R.string.ok, function()
            local mode = RunWindowConfig.MODES[checked + 1] or RunWindowConfig.MODE_OFF
            RunWindowConfig.setMode(this, mode)
            refreshRunWindowModeDesc()
        end)
        .setNegativeButton(android.R.string.cancel, nil)
        .show()
end

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
    local version = this.getVersionName("unknown")
    local message = table.concat({
        res.string.about_this,
        "",
        res.string.copyright,
        "v" .. tostring(version),
    }, "\n")
    MaterialAlertDialogBuilder(this)
        .setTitle("NeLuaJ+")
        .setMessage(message)
        .setPositiveButton(android.R.string.ok, nil)
        .show()
end

CopyrightItem.onClick = function()
    MaterialAlertDialogBuilder(this)
        .setTitle(res.string.copyright_title)
        .setMessage(res.string.copyright)
        .setPositiveButton(android.R.string.ok, nil)
        .show()
end
