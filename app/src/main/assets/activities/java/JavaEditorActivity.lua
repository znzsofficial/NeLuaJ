---@diagnostic disable: undefined-global
require "environment"
import "res"
local ColorUtil = this.globalData.ColorUtil
local LuaFileUtil = luajava.bindClass "com.nekolaska.io.LuaFileUtil".INSTANCE
local File = bindClass "java.io.File"
local path = tostring(...)
this.dynamicColor()
activity.setContentView(res.layout.java_layout)

function onCreateOptionsMenu(menu)
    local ColorTitle = ColorUtil.getColorOnBackground();
    local menu_show = 2; --MenuItem.SHOW_AS_ACTION_ALWAYS;
    menu.add("撤销")
        .setShowAsAction(menu_show)
        .setIcon(this.getResDrawable("undo", ColorTitle))
        .onMenuItemClick = function(a)
        mEditor.undo()
    end
    menu.add("重做")
        .setShowAsAction(menu_show)
        .setIcon(this.getResDrawable("redo", ColorTitle))
        .onMenuItemClick = function(a)
        mEditor.redo()
    end
    --[[
    menu.add("保存")
    .setShowAsAction(menu_show)
    .onMenuItemClick=function(a)
      LuaFileUtil.write(path, tostring(mEditor.getText()))
    end]]
end

mEditor.post(function()
    if File(path).exists() then
        mEditor.setText(LuaFileUtil.read(path))
        activity.setTitle(File(path).getName())
    else
        mEditor.setText("")
        activity.setTitle(res.string.no_file)
    end
    mEditor.setTypeface(res.font.code)
end)