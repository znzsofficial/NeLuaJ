import "com.google.android.material.dialog.MaterialAlertDialogBuilder"
local ArrayListAdapter = bindClass "com.androlua.adapter.ArrayListAdapter"
local Toast = bindClass "android.widget.Toast"
local _M = {}
local res = res

_M.lua_path = activity.getLuaDir()

-- 路由表：name → { file, hasArg }
local routes = {
  main          = "main/MainActivity.lua",
  axml          = "axml/CreatorActivity.lua",
  api           = "api/ApiActivity.lua",
  help          = "help/HelpActivity.lua",
  setting       = "setting/SettingActivity.lua",
  fix           = "fix/FixActivity.lua",
  photo         = "photo/PhotoActivity.lua",
  java          = "java/JavaEditorActivity.lua",
  layouthelper  = "layouthelper/LayoutHelperActivity.lua",
  resource      = "resource/ResourceBrowserActivity.lua",
}

function _M.new(name, path)
  local route = routes[name]
  if not route then
    print("ActivityUtil: unknown route '" .. tostring(name) .. "'")
    return
  end
  local fullPath = _M.lua_path .. "/activities/" .. route
  if path then
    activity.newActivity(fullPath, { path })
  else
    activity.newActivity(fullPath)
  end
end

function _M.showLog(context)
  local logs = context.logs
  if not logs or logs.size() == 0 then
    Toast.makeText(context, res.string.logs .. ": 0", Toast.LENGTH_SHORT).show()
    return
  end

  local adapter = ArrayListAdapter(context, logs)
  local dialog = MaterialAlertDialogBuilder(context)
      .setTitle(res.string.logs)
      .setAdapter(adapter, function(_, i)
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
        logs.clear()
        Toast.makeText(context, res.string.clear, Toast.LENGTH_SHORT).show()
      end)
      .show()
  -- 自动滚动到最新日志
  local listView = dialog.getListView()
  if listView then
    listView.setSelection(adapter.getCount() - 1)
  end
end

return _M