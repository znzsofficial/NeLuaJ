-- Editor adapter contract tests with an explicit production-loader boundary double.
-- LayoutPreviewTest on the JVM separately executes real LuaLayout.loadDecorated;
-- neither test proves Android rendering, touch dispatch or Material theme visuals.
local assets = ASSETS or "app/src/main/assets/"
local function class(name)
    return setmetatable({ name = name }, { __call = function(_, ...) return { ... } end })
end
local ViewGroup, AbsoluteLayout = class("ViewGroup"), class("AbsoluteLayout")
AbsoluteLayout.LayoutParams = class("AbsoluteLayout.LayoutParams")
local TextView = class("TextView")
local last, loads = nil, 0
local function view()
    local state, v = {}, {}
    v.setTag = function(value) state.tag = value end
    v.getTag = function() return state.tag end
    v.setMinimumHeight = function(value) state.minHeight = value end
    v.setMinimumWidth = function(value) state.minWidth = value end
    v.getBackground = function() return state.background end
    v.setBackground = function(value) state.background = value end
    v.state = state
    return v
end
local function drawable()
    local d = {}
    for _, method in ipairs({ "setColor", "setStroke", "setGradientRadius", "setGradientType" }) do
        d[method] = function() end
    end
    return d
end
local loaderClass = setmetatable({}, { __call = function()
    local loader = {}
    loader.loadDecorated = function(layout, env, hooks, params)
        loads = loads + 1
        last = { layout = layout, hooks = hooks, params = params, env = env }
        local function inflate(t)
            local v = view()
            hooks.onCreated(v, t)
            if t.id then env[t.id] = v end
            -- Deliberately emulate only lifecycle, not property interpretation.
            for key, child in pairs(t) do
                if type(key) == "number" and key > 1 and type(child) == "table" then inflate(child) end
            end
            if t.pages then for _, page in ipairs(t.pages) do inflate(page) end end
            if t.pagesWithTitle then for _, page in ipairs(t.pagesWithTitle[1]) do inflate(page) end end
            hooks.onLoaded(v, t)
            return v
        end
        return inflate(layout)
    end
    return loader
end })
local resources = {
    getDisplayMetrics = function() return { density = 2 } end,
    getIdentifier = function(name, kind)
        if name == "Widget.Test" and kind == "style" then return 42 end
        return 0
    end,
}
activity = { getResources = function() return resources end, getPackageName = function() return "test" end }
ColorUtil = { getColorAccent = function() return 123 end }
ColorPrimary = 456
onViewTouch = function() return "select foreground" end
onAbsoluteLayoutChildViewTouch = function() return "drag and edit source coordinates" end
res = { drawable = { lua_icon = "resolved-project-drawable" } }
luajava = {
    bindClass = function(name)
        if name == "com.androlua.LuaLayout" then return loaderClass end
        if name == "android.view.ViewGroup" then return ViewGroup end
        if name == "android.widget.AbsoluteLayout" then return AbsoluteLayout end
        if name == "android.graphics.drawable.GradientDrawable" then return drawable end
        if name == "com.androlua.LuaDrawable" then return function(fn) return { callback = fn } end end
        if name == "java.io.File" then return function(path) return { isFile = function()
            return path == "/project/res/drawable/icon.png" or path == "/project/res/drawable/lua_icon.lua"
        end } end end
        if name == "android.view.MotionEvent" then return { ACTION_DOWN = 0 } end
        return {}
    end,
    instanceof = function() return false end,
}
LayoutHelperActivity = { data = { this_project_lua_dir = "/project/", current_view = "" } }
local loadPreview = assert(loadfile(assets .. "activities/layouthelper/LayoutHelperActivity$loadlayout.lua"))()
local click = function() error("project onClick must not replace editor gestures") end
local child = { TextView, id = "title", text = "hello", layout_x = "1.5dp", onClick = click, src = "images/a.png" }
local root = { AbsoluteLayout, id = "root", child }
local bindings = {}
local result = loadPreview(root, bindings)
assert(loads == 1 and last.layout ~= root and last.layout[2] ~= child)
assert(last.layout[2].text == "hello" and last.layout[2].layout_x == "1.5dp", "raw attributes belong to LuaLayout")
assert(last.layout[2].src == "/project/images/a.png" and child.src == "images/a.png")
assert(last.layout[2].onClick == nil and child.onClick == click)
assert(result.getTag() == root and bindings.title.getTag() == child)
assert(LayoutHelperActivity.data.previewNodes[bindings.title] == child)
assert(LayoutHelperActivity.data.previewViews[child] == bindings.title)
assert(bindings.title.onTouch == onAbsoluteLayoutChildViewTouch and result.onTouch == onViewTouch)
assert(bindings.title.state.minHeight == 36 and result.state.background)
assert(last.hooks.layoutParamsFactory(AbsoluteLayout.LayoutParams)(10, 20)[4] == 0)
assert(last.hooks.layoutParamsFactory({}) == nil)
assert(LayoutHelperActivity.applyLayoutAttribute == nil, "edits must not use the legacy attribute interpreter")
print("PASS actual editor module delegates full layout tree and preserves mappings/gestures")

LayoutHelperActivity.data.current_view = bindings.title
child.text = "edited"
local bindings2 = {}
loadPreview(root, bindings2)
assert(loads == 2 and last.layout[2].text == "edited")
assert(LayoutHelperActivity.data.current_view == bindings2.title and bindings2.title ~= bindings.title)
assert(bindings2.title.getTag() == child)
child.text = nil
loadPreview(root, {})
assert(last.layout[2].text == nil, "removed attributes must not linger in the runtime copy")
print("PASS reinflation keeps source identity and rebinds selection after edit/removal")

package.loaded.preview_import = { TextView, id = "imported" }
local importBindings = {}
loadPreview({ ViewGroup, "preview_import" }, importBindings)
assert(importBindings.imported.getTag() == nil)
assert(importBindings.imported.onTouch ~= onViewTouch, "import roots stay read-only")
assert(importBindings.imported.onTouch({}, { getAction = function() return 0 end }) == true)
local style = { textSize = "17sp", textColor = "#123456" }
local styled = { TextView, style = style, textSize = "19sp" }
loadPreview(styled, {})
assert(last.layout.textSize == "19sp" and last.layout.textColor == "#123456" and last.layout.style == nil)
assert(getmetatable(styled) == nil and styled.textColor == nil, "preview may not mutate source style metadata")
local themed = { TextView, styleRes = "@style/Widget.Test", src = "@drawable/icon" }
loadPreview(themed, {})
assert(last.layout.styleRes == 42 and last.layout.src == "/project/res/drawable/icon.png")
assert(themed.styleRes == "@style/Widget.Test" and themed.src == "@drawable/icon")
loadPreview({ TextView, src = "@drawable/lua_icon" }, {})
assert(last.layout.src == res.drawable.lua_icon)
print("PASS imported roots, table styles and project resources retain editor compatibility")

local page = { TextView, id = "page" }
local pageBindings = {}
loadPreview({ ViewGroup, pages = { page }, pagesWithTitle = { { page }, { "Title" } } }, pageBindings)
assert(pageBindings.page.getTag() == page and last.layout.pages[1] ~= page)
local cyclic = { ViewGroup }
cyclic[2] = cyclic
assert(not pcall(loadPreview, cyclic, {}))
print("PASS pager tables are decorated and cyclic source fails without rewriting source")
print("ALL-PASS")
