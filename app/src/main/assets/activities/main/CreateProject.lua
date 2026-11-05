-- Public entry point. Functions stay in the caller; navigation returns data only.
local M = {}
function M.show(deps)
  local ok, result = pcall(function()
    return require("mods.utils.ActivityUtil").open("project_create")
  end)
  if not ok and deps and deps.snack then deps.snack(tostring(result)) end
  return ok and result ~= false
end
return M
