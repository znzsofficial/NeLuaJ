--- Home consumes only creator results. Shared pending identity prevents duplicate
--- launches when Android delivers onResume and onResult for the same request.
local M = {}
function M.new(deps)
  local nav = deps.navigation
  local completed, order = {}, {}
  local controller = {}
  local function supported(action)
    return action == "open_project" or action == "project_created"
  end
  local function handle(action, path)
    if not supported(action) then return false, "invalid" end
    if not deps.hasPermission() then return false, "permission" end
    if type(path) ~= "string" or path == "" or not deps.isDirectory(path) then
      return false, "project_missing"
    end
    if action == "project_created" then deps.refresh() return true end
    if not deps.isFile(path .. "/main.lua") then return false, "file_missing" end
    return deps.open(path) == true
  end
  function controller.process(retry, expected)
    if not deps.alive() then return false end
    local pending = expected or nav.peekPending()
    if not pending or not supported(pending.action) then return false end
    local ok, reason = nav.consumePending(function(action, path)
      -- An acknowledgement can fail after launch; retry the ack, not the launch.
      if completed[pending.id] then return true end
      return handle(action, path)
    end, pending, retry)
    if ok and not completed[pending.id] then
      completed[pending.id] = true
      order[#order + 1] = pending.id
      if #order > 8 then completed[table.remove(order, 1)] = nil end
    end
    if (not ok and reason ~= "replaced") or reason == "unacknowledged" then
      deps.failure(pending, reason, retry)
    end
    return ok
  end
  function controller.result(action, path, requestId)
    if not deps.alive() or not supported(action) then return false end
    if requestId and completed[requestId] then return true end
    local pending = nav.peekPending()
    if pending then
      if requestId and pending.id ~= requestId then return false end
      if pending.action ~= action or pending.payload ~= tostring(path or "") then return false end
      return controller.process(false, pending)
    end
    if nav.setPending(action, path) then return controller.process(false) end
    deps.failure({ action = action, payload = path, id = requestId }, "failed", false)
    return false
  end
  return controller
end
return M
