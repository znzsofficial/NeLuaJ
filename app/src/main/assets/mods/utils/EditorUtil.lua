local res = res
local TabUtil = require "mods.utils.TabUtil"
local Session = require "mods.editor.EditorSession"
local Minimap = require "mods.editor.EditorMinimap"
local Completion = require "mods.editor.EditorCompletion"
local Selection = require "mods.editor.EditorSelection"
local File = bindClass "java.io.File"
local Color = bindClass "android.graphics.Color"
local _M = {}
_M.fromRecy = false

local function isSharedTruthy(value)
    return value == true or value == "true" or value == 1
end

local function parseSharedColor(data, key, fallback)
    local raw = data and data[key]
    if not raw then return fallback end
    local ok, c = pcall(Color.parseColor, raw)
    if ok then return c end
    return fallback
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

local function resetPageTitle(path)
    -- 解析失败时保留当前工程。以前 catch 里把 this_project 清成空，
    -- 打开工程外文件或路径对不上时，构建/运行会突然变成「没有工程」。
    local root = tostring(Bean.Path.app_root_pro_dir or "")
    local subfolder = root ~= "" and string.match(path or "", root .. "(.*)/") or nil
    if subfolder then
        local projectName = (subfolder .. "/"):match("/(.-)/")
        if projectName and projectName ~= "" then
            Bean.Project.this_project = projectName
            activity.setTitle(projectName)
        end
    end
    pcall(function()
        activity.getSupportActionBar().setSubtitle(File(path).getName())
    end)
end

-- 程序自己拨回标签时置位，避免 onTabSelected 再 load 一次
local selectingQuietly = false

function _M.currentFile()
    return Session.current() or ""
end

local function commitFile(path)
    Session.setCurrent(path)
    PathManager.updateFile(path)
end

local function clearFile()
    Session.setCurrent(nil)
    PathManager.updateFile("")
end

--- 缓冲区还是原来的文本，只把绑定路径改到新位置。调用前必须已经把内容写进旧路径。
function _M.rebindPath(path)
    local previous = Session.current()
    if not previous or previous == "" or not path or path == "" or path == previous then
        return false
    end
    local cursor = Session.cursor(previous)
    commitFile(path)
    if type(cursor) == "number" then
        Session.setCursor(path, cursor)
    end
    Session.remember(path)
    resetPageTitle(path)
    return true
end

local function quietSelect(tab)
    if not tab then return end
    selectingQuietly = true
    pcall(function() tab.select() end)
    selectingQuietly = false
end

--- 读入编辑用文本。读失败时 LuaFileUtil.read 返回 ""，非空文件绝不当成空内容。
local function readFileForEdit(path)
    local file = File(path)
    if not file.isFile() then return nil end
    local text = tostring(LuaFileUtil.read(path) or "")
    local len = file.length()
    if text == "" and len and len > 0 then
        return nil
    end
    return text
end

--- 把已经读到的文本载入编辑器。失败时不改当前文件。
local function bindFile(path, text)
    if text == nil then return false end
    mLuaEditor.setText(text)
    commitFile(path)
    mLuaEditor.setVisibility(0)
    resetPageTitle(path)
    local Init = package.loaded["activities.main.Init"]
    if Init and Init.syncEditorEmptyState then Init.syncEditorEmptyState() end
    Minimap.noteEdit(60)
    return true
end

--- 关掉最后一个文件、或启动时还没有文件：清掉缓冲区，只留空状态。
--- 不清除工程名——人还在工程里，只是没打开文件。
function _M.enterEmptyState()
    clearFile()
    if mLuaEditor then
        mLuaEditor.setText("")
        mLuaEditor.setVisibility(4)
        mLuaEditor.clearFocus()
    end
    -- 窗口令牌还没生成时，这个调用会抛异常。键盘收不起来不能挡住空状态。
    pcall(function()
        local imm = activity.getSystemService(activity.INPUT_METHOD_SERVICE)
        if imm and mLuaEditor then
            imm.hideSoftInputFromWindow(mLuaEditor.getWindowToken(), 0)
        end
    end)
    if error_Text then
        local parent = error_Text.getParent()
        if parent then parent.setVisibility(8) end
    end
    local root = tostring(Bean.Path.app_root_pro_dir or ""):gsub("/+$", "")
    local dir = tostring(Bean.Path.this_dir or ""):gsub("/+$", "")
    local project = ""
    if root ~= "" and dir ~= root and dir:sub(1, #root) == root and dir:sub(#root + 1, #root + 1) == "/" then
        project = dir:sub(#root + 2):match("^([^/]+)") or ""
        if project ~= "" and not File(root .. "/" .. project).isDirectory() then
            project = ""
        end
    end
    if project ~= "" then
        Bean.Project.this_project = project
        activity.setTitle(project)
    else
        Bean.Project.this_project = ""
        activity.setTitle("NeLuaJ+")
    end
    local bar = activity.getSupportActionBar()
    if bar then bar.setSubtitle(res.string.no_file) end
    local Init = package.loaded["activities.main.Init"]
    if Init and Init.syncEditorEmptyState then Init.syncEditorEmptyState() end
end

local function initTab()
    -- TabLayout.OnTabSelectedListener
    mTab.addOnTabSelectedListener({
        onTabUnselected = function(tab)
        end;
        onTabSelected = function(tab)
            if selectingQuietly then return end
            if not tab.tag or not tab.tag.path then return end
            _M.load(tab.tag.path)
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

local function backupPrevious(path, disk)
    pcall(function()
        checkBackup()
        local root = tostring(Bean.Path.app_root_pro_dir or "")
        local relative = path
        if root ~= "" and path:sub(1, #root) == root then
            relative = path:sub(#root + 1)
        end
        local backups = Bean.Path.backup_dir .. "/" .. os.date("%Y-%m-%d") .. "/" .. os.date("%H_%M") .. relative
        local backupFile = File(backups)
        -- 每分钟一份，内容是覆盖前的磁盘文本。备份失败不能挡住这次保存。
        if not backupFile.exists() then
            File(backupFile.getParent()).mkdirs()
            LuaFileUtil.create(backups, disk)
        end
    end)
end

--- getText() 返回的是文档对象，不是字符串。toString() 才是正文，并且不含内部 EOF。
local function editorText(editor)
    local text = editor.getText()
    if text == nil then return "" end
    return tostring(text.toString())
end

local function noteEmptySave()
    pcall(function()
        local originTitle = this.supportActionBar.subtitle
        this.supportActionBar.subtitle = res.string.empty_file_saved
        this.delay(1000, function()
            this.supportActionBar.subtitle = originTitle
        end)
    end)
end

--- 返回 nil（无法保存）、"same"（不用写）或写入是否成功。
--- 只写当前缓冲区对应的文件。非空文件读成空时拒绝覆盖。
function _M.save(path, str, editor)
    editor = editor or mLuaEditor
    path = path or Session.current()
    if not path or path == "" or not editor then
        return
    end
    if Session.current() ~= path then
        return
    end
    if str == nil then
        str = editorText(editor)
    else
        str = tostring(str)
    end

    local file = File(path)
    local exists = file.isFile()
    local disk = tostring(LuaFileUtil.read(path) or "")
    local len = file.length()
    if exists and disk == "" and len and len > 0 then
        return
    end
    if str == disk then
        return "same"
    end

    if exists then backupPrevious(path, disk) end
    local written
    if exists then
        written = LuaFileUtil.write(path, str)
    else
        written = LuaFileUtil.writeOrCreate(path, str)
    end
    if written ~= true then
        return false
    end

    if #str == 0 then noteEmptySave() end
    local selectionEnd = editor.getSelectionEnd()
    Session.setCursor(path, selectionEnd)
    this.setSharedData("lastFile", path)
    this.setSharedData("lastSelect", selectionEnd)
    return true
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

    Minimap.refresh(false)
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
    Selection.init()
    initTab()
    _M.applyEditorPrefs(mLuaEditor)
    mLuaEditor.setTypeface(res.font.code)
    Minimap.refresh(true)
    Selection.install(mLuaEditor, function(view) return _M.toggleBlockComment(view) end)
    Completion.install(mLuaEditor)
end

local function savedEnough(result)
    return result == true or result == "same"
end

local function stayOn(path)
    _M.fromRecy = false
    if path and TabUtil.Table[path] then
        quietSelect(TabUtil.Table[path].obj)
    end
end

function _M.load(path)
    if not path or path == "" then return end
    -- 已经在编辑这个文件：不要从磁盘重读，否则未保存的修改会被盖掉。
    if Session.isCurrent(path) then
        if _M.fromRecy and TabUtil.Table[path] then
            quietSelect(TabUtil.Table[path].obj)
        end
        _M.fromRecy = false
        return
    end
    -- 先落盘当前缓冲区。拒绝覆盖时不切换，并把标签拨回去。
    local previous = Session.current()
    if previous and previous ~= "" then
        if not savedEnough(_M.save(previous)) then
            stayOn(previous)
            return
        end
    end
    local text = readFileForEdit(path)
    if text == nil then
        stayOn(previous)
        return
    end
    if not (TabUtil.Table[path] and TabUtil.Table[path].obj) then
        TabUtil.add(path, { select = false })
    end
    if not bindFile(path, text) then
        stayOn(previous)
        return
    end
    quietSelect(TabUtil.Table[path] and TabUtil.Table[path].obj)
    local cursor = Session.cursor(path)
    if type(cursor) == "number" then
        mLuaEditor.setSelection(cursor)
    end
    Session.remember(path)
    _M.fromRecy = false
end

return _M
