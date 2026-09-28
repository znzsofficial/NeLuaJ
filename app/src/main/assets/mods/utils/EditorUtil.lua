local res = res
local table = table
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

function _M.refreshMinimap(full)
    Minimap.refresh(full)
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

-- 编辑器缓冲区当前对应的文件。save 只写这个路径：
-- this_file 先被切走、文本还是上一个文件或尚未载入时，不能覆盖目标文件。
_M.shownFile = nil
-- 程序自己拨回标签时置位，避免 onTabSelected 再 load 一次
_M.quietSelect = false

local function syncSession()
    _M.shownFile = Session.current()
end

function _M.currentFile()
    return Session.current() or ""
end

local function commitFile(path)
    Session.setCurrent(path)
    syncSession()
    PathManager.updateFile(path)
end

local function clearFile()
    Session.setCurrent(nil)
    syncSession()
    PathManager.updateFile("")
end

local function quietSelect(tab)
    if not tab then return end
    _M.quietSelect = true
    pcall(function() tab.select() end)
    _M.quietSelect = nil
end

--- 读入编辑用文本。读失败时 LuaFileUtil.read 返回 ""，非空文件绝不当成空内容。
local function readFileForEdit(path)
    local file = File(path)
    if not file.isFile() then return nil end
    local text = LuaFileUtil.read(path)
    local len = file.length()
    if text == "" and len and len > 0 then
        return nil
    end
    return text
end

--- 把磁盘文件载入编辑器并绑定 shownFile。失败时不改 this_file / shownFile。
local function bindFile(path, text)
    if text == nil then text = readFileForEdit(path) end
    if text == nil then return false end
    mLuaEditor.setText(text)
    commitFile(path)
    mLuaEditor.setVisibility(0)
    resetPageTitle(path)
    pcall(function()
        local Init = package.loaded["activities.main.Init"]
        if Init and Init.syncEditorEmptyState then Init.syncEditorEmptyState() end
    end)
    Minimap.noteEdit(60)
    return true
end

--- 关掉最后一个文件、或启动时还没有文件：清掉缓冲区，只留空状态。
--- 不清除工程名——人还在工程里，只是没打开文件。
function _M.enterEmptyState()
    clearFile()
    pcall(function()
        mLuaEditor.setText("")
        mLuaEditor.setVisibility(4)
        mLuaEditor.clearFocus()
    end)
    pcall(function()
        local imm = activity.getSystemService(activity.INPUT_METHOD_SERVICE)
        if imm and mLuaEditor then
            imm.hideSoftInputFromWindow(mLuaEditor.getWindowToken(), 0)
        end
    end)
    pcall(function()
        if error_Text then error_Text.getParent().setVisibility(8) end
    end)
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
    pcall(function()
        activity.getSupportActionBar().setSubtitle(res.string.no_file)
    end)
    pcall(function()
        local Init = package.loaded["activities.main.Init"]
        if Init and Init.syncEditorEmptyState then Init.syncEditorEmptyState() end
    end)
end

local function initTab()
    -- TabLayout.OnTabSelectedListener
    mTab.addOnTabSelectedListener({
        onTabUnselected = function(tab)
        end;
        onTabSelected = function(tab)
            if _M.quietSelect then return end
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

function _M.save(path, str, editor)
    editor = editor or mLuaEditor
    path = path or Session.current()
    if not path or path == "" or not editor then
        return
    end
    -- 缓冲区不是这个文件时拒绝写入，避免把 A 的文本或空白写进 B
    if Session.current() ~= path then
        return
    end
    if not str then
        str = tostring(editor.getText())
    end

    local file = File(path)
    local disk = LuaFileUtil.read(path)
    local len = file.length()
    -- 磁盘上明明有内容却读成空：读失败，绝不能继续覆盖
    if disk == "" and file.isFile() and len and len > 0 then
        return
    end
    if str == disk then
        return "same"
    end

    if #str == 0 then
        local originTitle = this.supportActionBar.subtitle
        this.supportActionBar.subtitle = res.string.empty_file_saved
        this.delay(1000, function()
            this.supportActionBar.subtitle = originTitle
        end)
    end

    local selectionEnd = editor.getSelectionEnd()
    Session.setCursor(path, selectionEnd)
    syncSession()
    this.setSharedData("lastFile", path)
    this.setSharedData("lastSelect", selectionEnd)
    checkBackup()
    local _path = path:gsub(Bean.Path.app_root_pro_dir, "")
    local backups = Bean.Path.backup_dir .. "/" .. os.date("%Y-%m-%d") .. "/" .. os.date("%H_%M") .. _path
    local backup_file = File(backups)
    -- 每分钟一份，内容是覆盖前的磁盘文本，方便把误保存捞回来
    if not backup_file.exists() then
        File(backup_file.getParent()).mkdirs()
        LuaFileUtil.create(backups, disk)
    end
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
    Selection.init()
    initTab()
    _M.applyEditorPrefs(mLuaEditor)
    mLuaEditor.setTypeface(res.font.code)
    _M.refreshMinimap(true)
    Selection.install(mLuaEditor, function(view) return _M.toggleBlockComment(view) end)
    Completion.install(mLuaEditor)
end

local function rememberHistory(path)
    Session.remember(path)
    syncSession()
end

local function savedEnough(result)
    return result == true or result == "same"
end

function _M.load(path)
    if not path or path == "" then return end
    -- 已经在编辑这个文件：不要从磁盘重读，否则未保存的修改会被盖掉。
    if Session.isCurrent(path) then
        if _M.fromRecy and TabUtil.Table[path] and TabUtil.Table[path].obj then
            quietSelect(TabUtil.Table[path].obj)
        end
        _M.fromRecy = nil
        return
    end
    -- 先落盘当前缓冲区。拒绝覆盖时不切换，避免丢掉还在编辑的文本。
    local previous = Session.current()
    if previous and previous ~= "" then
        if not savedEnough(_M.save(previous)) then
            _M.fromRecy = nil
            return
        end
    end
    local text = readFileForEdit(path)
    if text == nil then
        _M.fromRecy = nil
        local created = not (TabUtil.Table[path] and TabUtil.Table[path].obj)
        _M.quietSelect = true
        pcall(function()
            if created then TabUtil.remove(path) end
            if previous and previous ~= path and TabUtil.Table[previous] and TabUtil.Table[previous].obj then
                TabUtil.Table[previous].obj.select()
            end
        end)
        _M.quietSelect = nil
        return
    end
    if not (TabUtil.Table[path] and TabUtil.Table[path].obj) then
        TabUtil.add(path, { select = false })
    end
    if not bindFile(path, text) then
        _M.fromRecy = nil
        return
    end
    quietSelect(TabUtil.Table[path] and TabUtil.Table[path].obj)
    local cursor = Session.cursor(path)
    if type(cursor) == "number" then
        mLuaEditor.setSelection(cursor)
    end
    rememberHistory(path)
    _M.fromRecy = nil
    Minimap.noteEdit(60)
end

--[[
function _M.post(func)
    return mLuaEditor.post(func)
end
]]

return _M
