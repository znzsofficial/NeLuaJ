--- 工程工作区持久化：每个工程单独保存打开的文件标签、活动文件与光标位置。
--- 存储走 LuaKV（ns = "workspace"，key = 工程目录绝对路径）。
--- 保存时机：编辑器 onPause、切换工程（PathManager.updateDir 前）、关闭文件标签。
--- 恢复时机：带工程参数打开编辑器时（onCreate 装配完成后）。
---
--- 注意：非编辑器环境（首页等）mLuaEditor 不存在，本模块所有入口自动跳过。
local File = luajava.bindClass "java.io.File"
local LuaKV = require "mods.utils.LuaKV"
local TabUtil = require "mods.utils.TabUtil"
local EditorUtil = require "mods.utils.EditorUtil"
local Session = require "mods.editor.EditorSession"
local ProjectContext = require "mods.project.ProjectContext"

local _M = {}

local normalize = ProjectContext.normalize

local function underProject(path, key)
    return key ~= nil and path ~= key and ProjectContext.contains(path, key)
end

local function editorContext()
    return mLuaEditor ~= nil
end

--- 收集当前工作区：只收该工程目录下的标签，避免切工程时把别的工程文件写进这份记录
local function collect(key)
    local tabs, seen = {}, {}
    for _, p in ipairs(Session.recent()) do
        p = normalize(p)
        if underProject(p, key) and not seen[p] and TabUtil.Table[p] and File(p).isFile() then
            seen[p] = true
            tabs[#tabs + 1] = p
        end
    end
    for p in pairs(TabUtil.Table) do
        p = normalize(p)
        if underProject(p, key) and not seen[p] and File(p).isFile() then
            seen[p] = true
            tabs[#tabs + 1] = p
        end
    end
    local active = normalize(EditorUtil.currentFile and EditorUtil.currentFile() or "")
    if not underProject(active, key) then active = "" end
    local select = nil
    if active ~= "" and mLuaEditor then
        pcall(function() select = mLuaEditor.getSelectionEnd() end)
    end
    local cursors = {}
    for path, position in pairs(Session.cursors()) do
        path = normalize(path)
        if underProject(path, key) then cursors[path] = position end
    end
    return {
        tabs = tabs,
        active = active ~= "" and active or nil,
        select = select,
        cursors = cursors,
    }
end

--- 保存指定工程目录的工作区（缺省 = 当前 this_dir）；非工程目录/非编辑器环境返回 false
function _M.saveFor(dir)
    if not editorContext() then return false end
    local key = ProjectContext.projectKeyOf(dir or ProjectContext.snapshot().directory)
    if not key then return false end
    local saved = LuaKV.set("workspace", key, collect(key))
    if not saved then return false, "workspace write failed: " .. key end
    return true
end

--- 恢复当前 this_dir 工程的工作区：加回文件标签、选中活动文件并恢复光标。
--- 返回是否发生了恢复。
function _M.restoreCurrent()
    if not editorContext() then return false end
    local key = ProjectContext.snapshot().projectRoot
    if not key then return false end
    local ws = LuaKV.get("workspace", key)
    if type(ws) ~= "table" then return false end

    local active = normalize(ws.active or "")
    if not underProject(active, key) then active = "" end
    local restored = false
    if type(ws.cursors) == "table" then
        local cursors = {}
        for path, position in pairs(ws.cursors) do
            path = normalize(path)
            if underProject(path, key) then cursors[path] = position end
        end
        Session.importCursors(cursors)
    end

    -- 非活动文件只挂标签，不读进唯一的缓冲区。
    for _, p in ipairs(ws.tabs or {}) do
        p = normalize(p)
        if underProject(p, key) and p ~= active and File(p).isFile() then
            TabUtil.add(p, { select = false })
            restored = true
        end
    end
    -- 活动文件最后载入并选中其标签，恢复光标
    if active ~= "" and File(active).isFile() then
        EditorUtil.fromRecy = true
        EditorUtil.load(active)
        if ws.select then EditorUtil.setSelection(tonumber(ws.select) or 0) end
        restored = true
    end
    return restored
end

return _M
