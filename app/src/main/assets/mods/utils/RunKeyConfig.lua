--- 工具栏运行键行为（设置页 / MainActivity 共用）
--- mode: "menu" | "file" | "project"
--- 默认 menu：有工程时弹出菜单；无工程仍直接运行当前文件
local _M = {}

import "com.google.android.material.dialog.MaterialAlertDialogBuilder"

_M.MODE_MENU = "menu"
_M.MODE_FILE = "file"
_M.MODE_PROJECT = "project"

_M.MODES = {
  _M.MODE_MENU,
  _M.MODE_FILE,
  _M.MODE_PROJECT,
}

function _M.isValidMode(mode)
  return mode == _M.MODE_MENU
      or mode == _M.MODE_FILE
      or mode == _M.MODE_PROJECT
end

function _M.resolve(getShared)
  local mode = getShared("run_key_mode", nil)
  if _M.isValidMode(mode) then
    return mode
  end
  return _M.MODE_MENU
end

function _M.getMode(ctx)
  ctx = ctx or this
  return _M.resolve(function(key, fallback)
    return ctx.getSharedData(key, fallback)
  end)
end

function _M.setMode(ctx, mode)
  ctx = ctx or this
  if not _M.isValidMode(mode) then
    mode = _M.MODE_MENU
  end
  ctx.setSharedData("run_key_mode", mode)
  return mode
end

function _M.label(mode)
  if mode == _M.MODE_FILE then
    return res.string.run_key_mode_file
  end
  if mode == _M.MODE_PROJECT then
    return res.string.run_key_mode_project
  end
  return res.string.run_key_mode_menu
end

function _M.labels()
  return {
    res.string.run_key_mode_menu,
    res.string.run_key_mode_file,
    res.string.run_key_mode_project,
  }
end

function _M.indexOf(mode)
  for i, m in ipairs(_M.MODES) do
    if m == mode then return i end
  end
  return 1
end

--- 单选对话框（与设置页一致）；onPicked(mode) 可选
function _M.showPicker(ctx, onPicked)
  ctx = ctx or this
  local current = _M.getMode(ctx)
  local labels = _M.labels()
  local checked = _M.indexOf(current) - 1
  MaterialAlertDialogBuilder(ctx)
    .setTitle(res.string.run_key_mode)
    .setSingleChoiceItems(labels, checked, function(_, which)
      checked = which
    end)
    .setPositiveButton(android.R.string.ok, function()
      local mode = _M.MODES[checked + 1]
      if not mode then mode = _M.MODE_MENU end
      _M.setMode(ctx, mode)
      if onPicked then onPicked(mode) end
    end)
    .setNegativeButton(android.R.string.cancel, nil)
    .show()
end

return _M
