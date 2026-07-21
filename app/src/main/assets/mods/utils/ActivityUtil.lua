import "com.google.android.material.dialog.MaterialAlertDialogBuilder"
local ArrayListAdapter = bindClass "com.androlua.adapter.ArrayListAdapter"
local Toast = bindClass "android.widget.Toast"
local _M = {}
local res = res

_M.lua_path = activity.getLuaDir()

-- 路由表：name → activities/ 下相对路径
local routes = {
  main             = "main/MainActivity.lua",
  axml             = "axml/CreatorActivity.lua",
  api              = "api/ApiActivity.lua",
  help             = "help/HelpActivity.lua",
  setting          = "setting/SettingActivity.lua",
  fix              = "fix/FixActivity.lua",
  photo            = "photo/PhotoActivity.lua",
  java             = "java/JavaEditorActivity.lua",
  layouthelper     = "layouthelper/LayoutHelperActivity.lua",
  resource         = "resource/ResourceBrowserActivity.lua",
  project_settings = "projectsettings/ProjectSettingsActivity.lua",
}

local PENDING_KEY = "_nav_pending_v1"

function _M.route(name)
  return routes[name]
end

function _M.path(name)
  local route = routes[name]
  if not route then return nil end
  return _M.lua_path .. "/activities/" .. route
end

--- 打开页面：ActivityUtil.open("setting") / open("project_settings", projectDir)
function _M.open(name, ...)
  local fullPath = _M.path(name)
  if not fullPath then
    print("ActivityUtil: unknown route '" .. tostring(name) .. "'")
    return false
  end
  local n = select("#", ...)
  if n <= 0 then
    activity.newActivity(fullPath)
  else
    local args = { ... }
    activity.newActivity(fullPath, args)
  end
  return true
end

--- 兼容旧 API：new(name) / new(name, path)
function _M.new(name, path)
  if path ~= nil and path ~= "" then
    return _M.open(name, path)
  end
  return _M.open(name)
end

--- 结束当前页并回传结果给父 Activity（走 onResult）
--- ActivityUtil.finishWith("open_file", path)
function _M.finishWith(...)
  local args = { ... }
  -- 同时写入 pending，防止 for-result 链路异常时丢失
  if #args >= 1 then
    _M.setPending(args[1], args[2])
  end
  pcall(function()
    this.result(args)
  end)
  return true
end

--- 跨页待办（SharedData 兜底，onResume 消费）
function _M.setPending(action, payload)
  local a = tostring(action or "")
  local p = tostring(payload or "")
  -- 单行 action + 换行 + payload（payload 可含路径）
  pcall(function()
    this.setSharedData(PENDING_KEY, a .. "\n" .. p)
  end)
end

function _M.takePending()
  local raw
  pcall(function()
    raw = this.getSharedData(PENDING_KEY, nil)
    this.setSharedData(PENDING_KEY, nil)
  end)
  if type(raw) ~= "string" or raw == "" then
    return nil
  end
  local action, payload = raw:match("^(.-)\n(.*)$")
  if not action then
    action = raw
    payload = ""
  end
  if action == "" then return nil end
  return { action = action, payload = payload }
end

function _M.peekPending()
  local raw
  pcall(function() raw = this.getSharedData(PENDING_KEY, nil) end)
  if type(raw) ~= "string" or raw == "" then return nil end
  local action, payload = raw:match("^(.-)\n(.*)$")
  if not action then
    return { action = raw, payload = "" }
  end
  return { action = action, payload = payload }
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
  local listView = dialog.getListView()
  if listView then
    listView.setSelection(adapter.getCount() - 1)
  end
end

return _M
