-- Both entry files live at project root, so their resource/module base is identical.
local M = {}

function M.openDetail(message)
  local path = activity.getLuaPath("detail.lua")
  activity.newActivity(path, { message })
end

return M
