local preferences = activity.getSharedPreferences({{packageNameLua}} .. ".settings", 0)
local M = {}

function M.load()
  local ok, result = pcall(function()
    return {
      friendly = preferences.getBoolean("friendly", true),
      large = preferences.getBoolean("large", false),
    }
  end)
  if not ok then return nil, result end
  return result
end

function M.save(settings)
  local ok, result = pcall(function()
    assert(type(settings) == "table" and type(settings.friendly) == "boolean"
      and type(settings.large) == "boolean", "Invalid settings")
    local editor = preferences.edit()
    editor.putBoolean("friendly", settings.friendly)
    editor.putBoolean("large", settings.large)
    return editor.commit()
  end)
  return ok and result == true
end

return M
