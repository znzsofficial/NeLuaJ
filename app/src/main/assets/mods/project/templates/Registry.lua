-- Only bundled, declarative manifests are registered; no user-supplied Lua is loaded.
local M = {}
M.IDS = { "blank", "form", "list", "navigation", "settings", "webview" }
M.MODULES = {
  time = { source = "templates/shared/modules/TimeMeter.lua", path = "mods/TimeMeter.lua" },
  array = { source = "templates/shared/modules/Array.lua", path = "mods/Array.lua" },
  strings = { source = "templates/shared/modules/Strings.lua", path = "mods/Strings.lua" },
  anim = { source = "templates/shared/modules/ObjectAnimator.lua", path = "mods/ObjectAnimator.lua" },
  rxlua = { source = "rx.lua", path = "mods/rx.lua" },
  vconsole = { source = "vConsole.lua", path = "vConsole.lua" },
}

local function copy(value, seen)
  if type(value) ~= "table" then
    assert(type(value) == "string" or type(value) == "number" or type(value) == "boolean", "manifest must contain only data")
    return value
  end
  seen = seen or {}
  assert(not seen[value], "cyclic manifest")
  assert(getmetatable(value) == nil, "manifest metatables are not allowed")
  seen[value] = true
  local result = {}
  for key, item in pairs(value) do
    assert(type(key) == "string" or type(key) == "number", "invalid manifest key")
    result[key] = copy(item, seen)
  end
  seen[value] = nil
  return result
end

function M.get(id)
  for _, known in ipairs(M.IDS) do
    if id == known then
      local manifest = copy(require("templates." .. id .. ".manifest"))
      assert(manifest.id == id and manifest.version ~= nil, "invalid manifest identity: " .. id)
      return manifest
    end
  end
  return nil
end

function M.list()
  local list = {}
  for _, id in ipairs(M.IDS) do list[#list + 1] = M.get(id) end
  return list
end

return M
