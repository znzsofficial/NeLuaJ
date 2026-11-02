-- User-invoked editor preview, NOT an execution sandbox. LuaLayout owns inflation,
-- property parsing, IDs, adapters and LayoutParams; only editor decoration lives here.
local bindClass = luajava.bindClass
local LuaLayout = bindClass "com.androlua.LuaLayout"
local ViewGroup = bindClass "android.view.ViewGroup"
local AbsoluteLayout = bindClass "android.widget.AbsoluteLayout"
local GradientDrawable = bindClass "android.graphics.drawable.GradientDrawable"
local LuaDrawable = bindClass "com.androlua.LuaDrawable"
local File = bindClass "java.io.File"
local MotionEvent = bindClass "android.view.MotionEvent"
local context = activity or service
local accent = ColorUtil.getColorAccent()
local density = context.getResources().getDisplayMetrics().density

-- Direct setters used to have a second, subtly different attribute interpreter.
-- Reinflate after edits/removals instead, so constructor fields, padding and defaults
-- all use production semantics. The original table remains the editable source.
LayoutHelperActivity.applyLayoutAttribute = nil

local function projectPath(path)
    if path:sub(1, 1) == "/" or path:match("^%a[%w+.-]*:") then return path end
    return LayoutHelperActivity.data.this_project_lua_dir:gsub("[/\\]+$", "") .. "/" .. path
end

local function resourceId(value, kind)
    if type(value) ~= "string" then return nil end
    local name = value:match("^%s*(.-)%s*$")
    name = name:gsub("^android%.R%." .. kind .. "%.", "")
        :gsub("^R%." .. kind .. "%.", "")
        :gsub("^[@?]android:" .. kind .. "/", "")
        :gsub("^[@?]" .. kind .. "/", ""):gsub("^%?", "")
    local resources = context.getResources()
    local id = resources.getIdentifier(name, kind, context.getPackageName())
    if id == 0 then id = resources.getIdentifier(name, kind, "android") end
    if id == 0 then id = resources.getIdentifier(name:gsub("%.", "_"), kind, context.getPackageName()) end
    return id ~= 0 and id or nil
end

local function styleValue(value, key)
    if type(value) ~= "string" then return value end
    if tonumber(value) then return tonumber(value) end
    local kind = (key == "styleAttr" or value:sub(1, 1) == "?") and "attr" or "style"
    return resourceId(value, kind) or value
end

local function projectDrawable(name)
    -- The editor activity's LuaContext points at its own assets, not the edited
    -- project. Resolve project-relative files here; LuaLayout still loads the image.
    for _, extension in ipairs({ ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp" }) do
        local path = projectPath("res/drawable/" .. name .. extension)
        if File(path).isFile() then return path end
    end
    if File(projectPath("res/drawable/" .. name .. ".lua")).isFile() then
        -- Same explicit project drawable execution already exposed by editor res.
        return res.drawable[name]
    end
end

local function imageValue(value, background, env)
    if type(value) ~= "string" then return value end
    if background then
        local named = rawget(env, value) or rawget(_G, value)
        if type(named) == "function" then return LuaDrawable(named) end
        if type(named) == "userdata" then return named end
    end
    local name = value:match("^@drawable/(.+)$") or value:match("^drawable/(.+)$")
    if name then
        -- Let the common loader resolve packaged resources before project files.
        local id = resourceId(name, "drawable") or resourceId("ic_" .. name, "drawable")
        if id then
            if background then return context.getResources().getDrawable(id, context.getTheme()) end
            return value
        end
        return projectDrawable(name) or value
    end
    local androidName = value:match("^@android:drawable/(.+)$")
    if background and androidName then
        local id = context.getResources().getIdentifier(androidName, "drawable", "android")
        if id ~= 0 then return context.getResources().getDrawable(id, context.getTheme()) end
    end
    if value:sub(1, 1) == "#" or value:sub(1, 1) == "?" or value:sub(1, 1) == "@" then return value end
    return projectPath(value)
end

local function loadlayout(source, root, group, importedPath)
    if LayoutHelperActivity.useLegacyLayoutLoader then
        return require("activities.layouthelper.LayoutHelperActivity$legacyloadlayout")(source, root, group, importedPath)
    end
    LayoutHelperActivity.applyLayoutAttribute = nil
    local env = root or _G
    local loader = LuaLayout(context)
    local nodes, views, metadata, visiting = {}, {}, {}, {}

    local prepare
    local function preparePages(pages)
        local result = {}
        for key, page in pairs(pages) do
            if type(key) == "number" and (type(page) == "table" or type(page) == "string") then
                result[key] = prepare(page)
            else
                result[key] = page
            end
        end
        return result
    end

    prepare = function(original, parentClass, path)
        if type(original) == "string" then
            path = original
            original = require(original)
        end
        if type(original) ~= "table" then error("loadlayout: expected a layout table or module name", 0) end
        if visiting[original] then error("loadlayout: cyclic layout table", 0) end
        visiting[original] = true
        local runtime = {}
        -- Flatten legacy table-style inheritance into a private runtime copy. Never
        -- attach a metatable to or rewrite the user's source table while previewing.
        local inherited = {}
        local function inherit(t)
            if inherited[t] then error("loadlayout: cyclic table style", 0) end
            inherited[t] = true
            local mt = getmetatable(t)
            if type(mt) == "table" and type(mt.__index) == "table" then inherit(mt.__index) end
            local style = rawget(t, "style")
            if type(style) == "string" and styleValue(style, "style") == style then
                local ok, styleTable = pcall(require, style)
                if ok and type(styleTable) == "table" then style = styleTable end
            end
            if type(style) == "table" then inherit(style) end
            for key, value in pairs(t) do
                if key ~= "style" or type(style) ~= "table" then runtime[key] = value end
            end
            inherited[t] = nil
        end
        inherit(original)
        if not runtime[1] then error("loadlayout: first layout value must be a View class", 0) end
        metadata[runtime] = { source = original, parentClass = parentClass, path = path }
        for key, value in pairs(runtime) do
            if type(key) == "number" and key > 1 and (type(value) == "table" or type(value) == "string") then
                runtime[key] = prepare(value, runtime[1])
            elseif key == "style" or key == "styleAttr" or key == "styleRes" or key == "theme" then
                runtime[key] = styleValue(value, key)
            elseif key == "src" or key == "background" then
                runtime[key] = imageValue(value, key == "background", env)
            elseif key == "textAppearance" then
                runtime[key] = resourceId(value, "style") or value
            elseif key == "backgroundResource" then
                local name = type(value) == "string" and value:match("^@[%w_]+/(.+)$") or value
                runtime[key] = resourceId(name, "drawable") or value
            elseif key == "pages" and type(value) == "table" then
                runtime[key] = preparePages(value)
            elseif key == "pagesWithTitle" and type(value) == "table" then
                runtime[key] = { preparePages(value[1]), value[2] }
            end
        end
        -- Editor gestures take precedence over project click/touch handlers, as in
        -- the old preview. Runtime handlers remain unchanged in ordinary LuaLayout.
        runtime.onClick = nil
        runtime.onTouch = nil
        if runtime.password == true or runtime.password == "true" then runtime.inputType = 0x81 end
        runtime.password = nil
        visiting[original] = nil
        return runtime
    end

    local selected = LayoutHelperActivity.data.current_view
    local selectedSource = selected and selected ~= "" and selected.getTag() or nil
    local runtime = prepare(source, group, importedPath)
    local hooks = {
        layoutParamsFactory = function(paramsClass)
            -- Android AbsoluteLayout.LayoutParams has no (width, height) ctor.
            -- Keep its drag/resize fields, but let production apply x/y/dimensions.
            if paramsClass == AbsoluteLayout.LayoutParams then
                return function(width, height)
                    return AbsoluteLayout.LayoutParams(width, height, 0, 0)
                end
            end
        end,
        onCreated = function(view)
            -- Set before production attributes so explicit minWidth/minHeight win.
            view.setMinimumHeight(18 * density)
            view.setMinimumWidth(18 * density)
            if view.getBackground() == nil then
                local outline = GradientDrawable()
                outline.setColor(0)
                outline.setStroke(2, luajava.instanceof(view, ViewGroup) and accent or ColorPrimary, 5, 5)
                outline.setGradientRadius(700)
                outline.setGradientType(1)
                view.setBackground(outline)
            end
        end,
        onLoaded = function(view, table)
            local node = metadata[table]
            if not node then return end
            if node.path then
                view.setTag(nil)
                view.onTouch = function(_, event)
                    if event.getAction() == MotionEvent.ACTION_DOWN then
                        print('import from "' .. node.path .. '"')
                        return true
                    end
                end
            else
                -- Tag is deliberately reserved for editor source identity. Mapping
                -- is installed after properties so a project tag cannot erase it.
                view.setTag(node.source)
                nodes[view] = node.source
                views[node.source] = view
                if node.parentClass == AbsoluteLayout then
                    view.onTouch = onAbsoluteLayoutChildViewTouch
                else
                    view.onTouch = onViewTouch
                end
            end
        end,
    }
    local result
    if group then
        result = loader.loadDecorated(runtime, env, hooks, group.LayoutParams)
    else
        result = loader.loadDecorated(runtime, env, hooks)
    end
    -- Publish only a completed generation. Rebind selection after edits/reinflation.
    local data = LayoutHelperActivity.data
    data.previewLoader = loader
    data.previewBindings = env
    data.previewNodes = nodes
    data.previewViews = views
    data.current_view = views[selectedSource] or result
    return result
end

return loadlayout
