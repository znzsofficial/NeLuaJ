import "com.google.android.material.dialog.MaterialAlertDialogBuilder"
local ArrayListAdapter = bindClass "com.androlua.adapter.ArrayListAdapter"
local _M ={}
local res = res

_M.lua_path = activity.getLuaDir()

function _M.new(para, path)
  switch para
   case "main"
    activity.newActivity(_M.lua_path.."/activities/main/MainActivity.lua")
   case "axml"
    activity.newActivity(_M.lua_path.."/activities/axml/CreatorActivity.lua")
   case "api"
    activity.newActivity(_M.lua_path.."/activities/api/ApiActivity.lua")
   case "help"
    activity.newActivity(_M.lua_path.."/activities/help/HelpActivity.lua")
   case "setting"
    activity.newActivity(_M.lua_path.."/activities/setting/SettingActivity")
   case "fix"
    activity.newActivity(_M.lua_path.."/activities/fix/FixActivity.lua", {path})
   case "photo"
    activity.newActivity(_M.lua_path.."/activities/photo/PhotoActivity.lua", {path})
   case "java"
    activity.newActivity(_M.lua_path.."/activities/java/JavaEditorActivity.lua", {path})
   case "layouthelper"
    activity.newActivity(_M.lua_path.."/activities/layouthelper/LayoutHelperActivity.lua", {path})
  end
end


function _M.showLog(context)
  local adapter = ArrayListAdapter(context, context.logs)
  local dialog = MaterialAlertDialogBuilder(context)
  .setTitle(res.string.logs)
  .setAdapter(adapter, function(dialog, i)
    local log = adapter.getItem(i)
    MaterialAlertDialogBuilder(context)
    .setMessage(log)
    .setPositiveButton(android.R.string.copy, function()
        context.getSystemService(context.CLIPBOARD_SERVICE).setText(log)
    end)
    .setNegativeButton(android.R.string.cancel, nil)
    .show()
  end)
  .setPositiveButton(android.R.string.ok, nil)
  .setNegativeButton(res.string.clear, function()
    context.logs.clear()
    MainActivity.Public.snack("日志已清空")
  end)
  .show()
  dialog.listView.setSelection(adapter.getCount() - 1)
end

return _M