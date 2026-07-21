local res = res
local table = table
local TabUtil = require "mods.utils.TabUtil"
local MagnifierManager = require "mods.utils.MagnifierManager"
local _M1 = require "mods.utils.EditorUtil$1"
local ActionMode = bindClass "androidx.appcompat.view.ActionMode"
local MotionEvent = bindClass "android.view.MotionEvent"
local View = bindClass "android.view.View"
local File = bindClass "java.io.File"
local Color = bindClass "android.graphics.Color"
local LuaCodeMinimapView = bindClass "com.androlua.LuaCodeMinimapView"
local _M = {}
_M.last_history = {}
_M.fromRecy = false

local _clipboardActionMode = nil
local GONE = View.GONE
local VISIBLE = View.VISIBLE

local function isSharedTruthy(value)
    return value == true or value == "true" or value == 1
end

local function isMinimapEnabled()
    return isSharedTruthy(this.getSharedData("code_minimap", true))
end

local function buildMinimapConfig(editor)
    local data = this.sharedData
    local cfg = LuaCodeMinimapView.MinimapConfig()
    cfg.lineHeight = 2.2
    cfg.charWidthAscii = 1.05
    cfg.verticalGap = 0.55
    cfg.paddingLeft = 3
    -- 悬浮叠层：面板背景默认全透明（透出编辑器代码）
    cfg.backgroundColor = Color.argb(0, 0, 0, 0)
    cfg.outsideDimColor = Color.argb(0, 0, 0, 0)
    -- MinimapBg = 缩略图面板背景（可选）
    if data["MinimapBg"] then
        pcall(function()
            cfg.backgroundColor = Color.parseColor(data["MinimapBg"])
        end)
    end
    -- MinimapMask = 编辑器可视区域指示色（maskColor，不是 background）
    -- 默认半透明浅蓝
    cfg.maskColor = Color.argb(0x28, 0x21, 0x96, 0xF3)
    if data["MinimapMask"] then
        pcall(function()
            cfg.maskColor = Color.parseColor(data["MinimapMask"])
        end)
    end
    -- 代码色条不透明度 0–255，默认 200
    cfg.codeAlpha = 200
    do
        local raw = this.getSharedData("code_minimap_alpha", nil)
        local n = tonumber(raw)
        if n then
            n = math.floor(n + 0.5)
            if n < 0 then n = 0 end
            if n > 255 then n = 255 end
            cfg.codeAlpha = n
        end
    end
    local function parseOr(key, fallback)
        local raw = data[key]
        if not raw then return fallback end
        local ok, c = pcall(Color.parseColor, raw)
        if ok then return c end
        return fallback
    end
    cfg.colorDefault = parseOr("BaseWord", Color.argb(255, 0x44, 0x77, 0xe0))
    cfg.colorKeyword = parseOr("KeyWord", Color.argb(255, 0xb4, 0x00, 0x2d))
    cfg.colorString = parseOr("String", Color.argb(255, 0xc2, 0x18, 0x5b))
    cfg.colorComment = parseOr("Comment", Color.argb(255, 0x71, 0x78, 0x7E))
    cfg.colorNumber = parseOr("UserWord", Color.argb(255, 0x5c, 0x6b, 0xc0))
    cfg.colorId = parseOr("Global", Color.argb(255, 0x68, 0x9f, 0x38))
    cfg.tileHeightPx = 1024
    cfg.maxTileCount = 8
    if editor then
        pcall(function()
            local size = editor.getTextSize()
            if size and size > 0 then
                cfg.charWidthAscii = math.max(0.7, size / 30)
            end
        end)
    end
    return cfg
end

local function readMinimapScale()
    local v = this.getSharedData("code_minimap_scale", 1.0)
    local n = tonumber(v)
    if not n or n ~= n then return 1.0 end
    if n < 0.55 then return 0.55 end
    if n > 2.8 then return 2.8 end
    return n
end

function _M.refreshMinimap(full)
    if not mCodeMinimap then return end
    if not isMinimapEnabled() then
        mCodeMinimap.setVisibility(GONE)
        if minimap_divider then minimap_divider.setVisibility(GONE) end
        pcall(function() mCodeMinimap.detachEditor() end)
        return
    end
    mCodeMinimap.setVisibility(VISIBLE)
    -- 悬浮叠层：不要分割线
    if minimap_divider then minimap_divider.setVisibility(GONE) end
    pcall(function()
        mCodeMinimap.setBackgroundColor(0)
        mCodeMinimap.setClickable(true)
        mCodeMinimap.bringToFront()
    end)
    mCodeMinimap.configure(buildMinimapConfig(mLuaEditor))
    mCodeMinimap.setScale(readMinimapScale())
    mCodeMinimap.setScaleListener(LuaCodeMinimapView.ScaleListener {
        onScaleChanged = function(scale)
            this.setSharedData("code_minimap_scale", scale)
        end
    })
    mCodeMinimap.attachToEditor(mLuaEditor)
    if full then
        mCodeMinimap.scheduleCodeRefresh(0)
    else
        mCodeMinimap.scheduleCodeRefresh(120)
    end
    mCodeMinimap.syncVisibleRangeFromEditor(false)
end

local function getActionMode(view)
    return ActionMode.Callback {
        onCreateActionMode = function(mode, menu)
            _clipboardActionMode = mode
            mode.setTitle(android.R.string.selectTextMode)
            local array = activity.getTheme().obtainStyledAttributes({
                android.R.attr.actionModeSelectAllDrawable,
                android.R.attr.actionModeCutDrawable,
                android.R.attr.actionModeCopyDrawable,
                android.R.attr.actionModePasteDrawable
            })
            menu.add(0, 0, 0, android.R.string.selectAll)
                .setShowAsAction(2)--MenuItem.SHOW_AS_ACTION_ALWAYS
                .setIcon(array.getResourceId(0, 0))
            menu.add(0, 1, 0, android.R.string.cut)
                .setShowAsAction(2)
                .setIcon(array.getResourceId(1, 0))
            menu.add(0, 2, 0, android.R.string.copy)
                .setShowAsAction(2)
                .setIcon(array.getResourceId(2, 0))
            menu.add(0, 3, 0, android.R.string.paste)
                .setShowAsAction(2)
                .setIcon(array.getResourceId(3, 0))
            array.recycle()
            return true
        end,
        onActionItemClicked = function(mode, item)
            if item.getItemId() == 0 then
                view.selectAll()
            elseif item.getItemId() == 1 then
                view.cut()
                mode.finish()
            elseif item.getItemId() == 2 then
                view.copy()
                mode.finish()
            elseif item.getItemId() == 3 then
                view.paste()
                mode.finish()
            end
            return false
        end,
        onDestroyActionMode = function(mode)
            view.selectText(false)
            _clipboardActionMode = nil
        end,
    }
end

local function resetPageTitle(path)
  --print"改变标题"
  try
    local pattern = Bean.Path.app_root_pro_dir .. "(.*)/"
    local subfolder = string.match(path, pattern).."/"
    local projectName = subfolder:match("/(.-)/")
    Bean.Project.this_project = projectName
    activity.setTitle(projectName)
    catch
    Bean.Project.this_project = ""
    activity.setTitle("")
    finally
    activity.getSupportActionBar().setSubtitle(File(path).getName())
  end
end

local function initTab()
    -- TabLayout.OnTabSelectedListener
    mTab.addOnTabSelectedListener({
        onTabUnselected = function(tab)
        end;
        onTabSelected = function(tab)
            if not tab.tag.first then
                --print("Tab选择事件")
                _M.save()
                local path = tab.tag.path
                -- 更新当前文件
                PathManager.updateFile(path)
                -- 载入文件
                _M.load(path)
            else
                tab.tag.first = nil
                local path = tab.tag.path
                -- 更新当前文件
                PathManager.updateFile(path)
                -- 载入文件
                resetPageTitle(path)
                --print"第一次被选择的tab，editor读取"
                mLuaEditor.setText(LuaFileUtil.read(path))
                if mCodeMinimap and isMinimapEnabled() then
                    mCodeMinimap.scheduleCodeRefresh(60)
                    mCodeMinimap.syncVisibleRangeFromEditor(false)
                end
            end
        end;
        onTabReselected = function(tab)
            --print"tab再次选择"
        end;
    })
end

function _M.setSelection(i, editor)
    editor = editor or mLuaEditor
    editor.setSelection(i)
end

function _M.save(path, str, editor)
    editor = editor or mLuaEditor
    path = path or Bean.Path.this_file
    -- 如果没有传入文本
    if not str then
        str = tostring(editor.getText())
        -- 如果编辑器文本为空
        if #str == 0 then
            local originTitle = this.supportActionBar.subtitle
            -- 显示提示
            this.supportActionBar.subtitle = res.string.empty_file_saved
            this.delay(1000, function()
                this.supportActionBar.subtitle = originTitle
            end)
        end
    end

    if Bean.Path.this_file == "" then
        return
    elseif str == LuaFileUtil.read(path) then
        return "same"
    end

    local selectionEnd = editor.getSelectionEnd()
    _M.last_history[path] = selectionEnd
    this.setSharedData("lastFile", path)
    this.setSharedData("lastSelect", selectionEnd)
    -- 检查备份文件夹
    checkBackup()
    -- 保存备份
    local _path = path:gsub(Bean.Path.app_root_pro_dir, "")
    local backups = Bean.Path.backup_dir .. "/" .. os.date("%Y-%m-%d") .. "/" .. os.date("%H_%M") .. _path
    local backup_file = File(backups)
    -- 每分钟保存一次
    if not backup_file.exists() then
        File(backup_file.getParent()).mkdirs()
        LuaFileUtil.create(backups, str)
    end
    -- 返回写入结果
    return LuaFileUtil.write(path, str)
end

function _M.setHighLight(view)
    local data = this.sharedData
    -- 默认色用 Color.argb，避免 0xff...... 在 LuaJ 中传 Java 出错
    view.basewordColor = data["BaseWord"] and Color.parseColor(data["BaseWord"]) or Color.argb(255, 0x44, 0x77, 0xe0)
    view.keywordColor = data["KeyWord"] and Color.parseColor(data["KeyWord"]) or Color.argb(255, 0xb4, 0x00, 0x2d)
    view.stringColor = data["String"] and Color.parseColor(data["String"]) or Color.argb(255, 0xc2, 0x18, 0x5b)
    view.userwordColor = data["UserWord"] and Color.parseColor(data["UserWord"]) or Color.argb(255, 0x5c, 0x6b, 0xc0)
    view.commentColor = data["Comment"] and Color.parseColor(data["Comment"]) or Color.argb(255, 0x71, 0x78, 0x7e)
    view.globalColor = data["Global"] and Color.parseColor(data["Global"]) or Color.argb(255, 0x68, 0x9f, 0x38)
    view.localColor = data["Local"] and Color.parseColor(data["Local"]) or Color.argb(255, 0xb4, 0xb4, 0x84)
    view.upvalColor = data["Upval"] and Color.parseColor(data["Upval"]) or Color.argb(255, 0x80, 0x80, 0xc0)
end

function _M.init()
    -- 初始化放大镜
    MagnifierManager.initMagnifier(mLuaEditor);
    _M1.init()
    -- 初始化Tab
    initTab();

    -- 设置高亮
    _M.setHighLight(mLuaEditor)

    --设置字体
    mLuaEditor.setTypeface(res.font.code)

    local function isMagnifierEnabled()
        return isSharedTruthy(this.getSharedData("editor_magnifier", true))
    end

    -- 代码缩略图（点击跳转由 Java 侧 attachToEditor 默认处理）
    if mCodeMinimap then
        _M.refreshMinimap(true)
    end

    --编辑器 放大镜 和 ActionMode
    mLuaEditor.OnSelectionChangedListener = function(status, start, end_)
        _M1.javaClassAnalyse(mLuaEditor, status)
        if not (_clipboardActionMode) and status then
            activity.startSupportActionMode(getActionMode(mLuaEditor))
            MagnifierManager.Available = isMagnifierEnabled()
        elseif _clipboardActionMode and not (status) then
            _clipboardActionMode.finish()
            _clipboardActionMode = nil
            MagnifierManager.hide()
            MagnifierManager.Available = false
        end
        if mCodeMinimap and isMinimapEnabled() then
            mCodeMinimap.syncVisibleRangeFromEditor(true)
        end
    end

    mLuaEditor.setOnTouchListener(function(view, event)
        if MagnifierManager.Available == true and isMagnifierEnabled() then
            local action = event.action
            if action == MotionEvent.ACTION_DOWN or action == MotionEvent.ACTION_MOVE then
                local relativeCaretX = view.getCaretX() - view.getScrollX()
                local relativeCaretY = view.getCaretY() - view.getScrollY()
                local x = event.getX()
                local y = event.getY()
                if MagnifierManager.isNearChar(view, relativeCaretX, relativeCaretY, x, y) then
                    MagnifierManager.show(view, relativeCaretX, relativeCaretY, x, y)
                else
                    MagnifierManager.hide()
                end
            elseif action == MotionEvent.ACTION_CANCEL or action == MotionEvent.ACTION_UP then
                MagnifierManager.hide()
            end
        end
        if mCodeMinimap and isMinimapEnabled() then
            local action = event.action
            if action == MotionEvent.ACTION_UP then
                -- 输入/粘贴后松手时刷新缩略图内容
                mCodeMinimap.scheduleCodeRefresh(350)
            end
            if action == MotionEvent.ACTION_MOVE or action == MotionEvent.ACTION_UP then
                mCodeMinimap.syncVisibleRangeFromEditor(true)
            end
        end
    end)

    thread(function(mLuaEditor, bindClass)
        --activity补全
        local LuaActivity = bindClass "com.androlua.LuaActivity"
        local methods = {}
        local tmp = {}
        for _, v in (LuaActivity.getMethods()) do
            v = tostring(v.getName())
            if not v:find("%$") and not tmp[v] then
                tmp[v] = true
                methods[#methods + 1] = v .. "()"
            end
        end
         methods[#methods + 1] = "themeUtil"
        --补全
        ClassesNames.ensure() -- 确保类名数据已加载
        local classes = ClassesNames.simple_top_classes
        local ms = {
            "onKeyDown", "onKeyUp", "onKeyLongPress", "onKeyShortcut",
            "onCreate", "onStart", "onResume",
            "onPause", "onStop", "onDestroy", "onError", "onReceive",
            "onActivityResult", "onResult", "onNightModeChanged",
            "onContentChanged", "onConfigurationChanged",
            "onContextItemSelected", "onCreateContextMenu",
            "onCreateOptionsMenu", "onOptionsItemSelected", "onRequestPermissionsResult",
            "onClick", "onTouch", "onLongClick", "onPanelClosed",
            "onSupportActionModeStarted", "onSupportActionModeFinished",
            "onItemClick", "onItemLongClick", "onVersionChanged", "this", "android"
        }
        local l = #ms
        for k, v in classes do
            ms[l + k + 1] = v
        end
        mLuaEditor.addNames(ms)
                  .addNames({ "byte", "boolean", "short", "int", "long", "float", "double", "char" })
                  .addNames({ "R", "dump", "toutf8", "loadlayout", "printf", "thread", "xTask", "lazy" })
                  .addPackage("activity", methods)
                  .addPackage("this", methods)
                  .addPackage("debug", { "debug", "gethook", "getinfo", "getlocal", "getmetatable", "getregistry", "getupvalue", "getuservalue", "sethook", "setlocal", "setmetatable", "setupvalue", "setuservalue", "traceback", "upvalueid", "upvaluejoin" })
                  .addPackage("coroutine", { "create", "resume", "running", "status", "wrap", "yield" })
                  .addPackage("math", { "abs", "acos", "asin", "atan", "atan2", "ceil", "cos", "cosh", "deg", "exp", "floor", "fmod", "frexp", "huge", "ldexp", "log", "max", "min", "modf", "pi", "pow", "rad", "random", "randomseed", "sin", "sinh", "sqrt", "tan", "tanh" })
                  .addPackage("string", { "byte", "char", "dump", "find", "format", "gfind", "gmatch", "gsub", "len", "lower", "match", "pack", "rep", "reverse", "sub", "toutf8", "unpack", "upper" })
                  .addPackage("utf8", { "byte", "char", "find", "format", "gfind", "gmatch", "gsub", "len", "lower", "match", "rep", "reverse", "sub", "upper" })
                  .addPackage("bit32", { "arshift", "band", "bnot", "bor", "btest", "bxor", "extract", "lrotate", "lshift", "replace", "rrotate", "rshift" })
                  .addPackage("table", { "add", "clear", "clone", "concat", "const", "copy", "dump", "find", "foreach", "foreachi", "gfind", "insert", "pack", "remove", "size", "sort", "sub", "unpack" })
                  .addPackage("os", { "clock", "date", "difftime", "execute", "exit", "getenv", "remove", "rename", "setlocale", "time", "tmpname" })
                  .addPackage("file", { "exists", "info", "list", "mkdir", "readall", "save", "type" })
                  .addPackage("json", { "decode", "encode" })
                  .addPackage("okHttp", { "get", "unsafe", "post", "postText", "postJson" })
                  .addPackage("okhttp", { "delete", "get", "head", "post", "put" })
                  .addPackage("ext", { "pack", "packsize", "unpack" })
                  .addPackage("res", { "bitmap", "color", "dimen", "drawable", "font", "layout", "language", "plurals", "raw", "string", "view", })
                  .addPackage("saf", { "delete", "exists", "list", "mkdir", "read", "rename", "save", "type" })
                  .addPackage("luajava", { "astable", "bindClass", "createProxy", "instanceof", "loadLib", "new", "newInstance" })
                  .addPackage("io", { "close", "flush", "input", "lines", "open", "output", "popen", "read", "tmpfile", "type", "write" })
    end, mLuaEditor, bindClass)

end

-- 加载文件请求
function _M.load(path)
    --显示编辑器
    if mLuaEditor.getVisibility() == 4 then
        mLuaEditor.setVisibility(0)
    end
    pcall(function()
        if editor_empty_state then editor_empty_state.setVisibility(8) end
    end)
    --更新当前文件
    PathManager.updateFile(path)
    --判断Tab操作
    if TabUtil.Table[path] == nil then
        -- 未打开的文件，添加tab，在onTabSelected里读取
        TabUtil.add(path)
    else
        -- 已经存在的tab，editor读取
        mLuaEditor.setText(LuaFileUtil.read(path))
        resetPageTitle(path)
        -- 来自RecyclerView
        -- 如果是来自RV的加载就选择 tab
        if _M.fromRecy then
            TabUtil.Table[path].obj.select()
        end
        --载入指针位置
        if _M.last_history[path] ~= nil then
            mLuaEditor.setSelection(_M.last_history[path])
        end
    end
    table.insert(_M.last_history, 1, path)
    for n = 2, #_M.last_history do
        if n > 50 then
            _M.last_history[n] = nil
        elseif _M.last_history[n] == path then
            table.remove(_M.last_history, n)
        end
    end
    -- 销毁来自RV的标识
    _M.fromRecy = nil
    if mCodeMinimap and isMinimapEnabled() then
        mCodeMinimap.scheduleCodeRefresh(60)
        mCodeMinimap.syncVisibleRangeFromEditor(false)
    end
end

--[[
function _M.post(func)
    return mLuaEditor.post(func)
end
]]

return _M