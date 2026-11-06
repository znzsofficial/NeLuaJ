local res = res
local TabUtil = require "mods.utils.TabUtil"
local Session = require "mods.editor.EditorSession"
local Minimap = require "mods.editor.EditorMinimap"
local Completion = require "mods.editor.EditorCompletion"
local Selection = require "mods.editor.EditorSelection"
local File = bindClass "java.io.File"
local Color = bindClass "android.graphics.Color"
local _M = {}
local loadedPath, loadedText, diskVersion
local ProjectContext = require "mods.project.ProjectContext"
local testStorage, native

-- Only a non-Android harness may explicitly supply storage. Binding failures in
-- production are errors, never permission to fall back to non-atomic writes.
function _M.setTestStorage(storage)
    assert(not luajava, "test storage is unavailable on Android")
    testStorage = storage
end

local function decode(value)
    if type(value) == "table" then return value end
    return require("json").decode(tostring(value))
end

local function storage()
    if testStorage then return testStorage end
    if not native then native = luajava.kotlinObject("com.nekolaska.io.FileMutationEngine") end
    return native
end

local function observe(path)
    local ok, value = pcall(function() return decode(storage().observe(path)) end)
    if ok and value and value.kind == "file" and type(value.text) == "string"
        and type(value.version) == "string" then return value end
    return nil, ok and "无法读取文本文件版本" or tostring(value)
end

local function draftFile(slot)
    local root = tostring(activity.getFilesDir()) .. "/editor-drafts"
    assert(File(root).isDirectory() or File(root).mkdirs(), "无法创建草稿目录")
    return root .. "/" .. slot .. ".json"
end

local function readDraftSlot(slot)
    if testStorage then return testStorage.readDraft(slot) end
    local f = io.open(draftFile(slot), "rb")
    if not f then return nil end
    local text = f:read("*a"); f:close()
    return decode(text)
end

function _M.listDrafts()
    local list = {}
    for slot = 1, 8 do
        local ok, draft = pcall(readDraftSlot, slot)
        if ok and draft then draft.slot = slot; list[#list + 1] = draft end
    end
    table.sort(list, function(a, b)
        if a.created ~= b.created then return a.created > b.created end
        return (a.order or 0) > (b.order or 0)
    end)
    return list
end

function _M.readDraft(slot)
    assert(type(slot) == "number" and slot >= 1 and slot <= 8 and slot % 1 == 0)
    local ok, draft = pcall(readDraftSlot, slot)
    if ok then return draft end
    return nil, tostring(draft)
end

function _M.listExternalDrafts(path)
    local list = {}
    for _, draft in ipairs(_M.listDrafts()) do
        if not path or draft.path == path then
            draft.id, draft.createdAt = draft.slot, draft.created
            list[#list + 1] = draft
        end
    end
    return list
end

local function preserveDraft(snapshot, target)
    local text = tostring(mLuaEditor.getText().toString())
    Session.observeText(text)
    if text == snapshot.text then return true end
    local ok, err = pcall(function()
        assert(#text <= 1024 * 1024, "草稿超过 1 MiB 上限")
        local list, used, slot, order = _M.listDrafts(), {}, nil, 0
        for _, item in ipairs(list) do used[item.slot] = true; order = math.max(order, item.order or 0) end
        for index = 1, 8 do if not used[index] then slot = index; break end end
        slot = slot or list[#list].slot
        local draft = { path = target or Session.current(), originalPath = Session.current(), text = text, created = os.time(), order = order + 1,
            documentId = Session.identity().documentId, diskVersion = diskVersion,
            cursor = mLuaEditor.getSelectionEnd() }
        if testStorage then assert(testStorage.writeDraft(slot, draft)); return end
        local path = draftFile(slot)
        local f = assert(io.open(path .. ".tmp", "wb"))
        local written, reason = f:write(require("json").encode(draft))
        local closed = f:close()
        assert(written and closed, reason or "草稿写入失败")
        assert(os.rename(path .. ".tmp", path))
    end)
    if not ok then return false, "强制刷新已继续，但手动输入草稿保存失败: " .. tostring(err) end
    return true
end

function _M.restoreDraft(slot)
    local draft, err = _M.readDraft(slot)
    if not draft then return false, err or "草稿不存在" end
    if Session.current() ~= draft.path then return false, "请先打开草稿对应文件" end
    local ok, warning = preserveDraft({ text = loadedText })
    if not ok then return false, warning end
    local latest, readError = observe(draft.path)
    if not latest then return false, readError end
    loadedPath, loadedText, diskVersion = draft.path, latest.text, latest.version
    mLuaEditor.setText(draft.text)
    Session.observeText(draft.text)
    return true
end

_M.restoreExternalDraft = _M.restoreDraft
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
    if loadedPath == previous then loadedPath = path end
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
    local value = observe(path)
    if value then return value.text, value.version end
end

--- 把已经读到的文本载入编辑器。失败时不改当前文件。
local function bindFile(path, text, version)
    if text == nil then return false end
    mLuaEditor.setText(text)
    commitFile(path)
    loadedPath, loadedText = path, text
    diskVersion = version
    Session.observeText(text)
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
    loadedPath, loadedText, diskVersion = nil, nil, nil
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
function _M.save(path, str, editor, token)
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

    Session.observeText(str)
    if loadedPath ~= path or not diskVersion then return false, "missing_baseline" end
    local ok, result = pcall(function()
        return decode(storage().saveText(token or "", path, str, diskVersion))
    end)
    if not ok then return false, tostring(result) end
    if result.outcome ~= "committed" and result.outcome ~= "unchanged" then
        return false, result.error or "save_rejected"
    end
    -- The version must belong to the committed text, not to a later observe.
    local version = result.version
    for _, change in ipairs(result.changes or {}) do
        if change.path == path then version = change.afterVersion or change.version or (change.after and change.after.version) or version end
    end
    if not version then
        local value = observe(path)
        if value and value.text == str then version = value.version end
    end
    diskVersion = version
    loadedPath, loadedText = path, str
    if result.outcome == "unchanged" then return "same" end

    if #str == 0 then noteEmptySave() end
    local selectionEnd = editor.getSelectionEnd()
    Session.setCursor(path, selectionEnd)
    this.setSharedData("lastFile", path)
    this.setSharedData("lastSelect", selectionEnd)
    return true
end

local function canonical(path)
    return tostring(File(path).getCanonicalPath())
end

--- Called on the UI thread immediately before an AI write, after approval.
function _M.prepareExternalWrite(path, token)
    local current = Session.current()
    if not current or current == "" or not mLuaEditor or canonical(current) ~= canonical(path) then
        return nil
    end
    local saved = _M.save(current, nil, nil, token)
    if saved ~= true and saved ~= "same" then
        error("当前编辑器内容无法保存或与磁盘冲突，AI 写入未执行")
    end
    local snapshot = Session.identity(editorText(mLuaEditor))
    snapshot.text, snapshot.cursor, snapshot.diskVersion = editorText(mLuaEditor), mLuaEditor.getSelectionEnd(), diskVersion
    return snapshot
end

--- Reload without load()'s save/same-file shortcuts; AI may explicitly prefer disk content.
function _M.finishExternalWrite(snapshot, target, force)
    if not snapshot or not Session.isBinding(snapshot) then return true end
    if not force and editorText(mLuaEditor) ~= snapshot.text then
        return false, "AI 已修改磁盘文件，但编辑期间又有手动修改；已保留编辑器内容，请合并后再保存。"
    end
    target = target or snapshot.path
    local text, version = readFileForEdit(target)
    if text == nil then return false, "AI 已写入，但编辑器无法重新读取文件: " .. target end
    local _, warning = preserveDraft(snapshot, target)
    if target ~= snapshot.path and not TabUtil.Table[target] then
        TabUtil.add(target, { select = false })
    end
    bindFile(target, text, version)
    Session.remember(target)
    if type(snapshot.cursor) == "number" then Session.setCursor(target, snapshot.cursor) end
    if target ~= snapshot.path then
        selectingQuietly = true
        local ok, err = pcall(TabUtil.remove, snapshot.path)
        selectingQuietly = false
        if not ok then return false, tostring(err) end
    end
    quietSelect(TabUtil.Table[target] and TabUtil.Table[target].obj)
    pcall(function() mLuaEditor.setSelection(snapshot.cursor or 0) end)
    return true, warning
end

local function within(path, root)
    return path == root or path:sub(1, #root + 1) == root .. "/"
end

function _M.prepareFileOperation(name, args, token)
    if not args or not args.path then return nil end
    local root = canonical(args.path):gsub("/+$", "")
    local destination = name == "rename_file" and args.new_path and canonical(args.new_path) or nil
    local snapshot = { tabs = {}, root = root, destination = destination,
        scope = ProjectContext.snapshot() }
    for path, tab in pairs(TabUtil.Table) do
        local normalized = canonical(path)
        if within(normalized, root) then
            snapshot.tabs[#snapshot.tabs + 1] = { path = path, tab = tab,
                target = destination and (destination .. normalized:sub(#root + 1)) or path }
        end
    end
    local current = Session.current()
    if current and current ~= "" and within(canonical(current), root) then
        snapshot.editor = _M.prepareExternalWrite(current, token)
        snapshot.target = destination and (destination .. canonical(current):sub(#root + 1)) or current
    end
    return snapshot
end

-- Recovery captures UI ownership without saving an old buffer over recovered data.
function _M.captureRecovery(effects)
    if not mLuaEditor then return nil, "editor_unavailable" end
    local scope = ProjectContext.snapshot()
    if effects.scopeId ~= scope.scopePath then return nil, "scope_stale" end
    local snapshot = { scope = scope, tabs = {}, recovery = true }
    for path, tab in pairs(TabUtil.Table) do
        snapshot.tabs[#snapshot.tabs + 1] = { path = path, tab = tab, target = path }
    end
    local current = Session.current()
    if current and current ~= "" then
        snapshot.editor = Session.identity(editorText(mLuaEditor))
        snapshot.editor.text = loadedText
        snapshot.editor.cursor = mLuaEditor.getSelectionEnd()
    end
    return snapshot
end

function _M.finishFileOperation(snapshot, effects)
    if not snapshot then return true end
    if not mLuaEditor then return false, "editor_unavailable" end
    if not ProjectContext.isCurrent(snapshot.scope, "project") then return true end
    if not effects or (effects.outcome ~= "committed" and effects.outcome ~= "partial") then return true end
    local recoveryWarning
    if effects.outcome == "partial" then
        local unknown = {}
        for _, item in ipairs(effects.unknownPaths or {}) do
            unknown[#unknown + 1] = tostring(item.path or "?")
        end
        recoveryWarning = "文件操作仅部分完成，已同步可确认的变更；请恢复文件历史后重新载入编辑器。"
        if #unknown > 0 then
            recoveryWarning = recoveryWarning .. " 无法确认的路径（保留当前内容）: " .. table.concat(unknown, ", ")
        end
    end
    local function withRecoveryWarning(reason)
        if reason and recoveryWarning then return reason .. "\n" .. recoveryWarning end
        return reason or recoveryWarning
    end
    local replayVersions = {}
    if snapshot.recovery then
        for _, change in ipairs(effects.changes or {}) do
            local ok, observed = pcall(function() return decode(storage().observe(change.path)) end)
            if not ok then return false, tostring(observed) end
            replayVersions[change.path] = observed and observed.version == change.afterVersion
        end
    end
    local function confirmed(change)
        return (effects.outcome ~= "partial" or change.verified == true)
            and (not snapshot.recovery or replayVersions[change.path])
    end
    local function affected(path)
        local normalized = canonical(path)
        for _, item in ipairs(effects.unknownPaths or {}) do
            if item.path and within(normalized, canonical(item.path):gsub("/+$", "")) then return end
        end
        for _, change in ipairs(effects.changes or {}) do
            local source = change.path
            if confirmed(change) and source and within(normalized, canonical(source):gsub("/+$", "")) then
                if change.afterKind == "missing" then
                    if change.kind == "rename" then
                        for _, other in ipairs(effects.changes) do
                            if confirmed(other) and other.kind == "rename" and other.path ~= source
                                and other.from == change.from and other.to == change.to
                                and (other.afterKind == "file" or other.afterKind == "dir") then
                                return canonical(other.path) .. normalized:sub(#canonical(source) + 1), "rename"
                            end
                        end
                    end
                    return nil, "delete"
                elseif change.afterKind == "file" or change.afterKind == "dir" then
                    return path, "write"
                end
            end
        end
    end
    local result, reason = true, nil
    local current = Session.current()
    if current then
        local target, kind = affected(current)
        if kind then
            -- A->B->A is a new binding: reconcile it using its own cursor and
            -- baseline, never apply the captured document's cursor to it.
            local currentSnapshot = snapshot.editor
            if not Session.isBinding(currentSnapshot) then
                currentSnapshot = Session.identity(editorText(mLuaEditor))
                currentSnapshot.text, currentSnapshot.cursor = loadedText, mLuaEditor.getSelectionEnd()
            end
            if kind == "delete" then
                local _, warning = preserveDraft(currentSnapshot)
                reason = warning
                _M.enterEmptyState()
            else
                result, reason = _M.finishExternalWrite(currentSnapshot, target, true)
            end
        end
    end
    selectingQuietly = true
    local ok, err = pcall(function()
        for _, item in ipairs(snapshot.tabs) do
            if TabUtil.Table[item.path] == item.tab then
                local target, kind = affected(item.path)
                if kind == "rename" and target ~= item.path then
                    if not TabUtil.Table[target] then TabUtil.add(target, { select = false }) end
                    local cursor = Session.cursor(item.path)
                    if cursor and Session.current() ~= target then Session.setCursor(target, cursor) end
                    Session.remember(target)
                    TabUtil.remove(item.path)
                elseif kind == "delete" then
                    TabUtil.remove(item.path)
                end
            end
        end
    end)
    selectingQuietly = false
    if not ok then return false, withRecoveryWarning(tostring(err)) end
    local current = Session.current()
    quietSelect(current and TabUtil.Table[current] and TabUtil.Table[current].obj)
    return result, withRecoveryWarning(reason)
end

function _M.reconcileExternal(...)
    return require("mods.editor.ExternalEdits").reconcile(...)
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
    local text, version = readFileForEdit(path)
    if text == nil then
        stayOn(previous)
        return
    end
    if not (TabUtil.Table[path] and TabUtil.Table[path].obj) then
        TabUtil.add(path, { select = false })
    end
    if not bindFile(path, text, version) then
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
