local require = require
local table = require "table"
local insert = table.insert
local new = luajava.new
local bindClass = luajava.bindClass
local ids = {}
local ltrs = {}
local id = 0x7f000000
local context = activity or service
local luadir = LayoutHelperActivity.data.this_project_lua_dir

local MotionEvent = bindClass "android.view.MotionEvent"
local AdapterView = bindClass "android.widget.AdapterView"
local String = bindClass "java.lang.String"
local TypedValue = bindClass "android.util.TypedValue"
local BitmapDrawable = bindClass "android.graphics.drawable.BitmapDrawable"
local LuaDrawable = bindClass "com.androlua.LuaDrawable"
local ArrayListAdapter = bindClass "com.androlua.adapter.ArrayListAdapter"
local AbsoluteLayout = bindClass "android.widget.AbsoluteLayout"
local LuaAdapter = bindClass "com.androlua.adapter.LuaAdapter"
local ContextThemeWrapper = bindClass "androidx.appcompat.view.ContextThemeWrapper"
local View = bindClass "android.view.View"
local ViewGroup = bindClass "android.view.ViewGroup"
local ArrayAdapter = bindClass "android.widget.ArrayAdapter"
local GradientDrawable = bindClass "android.graphics.drawable.GradientDrawable"
local NineBitmapDrawable = bindClass "com.androlua.NineBitmapDrawable"
local OnClickListener = bindClass("android.view.View$OnClickListener")
local TruncateAt = bindClass("android.text.TextUtils$TruncateAt")
local ScaleType = bindClass("android.widget.ImageView$ScaleType")

local Typeface = bindClass "android.graphics.Typeface"
local scaleTypes = ScaleType.values()
local android_R = bindClass("android.R")
local ColorAccent = ColorUtil.getColorAccent()

local Context = bindClass "android.content.Context"
local DisplayMetrics = bindClass "android.util.DisplayMetrics"

local wm = context.getSystemService(Context.WINDOW_SERVICE);
local outMetrics = DisplayMetrics();
wm.getDefaultDisplay().getMetrics(outMetrics);
local W = outMetrics.widthPixels;
local H = outMetrics.heightPixels;

local dm = context.getResources().getDisplayMetrics()
local resourceCache = {}

local function cacheKey(defType, name)
    return tostring(defType or "") .. ":" .. tostring(name)
end

local function getIdentifier(name, defType)
    local key = cacheKey(defType, name)
    local cached = resourceCache[key]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end

    local res = context.getResources().getIdentifier(name, defType, context.getPackageName())
    if res == 0 and name:find("%.") then
        res = context.getResources().getIdentifier((name:gsub("%.", "_")), defType, context.getPackageName())
    end

    resourceCache[key] = res ~= 0 and res or false
    return res ~= 0 and res or nil
end

local function getAttrIdentifier(name)
    return android_R.attr[name] or getIdentifier(name, "attr")
end

local function getStyleIdentifier(name)
    return android_R.style[name] or getIdentifier(name, "style")
end

local checkattr

local function safeCall(target, method, ...)
    if target and target[method] then
        local ok = pcall(target[method], ...)
        return ok
    end
    return false
end

local function resolveStyleField(v, field)
    if type(v) == "number" then
        return v
    end
    if type(v) ~= "string" then
        return nil
    end

    v = v:match("^%s*(.-)%s*$")
    if v == "" or v == "nil" then
        return nil
    end

    local n = tonumber(v)
    if n then
        return n
    end

    if field == "theme" then
        if v:find("^@android:style/") then
            return android_R.style[v:sub(16)] or getStyleIdentifier(v:sub(16))
        elseif v:find("^@style/") then
            return getStyleIdentifier(v:sub(8))
        elseif v:find("^@") then
            local name = v:sub(2)
            return getStyleIdentifier(name) or getAttrIdentifier(name)
        end
        return getStyleIdentifier(v)
    elseif field == "styleAttr" then
        if v:find("^%?android:attr/") then
            return android_R.attr[v:sub(15)] or getAttrIdentifier(v:sub(15))
        elseif v:find("^%?attr/") then
            return getAttrIdentifier(v:sub(7))
        elseif v:find("^%?") then
            local name = v:sub(2)
            return getAttrIdentifier(name)
        elseif v:find("^@attr/") then
            return getAttrIdentifier(v:sub(7))
        end
        return getAttrIdentifier(v)
    elseif field == "styleRes" then
        if v:find("^@android:style/") then
            return android_R.style[v:sub(16)] or getStyleIdentifier(v:sub(16))
        elseif v:find("^@style/") then
            return getStyleIdentifier(v:sub(8))
        elseif v:find("^@") then
            local name = v:sub(2)
            return getStyleIdentifier(name) or getAttrIdentifier(name)
        end
        return getStyleIdentifier(v)
    elseif field == "style" then
        if v:find("^%?android:attr/") then
            return android_R.attr[v:sub(15)] or getAttrIdentifier(v:sub(15))
        elseif v:find("^%?attr/") then
            return getAttrIdentifier(v:sub(7))
        elseif v:find("^%?") then
            local name = v:sub(2)
            return getAttrIdentifier(name)
        elseif v:find("^@android:style/") then
            return android_R.style[v:sub(16)] or getStyleIdentifier(v:sub(16))
        elseif v:find("^@style/") then
            return getStyleIdentifier(v:sub(8))
        elseif v:find("^@attr/") then
            return getAttrIdentifier(v:sub(7))
        elseif v:find("^@") then
            local name = v:sub(2)
            return getStyleIdentifier(name) or getAttrIdentifier(name)
        end
    end

    return nil
end

local function resolveLegacyStyle(v)
    local style = resolveStyleField(v, "style")
    if style then
        return style
    end

    if type(v) == "string" then
        local ok, sty = pcall(require, v)
        if ok then
            return sty, "table"
        end
        local attr = checkattr(v)
        if attr then
            return attr, "attr"
        end
        return getStyleIdentifier(v), "style"
    elseif type(v) == "number" then
        return v, "style"
    end

    return nil
end

local toint = {
    --android:drawingCacheQuality
    auto = 0,
    low = 1,
    high = 2,

    --android:importantForAccessibility
    auto = 0,
    yes = 1,
    no = 2,

    --android:layerType
    none = 0,
    software = 1,
    hardware = 2,

    --android:layoutDirection
    ltr = 0,
    rtl = 1,
    inherit = 2,
    locale = 3,

    --android:scrollbarStyle
    insideOverlay = 0x0,
    insideInset = 0x01000000,
    outsideOverlay = 0x02000000,
    outsideInset = 0x03000000,

    --android:visibility
    visible = 0,
    invisible = 1,
    gone = 2,

    wrap_content = -2,
    fill_parent = -1,
    match_parent = -1,
    wrap = -2,
    fill = -1,
    match = -1,

    --android:autoLink
    none = 0x00,
    web = 0x01,
    email = 0x02,
    phon = 0x04,
    map = 0x08,
    all = 0x0f,

    --android:orientation
    vertical = 1,
    horizontal = 0,

    --android:gravity
    axis_clip = 8,
    axis_pull_after = 4,
    axis_pull_before = 2,
    axis_specified = 1,
    axis_x_shift = 0,
    axis_y_shift = 4,
    bottom = 80,
    center = 17,
    center_horizontal = 1,
    center_vertical = 16,
    clip_horizontal = 8,
    clip_vertical = 128,
    display_clip_horizontal = 16777216,
    display_clip_vertical = 268435456,
    --fill = 119,
    fill_horizontal = 7,
    fill_vertical = 112,
    horizontal_gravity_mask = 7,
    left = 3,
    no_gravity = 0,
    relative_horizontal_gravity_mask = 8388615,
    relative_layout_direction = 8388608,
    right = 5,
    start = 8388611,
    top = 48,
    vertical_gravity_mask = 112,
    ["end"] = 8388613,

    --android:textAlignment
    inherit = 0,
    gravity = 1,
    textStart = 2,
    textEnd = 3,
    textCenter = 4,
    viewStart = 5,
    viewEnd = 6,

    --android:inputType
    none = 0x00000000,
    text = 0x00000001,
    textCapCharacters = 0x00001001,
    textCapWords = 0x00002001,
    textCapSentences = 0x00004001,
    textAutoCorrect = 0x00008001,
    textAutoComplete = 0x00010001,
    textMultiLine = 0x00020001,
    textImeMultiLine = 0x00040001,
    textNoSuggestions = 0x00080001,
    textUri = 0x00000011,
    textEmailAddress = 0x00000021,
    textEmailSubject = 0x00000031,
    textShortMessage = 0x00000041,
    textLongMessage = 0x00000051,
    textPersonName = 0x00000061,
    textPostalAddress = 0x00000071,
    textPassword = 0x00000081,
    textVisiblePassword = 0x00000091,
    textWebEditText = 0x000000a1,
    textFilter = 0x000000b1,
    textPhonetic = 0x000000c1,
    textWebEmailAddress = 0x000000d1,
    textWebPassword = 0x000000e1,
    number = 0x00000002,
    numberSigned = 0x00001002,
    numberDecimal = 0x00002002,
    numberPassword = 0x00000012,
    phone = 0x00000003,
    datetime = 0x00000004,
    date = 0x00000014,
    time = 0x00000024,

    --android:imeOptions
    normal = 0x00000000,
    actionUnspecified = 0x00000000,
    actionNone = 0x00000001,
    actionGo = 0x00000002,
    actionSearch = 0x00000003,
    actionSend = 0x00000004,
    actionNext = 0x00000005,
    actionDone = 0x00000006,
    actionPrevious = 0x00000007,
    flagNoFullscreen = 0x2000000,
    flagNavigatePrevious = 0x4000000,
    flagNavigateNext = 0x8000000,
    flagNoExtractUi = 0x10000000,
    flagNoAccessoryAction = 0x20000000,
    flagNoEnterAction = 0x40000000,
    flagForceAscii = 0x80000000,

}

local scaleType = {
    --android:scaleType
    matrix = 0,
    fitXY = 1,
    fitStart = 2,
    fitCenter = 3,
    fitEnd = 4,
    center = 5,
    centerCrop = 6,
    centerInside = 7,
}

local rules = {
    layout_above = 2,
    layout_alignBaseline = 4,
    layout_alignBottom = 8,
    layout_alignEnd = 19,
    layout_alignLeft = 5,
    layout_alignParentBottom = 12,
    layout_alignParentEnd = 21,
    layout_alignParentLeft = 9,
    layout_alignParentRight = 11,
    layout_alignParentStart = 20,
    layout_alignParentTop = 10,
    layout_alignRight = 7,
    layout_alignStart = 18,
    layout_alignTop = 6,
    layout_alignWithParentIfMissing = 0,
    layout_below = 3,
    layout_centerHorizontal = 14,
    layout_centerInParent = 13,
    layout_centerVertical = 15,
    layout_toEndOf = 17,
    layout_toLeftOf = 0,
    layout_toRightOf = 1,
    layout_toStartOf = 16
}

local types = {
    px = 0,
    dp = 1,
    sp = 2,
    pt = 3,
    ["in"] = 4,
    mm = 5
}

local function checkType(v)
    local n, ty = string.match(v, "^(%-?%d+)(%a%a)$")
    return tonumber(n), types[ty]
end

local function checkPercent(v)
    local n, ty = string.match(v, "^(%-?[%.%d]+)%%([wh])$")
    if ty == nil then
        return nil
    elseif ty == "w" then
        return tonumber(n) * W / 100
    elseif ty == "h" then
        return tonumber(n) * H / 100
    end
end

local function split(s, t)
    local idx = 1
    local l = #s
    return function()
        local i = s:find(t, idx)
        if idx >= l then
            return nil
        end
        if i == nil then
            i = l + 1
        end
        local sub = s:sub(idx, i - 1)
        idx = i + 1
        return sub
    end
end
local function checkint(s)
    local ret = 0
    for n in split(s, "|") do
        if toint[n] then
            ret = ret | toint[n]
        else
            return nil
        end
    end
    return ret
end

local function checkNumber(var)
    if type(var) == "string" then
        if var == "true" then
            return true
        elseif var == "false" then
            return false
        end

        if toint[var] then
            return toint[var]
        end

        local i = checkint(var)
        if i then
            return i
        end

        local p = checkPercent(var)
        if p then
            return p
        end

        local h = string.match(var, "^#(%x+)$")
        if h then
            local c = tonumber(h, 16)
            if c then
                if #h <= 6 then
                    return c - 0x1000000
                elseif #h <= 8 then
                    if c > 0x7fffffff then
                        return c - 0x100000000
                    else
                        return c
                    end
                end
            end
        end

        local n, ty = checkType(var)
        if ty then
            return TypedValue.applyDimension(ty, n, dm)
        end
    end
    -- return var
end

local function getViewClassConstructor(cls, contextObj, attrSet, styleAttr, styleRes)
    local ok, result = pcall(function()
        if styleAttr and styleRes then
            return cls(contextObj, attrSet, styleAttr, styleRes)
        elseif styleAttr then
            return cls(contextObj, attrSet, styleAttr)
        elseif styleRes then
            return cls(contextObj, attrSet, 0, styleRes)
        end
        return nil
    end)
    if ok and result then
        return result
    end
end

local function checkValue(var)
    return tonumber(var) or checkNumber(var) or var
end

local function checkValues(...)
    local vars = { ... }
    for n = 1, #vars do
        vars[n] = checkValue(vars[n])
    end
    return unpack(vars)
end

local function getattr(s)
    return android_R.attr[s]
end

function checkattr(s)
    try
        getattr(s)
    catch(e)
        return e
    end
    return nil
    -[[
    local e, s = pcall(getattr, s)
    if e then
        return s
    end
    return nil
    ]]
end

local function dump2 (t)
    local _t = {}
    table.insert(_t, tostring(t))
    table.insert(_t, "\t{")
    for k, v in pairs(t) do
        if type(v) == "table" then
            table.insert(_t, "\t\t" .. tostring(k) .. "={" .. tostring(v[1]) .. " ...}")
        else
            table.insert(_t, "\t\t" .. tostring(k) .. "=" .. tostring(v))
        end
    end
    table.insert(_t, "\t}")
    t = table.concat(_t, "\n")
    return t
end

local ver = bindClass("android.os.Build").VERSION.SDK_INT;
function setBackground(view, bg)
    if ver < 16 then
        view.setBackgroundDrawable(bg)
    else
        view.setBackground(bg)
    end
end

local function createBehaviorFromString(behaviorString)
    if behaviorString == "@string/bottom_sheet_behavior" then
        return bindClass("com.google.android.material.bottomsheet.BottomSheetBehavior")()
    elseif behaviorString == "@string/side_sheet_behavior" then
        return bindClass("com.google.android.material.sidesheet.SideSheetBehavior")()
    elseif behaviorString == "@string/hide_bottom_view_on_scroll_behavior" then
        return bindClass("com.google.android.material.behavior.HideBottomViewOnScrollBehavior")()
    elseif behaviorString == "@string/hide_view_on_scroll_behavior" then
        return bindClass("com.google.android.material.behavior.HideViewOnScrollBehavior")()
    elseif behaviorString == "@string/appbar_scrolling_view_behavior" then
        return bindClass("com.google.android.material.appbar.AppBarLayout$ScrollingViewBehavior")()
    elseif behaviorString == "@string/searchbar_scrolling_view_behavior" then
        return bindClass("com.google.android.material.search.SearchBar$ScrollingViewBehavior")()
    end
end

local function setattribute(root, view, params, k, v, ids)
    if k == "layout_x" then
        params.x = checkValue(v)
    elseif k == "layout_y" then
        params.y = checkValue(v)
    elseif k == "layout_weight" then
        params.weight = checkValue(v)
    elseif k == "layout_gravity" then
        params.gravity = checkValue(v)
    elseif k == "layout_anchorGravity" then
        safeCall(params, "setAnchorGravity", checkValue(v))
    elseif k == "layout_marginStart" then
        params.setMarginStart(checkValue(v))
    elseif k == "layout_marginEnd" then
        params.setMarginEnd(checkValue(v))
    elseif k == "layout_goneMarginLeft" then
        safeCall(params, "setGoneLeftMargin", checkValue(v))
    elseif k == "layout_goneMarginTop" then
        safeCall(params, "setGoneTopMargin", checkValue(v))
    elseif k == "layout_goneMarginRight" then
        safeCall(params, "setGoneRightMargin", checkValue(v))
    elseif k == "layout_goneMarginBottom" then
        safeCall(params, "setGoneBottomMargin", checkValue(v))
    elseif k == "layout_goneMarginStart" then
        safeCall(params, "setGoneStartMargin", checkValue(v))
    elseif k == "layout_goneMarginEnd" then
        safeCall(params, "setGoneEndMargin", checkValue(v))
    elseif k == "layout_behavior" then
        local behavior = type(v) == "string" and createBehaviorFromString(v) or v
        if behavior then
            params.setBehavior(behavior)
        end
    elseif k == "layout_anchor" then
        local anchorId = ids[v]
        if anchorId then
            params.setAnchorId(anchorId)
        end
    elseif k == "layout_collapseParallaxMultiplier" then
        params.setParallaxMultiplier(checkValue(v))
    elseif k == "layout_collapseMode" then
        params.setCollapseMode(checkValue(v))
    elseif k == "layout_scrollFlags" then
        params.setScrollFlags(checkValue(v))
    elseif rules[k] and (v == true or v == "true") then
        params.addRule(rules[k])
    elseif rules[k] then
        params.addRule(rules[k], ids[v])
    elseif k == "items" then
        --创建列表项目
        if type(v) == "table" then
            if view.adapter then
                view.adapter.addAll(v)
            else
                local adapter = ArrayListAdapter(context, android_R.layout.simple_list_item_1, String(v))
                view.setAdapter(adapter)
            end
        end
    elseif k == "pages" and type(v) == "table" then
        --创建页项目
    elseif k == "onClick" then
        --设置onClick事件接口
    elseif k == "textSize" then
        if tonumber(v) then
            view.setTextSize(tonumber(v))
        elseif type(v) == "string" then
            local n, ty = checkType(v)
            if ty then
                view.setTextSize(ty, n)
            else
                view.setTextSize(v)
            end
        else
            view.setTextSize(v)
        end
    elseif k == "textStyle" then
        if v == "bold" then
            local bold = Typeface.defaultFromStyle(Typeface.BOLD)
            view.setTypeface(bold)
        elseif v == "normal" then
            local normal = Typeface.defaultFromStyle(Typeface.NORMAL)
            view.setTypeface(normal)
        elseif v == "italic" then
            local italic = Typeface.defaultFromStyle(Typeface.ITALIC)
            view.setTypeface(italic)
        elseif v == "italic|bold" or v == "bold|italic" then
            local bold_italic = Typeface.defaultFromStyle(Typeface.BOLD_ITALIC)
            view.setTypeface(bold_italic)
        end
    elseif k == "textAppearance" then
        view.setTextAppearance(context, checkattr(v))
    elseif k == "ellipsize" then
        view.setEllipsize(TruncateAt[string.upper(v)])
    elseif k == "url" then
        view.loadUrl(url)
    elseif k == "src" then
        this.loadImage(v, view)
    elseif k == "scaleType" then
        view.setScaleType(scaleTypes[scaleType[v]])
    elseif k == "textColor" then
        safeCall(view, "setTextColor", checkValue(v))
    elseif k == "hintTextColor" then
        safeCall(view, "setHintTextColor", checkValue(v))
    elseif k == "textAppearance" then
        safeCall(view, "setTextAppearance", context, checkValue(v))
    elseif k == "textAlignment" then
        safeCall(view, "setTextAlignment", checkValue(v))
    elseif k == "inputType" then
        safeCall(view, "setInputType", checkValue(v))
    elseif k == "imeOptions" then
        safeCall(view, "setImeOptions", checkValue(v))
    elseif k == "maxLines" then
        safeCall(view, "setMaxLines", checkValue(v))
    elseif k == "minLines" then
        safeCall(view, "setMinLines", checkValue(v))
    elseif k == "singleLine" then
        safeCall(view, "setSingleLine", v == true or v == "true")
    elseif k == "backgroundResource" then
        safeCall(view, "setBackgroundResource", checkValue(v))
    elseif k == "backgroundDrawable" then
        safeCall(view, "setBackground", v)
    elseif k == "paddingStart" then
        view.setPaddingRelative(checkValue(v), view.getPaddingTop(), view.getPaddingEnd(), view.getPaddingBottom())
    elseif k == "paddingEnd" then
        view.setPaddingRelative(view.getPaddingStart(), view.getPaddingTop(), checkValue(v), view.getPaddingBottom())
    elseif k == "paddingTop" then
        view.setPadding(view.getPaddingLeft(), checkValue(v), view.getPaddingRight(), view.getPaddingBottom())
    elseif k == "paddingBottom" then
        view.setPadding(view.getPaddingLeft(), view.getPaddingTop(), view.getPaddingRight(), checkValue(v))
    elseif k == "paddingLeft" then
        view.setPadding(checkValue(v), view.getPaddingTop(), view.getPaddingRight(), view.getPaddingBottom())
    elseif k == "paddingRight" then
        view.setPadding(view.getPaddingLeft(), view.getPaddingTop(), checkValue(v), view.getPaddingBottom())
    elseif k == "background" then
        if type(v) == "string" then
            if v:find("^%?") then
                view.setBackgroundResource(getAttrIdentifier(v:sub(2, -1)))
            elseif v:find("^#") then
                view.setBackgroundColor(checkNumber(v))
            elseif rawget(root, v) or rawget(_G, v) then
                v = rawget(root, v) or rawget(_G, v)
                if type(v) == "function" then
                    setBackground(view, LuaDrawable(v))
                elseif type(v) == "userdata" then
                    setBackground(view, v)
                end
            else
                if (not v:find("^/")) and luadir then
                    v = luadir .. v
                end
                if v:find("%.9%.png") then
                    setBackground(view, NineBitmapDrawable(loadbitmap(v)))
                else
                    setBackground(view, BitmapDrawable(loadbitmap(v)))
                end
            end
        elseif type(v) == "userdata" then
            setBackground(view, v)
        elseif type(v) == "number" then
            view.setBackgroundColor(v)
        end
    elseif k == "password" and (v == "true" or v == true) then
        view.setInputType(0x81)
    elseif type(k) == "string" and not (k:find("layout_")) and not (k:find("padding")) and k ~= "style" and k ~= "theme" and k ~= "styleAttr" and k ~= "styleRes" then
        --设置属性
        local rawKey = k
        k = string.gsub(k, "^(%w)", function(s)
            return string.upper(s)
        end)
        if k == "Text" or k == "Title" or k == "Subtitle" then
            if not safeCall(view, "set" .. k, v) then
                safeCall(view, "set" .. rawKey, v)
            end
        else
            local value = checkValue(v)
            if not safeCall(view, "set" .. k, value) then
                if not safeCall(view, rawKey, value) then
                    view[rawKey] = value
                end
            end
        end
    end
end

LayoutHelperActivity.applyLayoutAttribute = function(root, view, k, v)
    local params = view.getLayoutParams()
    setattribute(root or _G, view, params, k, v, ids)
    if params then
        view.setLayoutParams(params)
    end
    view.invalidate()
end

local function setMiniSize(view)
    view.setMinimumHeight(checkValue("18dp"))
    view.setMinimumWidth(checkValue("18dp"))
end

local function copytable(f, t, b)
    for k, v in pairs(f) do
        if k == 1 then
        elseif b or t[k] == nil then
            t[k] = v
        end
    end
end

local function setstyle(c, t, root, view, params, ids)
    local mt = getmetatable(t)
    if not mt or not mt.__index then
        return
    end
    local m = mt.__index
    if c[m] then
        return
    end
    c[m] = true
    for k, v in pairs(m) do
        if not rawget(c, k) then
            pcall(setattribute, root, view, params, k, v, ids)
        end
        c[k] = true
    end
    setstyle(c, m, root, view, params, ids)
end

local function loadlayout(t, root, group, p)
    if type(t) == "string" then
        p = t
        t = require(t)
    elseif type(t) ~= "table" then
        error(string.format("loadlayout error: Fist value Must be a table, checked import layout.", 0))
    end
    root = root or _G
    local view
    local theme = resolveStyleField(t.theme, "theme")
    local styleAttr = resolveStyleField(t.styleAttr, "styleAttr")
    local styleRes = resolveStyleField(t.styleRes, "styleRes")
    local style = nil
    local legacyStyleType = nil

    if t.style then
        style, legacyStyleType = resolveLegacyStyle(t.style)
        if legacyStyleType == "table" then
            setmetatable(t, { __index = style })
            style = nil
        end
    end
    if not t[1] then
        error(string.format("loadlayout error: First value Must be a Class, checked import package.\n\tat %s", dump2(t)), 0)
    end

    local viewContext = context
    if theme then
        viewContext = ContextThemeWrapper(context, theme)
    end

    if styleAttr and styleRes then
        view = getViewClassConstructor(t[1], viewContext, nil, styleAttr, styleRes)
    end
    if not view and styleAttr then
        view = getViewClassConstructor(t[1], viewContext, nil, styleAttr, nil)
    end
    if not view and styleRes then
        view = getViewClassConstructor(t[1], viewContext, nil, nil, styleRes)
    end
    if not view and style then
        view = getViewClassConstructor(t[1], viewContext, nil, style, nil)
    end
    if not view then
        view = t[1](viewContext) --创建view
    end
    if p then
        view.onTouch = function(v, e)
            if e.getAction() == MotionEvent.ACTION_DOWN then
                print("import from \"" .. p .. "\"")
                return true
            end
        end
    else
        view.setTag(t)
        if group and group == AbsoluteLayout then
            view.onTouch = onAbsoluteLayoutChildViewTouch
        else
            view.onTouch = onViewTouch
        end
        --view.onClick = onClick
    end
    local vgw, vgh
    try
    setMiniSize(view)
end

if view.getBackground() == nil then
    local gd = GradientDrawable()
    gd.setColor(android_R.color.transparent)
    if luajava.instanceof(view, ViewGroup) then
        gd.setStroke(2, ColorAccent, 5, 5)
    else
        gd.setStroke(2, ColorPrimary, 5, 5)
    end
    gd.setGradientRadius(700)
    gd.setGradientType(1)
    setBackground(view, gd)
end

local params = ViewGroup.LayoutParams(checkValue(t.layout_width) or -2, checkValue(t.layout_height) or -2) --设置layout属性
if group then
    params = group.LayoutParams(params)
end

--设置layout_margin属性
if t.layout_margin or t.layout_marginStart or t.layout_marginEnd or t.layout_marginLeft or t.layout_marginTop or t.layout_marginRight or t.layout_marginBottom then
    params.setMargins(checkValues(t.layout_marginLeft or t.layout_margin or 0, t.layout_marginTop or t.layout_margin or 0, t.layout_marginRight or t.layout_margin or 0, t.layout_marginBottom or t.layout_margin or 0))
end

--设置padding属性
if t.padding or t.paddingLeft or t.paddingTop or t.paddingRight or t.paddingBottom then
    view.setPadding(checkValues(t.paddingLeft or t.padding or 0, t.paddingTop or t.padding or 0, t.paddingRight or t.padding or 0, t.paddingBottom or t.padding or 0))
end
if t.paddingStart or t.paddingEnd then
    view.setPaddingRelative(checkValues(t.paddingStart or t.padding or 0, t.paddingTop or t.padding or 0, t.paddingEnd or t.padding or 0, t.paddingBottom or t.padding or 0))
end

local c = {}
setmetatable(c, { __index = t })
setstyle(c, t, root, view, params, ids)

for k, v in pairs(t) do
    if tonumber(k) and (type(v) == "table" or type(v) == "string") then
        --创建子view
        if luajava.instanceof(view, AdapterView) then
            if type(v) == "string" then
                v = require(v)
            end
            view.adapter = LuaAdapter(context, v)
        else
            view.addView(loadlayout(v, root, t[1]))
        end
    elseif k == "id" then
        --创建view的全局变量
        rawset(root, v, view)
        id = id + 1
        view.setId(id)
        ids[v] = id
    else
        local e, s = pcall(setattribute, root, view, params, k, v, ids)
        if not e then
            local _, i = s:find(":%d+:")
            s = s:sub(i or 1, -1)
            error(string.format("loadlayout error %s \n\tat %s\n\tat  key=%s value=%s\n\tat %s", s, view.toString(), k, v, dump2(t)), 0)
        end
    end
end

--if group then
--group.addView(view,params)
--else
view.setLayoutParams(params)
return view
--end
end

return loadlayout

