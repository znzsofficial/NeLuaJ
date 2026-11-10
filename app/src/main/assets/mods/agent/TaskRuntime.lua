-- Android adapters for the owner-thread task registry. No Activity lifecycle owns
-- these timers: a destroyed screen must not silently discard task bookkeeping.
local M = {}
local handler, clock, uuid, log, looper
local function platform()
  if handler then return end
  looper = luajava.bindClass('android.os.Looper')
  clock = luajava.bindClass('android.os.SystemClock')
  uuid = luajava.bindClass('java.util.UUID')
  log = luajava.bindClass('android.util.Log')
  handler = luajava.bindClass('android.os.Handler')(looper.getMainLooper())
end

function M.clockMillis()
  platform()
  -- Same monotonic time base as Handler.postDelayed; excludes deep sleep.
  return tonumber(clock.uptimeMillis())
end

function M.idFactory()
  platform()
  return tostring(uuid.randomUUID())
end

function M.isOwnerThread()
  platform()
  return looper.getMainLooper().isCurrentThread()
end

function M.scheduleTimeout(delayMs, callback)
  platform()
  local active = true
  -- Keep the proxy identity, rather than coercing the same Lua function twice.
  local runnable = luajava.createProxy('java.lang.Runnable', {run=function()
    if not active then return end
    active = false
    callback()
  end})
  assert(handler.postDelayed(runnable, math.max(0, math.floor(delayMs))), 'Task timer dispatcher stopped')
  return function()
    if not active then return end
    active = false
    handler.removeCallbacks(runnable)
  end
end

function M.postToOwner(callback)
  platform()
  if M.isOwnerThread() then return callback() end
  local runnable = luajava.createProxy('java.lang.Runnable', {run=callback})
  assert(handler.post(runnable), 'Task owner dispatcher stopped')
end

function M.onDiagnostic(event)
  platform()
  -- Allowlist metadata only: never log parameters, result text, headers or paths.
  local fields = {}
  for _,key in ipairs({'taskId','name','event','executionState','waitState','cancelReason','elapsedMs','transactionId'}) do
    local value = event and event[key]
    if type(value)=='string' or type(value)=='number' or type(value)=='boolean' then
      fields[#fields+1] = key..'='..tostring(value):gsub('%c',' '):sub(1,128)
    end
  end
  log.d('AgentTask',table.concat(fields,' '))
end

return M
