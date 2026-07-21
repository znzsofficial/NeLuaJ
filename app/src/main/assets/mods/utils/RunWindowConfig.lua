--- 运行窗口模式（轻量，设置页 / Init 共用）
--- mode: "off" | "freeform" | "adjacent"
--- 兼容旧 SharedData 键 run_in_window=true → freeform
local _M = {}

_M.MODE_OFF = "off"
_M.MODE_FREEFORM = "freeform"
_M.MODE_ADJACENT = "adjacent"

_M.MODES = {
  _M.MODE_OFF,
  _M.MODE_FREEFORM,
  _M.MODE_ADJACENT,
}

local function isTruthy(value)
  return value == true or value == "true" or value == 1
end

function _M.isValidMode(mode)
  return mode == _M.MODE_OFF
      or mode == _M.MODE_FREEFORM
      or mode == _M.MODE_ADJACENT
end

--- @param getShared fun(key, fallback): any
function _M.resolve(getShared)
  local mode
  pcall(function()
    mode = getShared("run_window_mode", nil)
  end)
  if _M.isValidMode(mode) then
    return mode
  end
  local legacy
  pcall(function()
    legacy = getShared("run_in_window", false)
  end)
  if isTruthy(legacy) then
    return _M.MODE_FREEFORM
  end
  return _M.MODE_OFF
end

--- 从 Activity / this 解析
function _M.getMode(ctx)
  ctx = ctx or this
  -- LuaJ 保留字：参数名不能用 default
  return _M.resolve(function(key, fallback)
    return ctx.getSharedData(key, fallback)
  end)
end

--- 写入；同步旧键 run_in_window（仅 freeform 为 true）
function _M.setMode(ctx, mode)
  ctx = ctx or this
  if not _M.isValidMode(mode) then
    mode = _M.MODE_OFF
  end
  pcall(function()
    ctx.setSharedData("run_window_mode", mode)
    ctx.setSharedData("run_in_window", mode == _M.MODE_FREEFORM)
  end)
  return mode
end

function _M.label(mode)
  if mode == _M.MODE_FREEFORM then
    return res.string.run_window_mode_freeform
  end
  if mode == _M.MODE_ADJACENT then
    return res.string.run_window_mode_adjacent
  end
  return res.string.run_window_mode_off
end

function _M.labels()
  return {
    res.string.run_window_mode_off,
    res.string.run_window_mode_freeform,
    res.string.run_window_mode_adjacent,
  }
end

function _M.indexOf(mode)
  for i, m in ipairs(_M.MODES) do
    if m == mode then return i end
  end
  return 1
end

return _M
