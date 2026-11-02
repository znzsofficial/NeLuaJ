import "com.google.android.material.dialog.MaterialAlertDialogBuilder"
local ArrayListAdapter = bindClass "com.androlua.adapter.ArrayListAdapter"
local Toast = bindClass "android.widget.Toast"
local _M = {}
local res = res

-- 路由表：name → activities/ 下相对路径
local routes = {
  main             = "main/MainActivity.lua",
  home             = "home/HomeActivity.lua",
  editor           = "main/MainActivity.lua",
  axml             = "axml/CreatorActivity.lua",
  api              = "api/ApiActivity.lua",
  help             = "help/HelpActivity.lua",
  fix              = "fix/FixActivity.lua",
  photo            = "photo/PhotoActivity.lua",
  java             = "java/JavaEditorActivity.lua",
  layouthelper     = "layouthelper/LayoutHelperActivity.lua",
  resource         = "resource/ResourceBrowserActivity.lua",
  project_settings = "projectsettings/ProjectSettingsActivity.lua",
  media            = "media/MediaBrowserActivity.lua",
  agent_center     = "agent/AgentCenterActivity.lua",
}

local PENDING_KEY = "_nav_pending_v1"
local FAILED_KEY = "_nav_pending_failed_v1"
local sequence = 0
local MAX_PENDING_AGE = 10 * 60

function _M.route(name)
  return routes[name]
end

--- 脚本根目录锚点：子页环境（如编辑器 activities/main）的 getLuaDir
--- 带 /activities/... 后缀，统一剥掉；根 main.lua 环境无后缀原样返回。
--- 路由表全部相对脚本根的 activities/ 目录，禁止用子页 luaDir 拼路由。
function _M.assetsRoot()
  local dir = tostring(activity and activity.getLuaDir() or _M.lua_path or "")
  return (dir:gsub("/activities[/\\].*$", ""))
end

_M.lua_path = _M.assetsRoot()

function _M.path(name)
  local route = routes[name]
  if not route then return nil end
  return _M.assetsRoot() .. "/activities/" .. route
end

--- 打开页面：ActivityUtil.open("help") / open("project_settings", projectDir)
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
    -- Additive identity lets MainActivity deduplicate result-after-onResume.
    -- Existing action/payload consumers continue to receive the first two args.
    if #args <= 2 then
      local pending = _M.peekPending()
      if pending and pending.action == tostring(args[1])
          and pending.payload == tostring(args[2] or "") then
        args[2] = args[2] or ""
        args[3] = pending.id
      end
    end
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
  if a == "" or a:find("\n", 1, true) then return false end
  sequence = sequence + 1
  -- Unique per request, including two requests for the very same destination.
  local id = tostring(os.time()) .. ":" .. tostring(os.clock()) .. ":" .. tostring({}) .. ":" .. sequence
  local raw = "\30nav2:" .. id .. "\n" .. os.time() .. "\n" .. a .. "\n" .. p
  local ok, result = pcall(function()
    return this.setSharedData(PENDING_KEY, raw)
  end)
  return ok and result ~= false
end

function _M.peekPending()
  local raw
  pcall(function() raw = this.getSharedData(PENDING_KEY, nil) end)
  if type(raw) ~= "string" or raw == "" then return nil end
  local id, created, action, payload = raw:match("^\30nav2:([^\n]+)\n(%d+)\n([^\n]*)\n(.*)$")
  if not id then
    action, payload = raw:match("^(.-)\n(.*)$")
    action, payload = action or raw, payload or ""
  end
  local failed
  pcall(function() failed = this.getSharedData(FAILED_KEY, nil) end)
  return { action = action, payload = payload, id = id or raw, token = raw,
    expired = created ~= nil and os.time() - tonumber(created) > MAX_PENDING_AGE,
    blocked = failed == raw }
end

-- Compare-and-ack on the UI thread: never erase a replacement posted by a callback.
function _M.ackPending(pending)
  if not pending or not pending.token then return false end
  local ok, result = pcall(function()
    if this.getSharedData(PENDING_KEY, nil) ~= pending.token then return false end
    local written = this.setSharedData(PENDING_KEY, nil)
    if written == false then return false end
    if this.getSharedData(FAILED_KEY, nil) == pending.token then
      this.setSharedData(FAILED_KEY, nil)
    end
    return true
  end)
  return ok and result == true
end

-- Callback must positively report success. Failed requests remain available for
-- explicit retry/dismiss, but are not automatically replayed on every onResume.
function _M.consumePending(callback, pending, retry)
  pending = pending or _M.peekPending()
  if not pending then return false, "missing" end
  local current = _M.peekPending()
  if not current or current.token ~= pending.token then return false, "replaced", pending end
  if pending.blocked and not retry then return false, "blocked", pending end
  local ok, result, reason
  if pending.expired and not retry then
    ok, result, reason = true, false, "expired"
  else
    ok, result, reason = pcall(callback, pending.action, pending.payload)
  end
  if ok and result == true then
    if not _M.ackPending(pending) then return true, "unacknowledged", pending end
    return true, nil, pending
  end
  current = _M.peekPending()
  if current and current.token == pending.token then
    pcall(function() this.setSharedData(FAILED_KEY, pending.token) end)
  end
  return false, ok and (reason or "failed") or "failed", pending
end

-- Compatibility API; new navigation must use consumePending instead.
function _M.takePending()
  local pending = _M.peekPending()
  if pending and _M.ackPending(pending) then return pending end
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
