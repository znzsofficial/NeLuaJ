local PopupMenu = luajava.bindClass "androidx.appcompat.widget.PopupMenu"
local File = luajava.bindClass "java.io.File"

local _M = {}
_M.Table = {}
local tabTable = _M.Table

local copy = function(str)
    this.getSystemService(this.CLIPBOARD_SERVICE).setText(str)
end

function _M.add(path)
    --print"创建tab"
    tabTable = tabTable or {}
    tabTable[path] = tabTable[path] or {}
    local tab = mTab.newTab()
    local pathName = path:match(".*/(.*)")
    local pattern
    local subfolder
    local projectName
    local _subfolder
    local notProject
    try
    pattern = Bean.Path.app_root_pro_dir .. "(.*)/"
    subfolder = string.match(path, pattern) .. "/"
    projectName = subfolder:match("/(.-)/")
    _subfolder = subfolder:match("/(.+)")
    catch
    notProject = true
end

tab.setText(pathName)

local view = tab.view
local popupMenu = PopupMenu(activity, view)
local menu = popupMenu.getMenu()
menu.add(res.string.close_file).onMenuItemClick = function(a)
    for i in pairs(tabTable) do
        local _o = tabTable[i].obj
        LuaFileUtil.write(Bean.Path.this_file, tostring(mLuaEditor.getText()))
        if _o == tab then
            tabTable[i] = nil
            mTab.removeTab(_o)
        end
        if mTab.getTabCount() == 0 then
            PathManager.update_this_file("")
            activity.setTitle("NeLuaJ+")
            activity.getSupportActionBar().setSubtitle(res.string.no_file)
            Bean.Project.this_project = ""
            mLuaEditor.setVisibility(4)
        end
    end
end
menu.add(res.string.close_other).onMenuItemClick = function(a)
    if mTab.getTabCount() ~= 1 then
        for i in pairs(tabTable) do
            local _o = tabTable[i].obj
            LuaFileUtil.write(Bean.Path.this_file, tostring(mLuaEditor.getText()))
            if _o ~= tab then
                tabTable[i] = nil
                mTab.removeTab(_o)
            end
        end
    end
end
menu.add(res.string.close_all).onMenuItemClick = function(a)
    for i in pairs(tabTable) do
        local _o = tabTable[i].obj
        LuaFileUtil.write(Bean.Path.this_file, tostring(mLuaEditor.getText()))
        tabTable[i] = nil
        mTab.removeTab(_o)
    end
    PathManager.update_this_file("")
    Bean.Project.this_project = ""
    activity.setTitle("NeLuaJ+")
    activity.getSupportActionBar().setSubtitle(res.string.no_file)
    mLuaEditor.setVisibility(4)
end
local menu1 = menu.addSubMenu(res.string.copy)
menu1.add(pathName).onMenuItemClick = function()
    copy(pathName)
end
-- 如果不在工程目录内就不添加这一项了
if not notProject then
    try
    menu1.add(_subfolder .. pathName).onMenuItemClick = function()
        copy(_subfolder .. pathName)
    end
end
end
menu1.add(path).onMenuItemClick = function ()
copy(path)
end
view.onLongClick = function (v)
popupMenu.show()
return true
end

view.setOnTouchListener(popupMenu.getDragToOpenListener())

-- 在table中保存tab对象
tabTable[path].obj = tab
tabTable[path].obj.tag ={}
-- 在tag中保存路径
tabTable[path].obj.tag.path= path
tabTable[path].obj.tag.first = path
mTab.addTab(tab,mTab.getTabCount())
--print"创建后选择tab"
tab.select()
end

function _M.remove(path)
if tabTable[path] ~= nil
mTab.removeTab(tabTable[path].obj)
tabTable[path] = nil
if mTab.getTabCount() == 0
Bean.Path.this_file = ""
activity.setTitle("NeLuaJ+")
activity.getSupportActionBar().setSubtitle(res.string.no_file)
mLuaEditor.setVisibility(4)
end
end
end

function _M.checkAll()
for i in pairs(tabTable) do
if not File(tabTable[i].obj.tag.path).exists()
_M.remove(tabTable[i].obj.tag.path)
end
end
end

return _M