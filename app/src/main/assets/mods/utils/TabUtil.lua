local PopupMenu = luajava.bindClass "androidx.appcompat.widget.PopupMenu"
local File = luajava.bindClass "java.io.File"

local _M = {}
_M.Table = {}
local tabTable = _M.Table

local function copy(str)
    this.getSystemService(this.CLIPBOARD_SERVICE).setText(str)
end

local function getPathName(path)
    return path:match(".*/(.*)") or path
end

local function getProjectPathInfo(path)
    local pattern = Bean.Path.app_root_pro_dir .. "(.*)/"
    local subfolder = path:match(pattern)
    if not subfolder then
        return nil
    end
    subfolder = subfolder .. "/"
    return {
        subfolder = subfolder,
        projectName = subfolder:match("/(.-)/"),
        relativePath = subfolder:match("/(.+)"),
    }
end

local function saveCurrentEditor()
    if Bean.Path.this_file ~= "" then
        LuaFileUtil.write(Bean.Path.this_file, tostring(mLuaEditor.getText()))
    end
end

local function resetEmptyState()
    PathManager.updateFile("")
    activity.setTitle("NeLuaJ+")
    activity.getSupportActionBar().setSubtitle(res.string.no_file)
    Bean.Project.this_project = ""
    mLuaEditor.setVisibility(4)
    pcall(function()
        local Init = package.loaded["activities.main.Init"]
        if Init and Init.syncEditorEmptyState then
            Init.syncEditorEmptyState()
        elseif editor_empty_state then
            editor_empty_state.setVisibility(0)
            editor_empty_state.bringToFront()
        end
    end)
end

local function closeTabs(paths)
    if #paths == 0 then
        return
    end

    saveCurrentEditor()
    for _, path in ipairs(paths) do
        local entry = tabTable[path]
        if entry and entry.obj then
            mTab.removeTab(entry.obj)
        end
        tabTable[path] = nil
    end

    if mTab.getTabCount() == 0 then
        resetEmptyState()
    end
end

function _M.add(path)
    if tabTable[path] and tabTable[path].obj then
        tabTable[path].obj.select()
        return tabTable[path].obj
    end

    tabTable[path] = tabTable[path] or {}

    local tab = mTab.newTab()
    local pathName = getPathName(path)
    local projectInfo = getProjectPathInfo(path)

    tab.setText(pathName)

    local view = tab.view
    local popupMenu = PopupMenu(activity, view)
    local menu = popupMenu.getMenu()

    menu.add(res.string.close_file).onMenuItemClick = function()
        closeTabs({ path })
    end

    menu.add(res.string.close_other).onMenuItemClick = function()
        local paths = {}
        for itemPath, entry in pairs(tabTable) do
            if itemPath ~= path and entry and entry.obj then
                paths[#paths + 1] = itemPath
            end
        end
        closeTabs(paths)
    end

    menu.add(res.string.close_all).onMenuItemClick = function()
        local paths = {}
        for itemPath, entry in pairs(tabTable) do
            if entry and entry.obj then
                paths[#paths + 1] = itemPath
            end
        end
        closeTabs(paths)
    end

    local menu1 = menu.addSubMenu(res.string.copy)
    menu1.add(pathName).onMenuItemClick = function()
        copy(pathName)
    end
    if projectInfo then
        menu1.add(projectInfo.relativePath .. pathName).onMenuItemClick = function()
            copy(projectInfo.relativePath .. pathName)
        end
    end
    menu1.add(path).onMenuItemClick = function()
        copy(path)
    end

    view.onLongClick = function()
        popupMenu.show()
        return true
    end

    view.setOnTouchListener(popupMenu.getDragToOpenListener())

    tabTable[path].obj = tab
    tabTable[path].obj.tag = tabTable[path].obj.tag or {}
    tabTable[path].obj.tag.path = path
    tabTable[path].obj.tag.first = path

    mTab.addTab(tab, mTab.getTabCount())
    tab.select()

    return tab
end

function _M.remove(path)
    local entry = tabTable[path]
    if not entry then
        return
    end

    if Bean.Path.this_file == path then
        saveCurrentEditor()
    end

    if entry.obj then
        mTab.removeTab(entry.obj)
    end
    tabTable[path] = nil

    if mTab.getTabCount() == 0 then
        resetEmptyState()
    end
end

--- 关闭 path 本身及位于 path/ 下的全部标签（删目录 / 多选删工程）
function _M.removeUnder(root)
    if type(root) ~= "string" or root == "" then return end
    local prefix = root
    if prefix:sub(-1) ~= "/" then
        prefix = prefix .. "/"
    end
    local paths = {}
    for path, entry in pairs(tabTable) do
        local current = path
        if entry and entry.obj and entry.obj.tag and entry.obj.tag.path then
            current = entry.obj.tag.path
        end
        if current == root or (current and current:sub(1, #prefix) == prefix) then
            paths[#paths + 1] = path
        end
    end
    closeTabs(paths)
end

function _M.checkAll()
    local missing = {}
    for path, entry in pairs(tabTable) do
        local tab = entry and entry.obj
        local currentPath = tab and tab.tag and tab.tag.path or path
        if currentPath and not File(currentPath).exists() then
            missing[#missing + 1] = path
        end
    end

    if #missing > 0 then
        closeTabs(missing)
    end

    -- 当前工程目录已不存在时清掉项目态（标题 / this_project）
    local proj = Bean.Project and Bean.Project.this_project
    if type(proj) == "string" and proj ~= "" then
        local proDir = Bean.Path.app_root_pro_dir .. "/" .. proj
        if not File(proDir).exists() then
            if mTab.getTabCount() == 0 then
                resetEmptyState()
            else
                Bean.Project.this_project = ""
                activity.setTitle("NeLuaJ+")
            end
        end
    end
end

return _M