import "com.google.android.material.dialog.MaterialAlertDialogBuilder"
local ArrayAdapter = bindClass "android.widget.ArrayAdapter"
local _M ={}
local:res

_M.lua_path = activity.getLuaDir()

function _M.new(para, path)
  switch para
   case "main"
    activity.newActivity(_M.lua_path.."/activities/znzsofficial/main/MainActivity.lua")
   case "axml"
    activity.newActivity(_M.lua_path.."/activities/znzsofficial/axml/CreatorActivity.lua")
   case "api"
    activity.newActivity(_M.lua_path.."/activities/znzsofficial/api/ApiActivity.lua")
   case "help"
    activity.newActivity(_M.lua_path.."/activities/znzsofficial/help/HelpActivity.lua")
   case "setting"
    activity.newActivity(_M.lua_path.."/activities/znzsofficial/setting/SettingActivity")
   case "fix"
    activity.newActivity(_M.lua_path.."/activities/znzsofficial/fix/FixActivity.lua", {path})
   case "photo"
    activity.newActivity(_M.lua_path.."/activities/znzsofficial/photo/PhotoActivity.lua", {path})
   case "java"
    activity.newActivity(_M.lua_path.."/activities/znzsofficial/java/JavaEditorActivity.lua", {path})
   case "layouthelper"
    activity.newActivity(_M.lua_path.."/activities/znzsofficial/layouthelper/LayoutHelperActivity.lua", {path})
  end
end

local function adapter(t)
  return ArrayAdapter(activity,android.R.layout.simple_list_item_1,t)
end

function _M.showLog(context)
  local logAdapter = adapter(context.getLogs())
  local dialog = MaterialAlertDialogBuilder(context)
  .setTitle(res.string.logs)
  .setAdapter(logAdapter, nil)
  .setPositiveButton(android.R.string.ok, nil)
  .setNegativeButton(res.string.clear, function()
    context.getLogs().clear()
    MainActivity.Public.snack("日志已清空")
  end)
  .show()
  dialog.listView.setSelection(logAdapter.getCount() - 1)
end

return _M