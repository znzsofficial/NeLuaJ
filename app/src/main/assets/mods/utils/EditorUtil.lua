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

local function parseSharedColor(data, key, fallback)
    local raw = data and data[key]
    if not raw then return fallback end
    local ok, c = pcall(Color.parseColor, raw)
    if ok then return c end
    return fallback
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
    cfg.backgroundColor = parseSharedColor(data, "MinimapBg", cfg.backgroundColor)
    cfg.maskColor = parseSharedColor(data, "MinimapMask", Color.argb(0x28, 0x21, 0x96, 0xF3))
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
    cfg.colorDefault = parseSharedColor(data, "BaseWord", Color.argb(255, 0x44, 0x77, 0xe0))
    cfg.colorKeyword = parseSharedColor(data, "KeyWord", Color.argb(255, 0xb4, 0x00, 0x2d))
    cfg.colorString = parseSharedColor(data, "String", Color.argb(255, 0xc2, 0x18, 0x5b))
    cfg.colorComment = parseSharedColor(data, "Comment", Color.argb(255, 0x71, 0x78, 0x7E))
    cfg.colorNumber = parseSharedColor(data, "UserWord", Color.argb(255, 0x5c, 0x6b, 0xc0))
    cfg.colorId = parseSharedColor(data, "Global", Color.argb(255, 0x68, 0x9f, 0x38))
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

--- 选中区域切换 --[[ ... ]] 多行注释；无选区时注释当前行
function _M.toggleBlockComment(editor)
    if editor == nil then editor = mLuaEditor end
    local doc = editor.getText()
    local len = doc.length()
    if len <= 0 then return false end

    local a = editor.getSelectionStart()
    local b = editor.getSelectionEnd()
    if a > b then a, b = b, a end
    if a < 0 then a = 0 end
    if b > len then b = len end

    -- 无选区：整行（按 \n 边界）；setSelection(start, length)
    if a == b then
        local lineStart = a
        while lineStart > 0 and doc.charAt(lineStart - 1) ~= 10 do
            lineStart = lineStart - 1
        end
        local lineEnd = b
        while lineEnd < len and doc.charAt(lineEnd) ~= 10 do
            lineEnd = lineEnd + 1
        end
        a, b = lineStart, lineEnd
        if a == b then return false end
        editor.setSelection(a, b - a)
    end

    local selected = tostring(editor.getSelectedText())
    if selected == "" then return false end

    local JString = bindClass "java.lang.String"
    local out
    -- 解包：整段为 --[==[...]==]（含 0 个 =）
    local openEq, body = selected:match("^%-%-%[(=*)%[(.-)%]%1%]$")
    if openEq ~= nil then
        out = body
    else
        -- 内容含 ]] 时升级等号
        local n = 0
        while true do
            local close = "]" .. string.rep("=", n) .. "]"
            if not selected:find(close, 1, true) then break end
            n = n + 1
        end
        local eq = string.rep("=", n)
        out = "--[" .. eq .. "[" .. selected .. "]" .. eq .. "]"
    end

    editor.paste(out)
    local outLen = JString(out).length()
    local start = editor.getCaretPosition() - outLen
    if start < 0 then start = 0 end
    editor.setSelection(start, outLen)
    return true
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
            local commentItem = menu.add(0, 4, 0, res.string.block_comment)
            commentItem.setShowAsAction(2) -- SHOW_AS_ACTION_ALWAYS
            commentItem.setIcon(res.drawable("ic_comment"))
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
            elseif item.getItemId() == 4 then
                _M.toggleBlockComment(view)
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

--- 从 SharedData 应用高亮 / 光标 / 换行 / 空白 / Tab（可重复调用，即时生效）
function _M.applyEditorPrefs(editor)
    editor = editor or mLuaEditor
    if not editor then return false end
    local data = this.sharedData

    editor.basewordColor = parseSharedColor(data, "BaseWord", Color.argb(255, 0x44, 0x77, 0xe0))
    editor.keywordColor = parseSharedColor(data, "KeyWord", Color.argb(255, 0xb4, 0x00, 0x2d))
    editor.stringColor = parseSharedColor(data, "String", Color.argb(255, 0xc2, 0x18, 0x5b))
    editor.userwordColor = parseSharedColor(data, "UserWord", Color.argb(255, 0x5c, 0x6b, 0xc0))
    editor.commentColor = parseSharedColor(data, "Comment", Color.argb(255, 0x71, 0x78, 0x7e))
    editor.globalColor = parseSharedColor(data, "Global", Color.argb(255, 0x68, 0x9f, 0x38))
    editor.localColor = parseSharedColor(data, "Local", Color.argb(255, 0xb4, 0xb4, 0x84))
    editor.upvalColor = parseSharedColor(data, "Upval", Color.argb(255, 0x80, 0x80, 0xc0))

    -- 自定义光标色默认关；关闭时不写（关闭后需重启才回到默认）
    if isSharedTruthy(this.getSharedData("editor_custom_caret", false)) then
        local dark = this.isNightMode and this.isNightMode()
        local caretKey = dark and "Caret_Dark" or "Caret_Light"
        local caretDefault = dark
            and Color.argb(255, 0x9e, 0xca, 0xff)
            or Color.argb(255, 0x15, 0x65, 0xc0)
        editor.setCaretColor(parseSharedColor(data, caretKey, caretDefault))
    end

    if editor.setWordWrap then
        editor.setWordWrap(isSharedTruthy(this.getSharedData("editor_word_wrap", false)))
    end
    if editor.setNonPrintingCharVisibility then
        editor.setNonPrintingCharVisibility(
            isSharedTruthy(this.getSharedData("editor_show_whitespace", false)))
    end
    if editor.setTabSpaces then
        local n = tonumber(this.getSharedData("editor_tab_spaces", 4)) or 4
        n = math.floor(n + 0.5)
        if n < 1 then n = 1 elseif n > 16 then n = 16 end
        editor.setTabSpaces(n)
    end

    if mCodeMinimap then
        _M.refreshMinimap(false)
    end
    return true
end

--- 兼容旧名
function _M.setHighLight(view)
    _M.applyEditorPrefs(view)
end

--- 设置页改完后通知主界面立即重施（Main 的 pageName 为 MainActivity）
function _M.notifyPrefsChanged()
    pcall(function()
        local main = luajava.bindClass("com.androlua.LuaActivity").getActivity("MainActivity")
        if main then main.runFunc("onEditorPrefsChanged") end
    end)
end

function _M.init()
    -- 初始化放大镜
    MagnifierManager.initMagnifier(mLuaEditor);
    _M1.init()
    -- 初始化Tab
    initTab();

    _M.applyEditorPrefs(mLuaEditor)

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