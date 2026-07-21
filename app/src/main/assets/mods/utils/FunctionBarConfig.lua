--- 功能栏配置（轻量，可在设置页 require，不依赖 EditorUtil / SelectMain）
local _M = {}

-- id + 文案 key（稳定 id 用于 SharedData）
local CATALOG = {
  { id = "save", titleKey = "save_file" },
  { id = "backup", titleKey = "backup" },
  { id = "format", titleKey = "format" },
  { id = "undo", titleKey = "undo" },
  { id = "redo", titleKey = "redo" },
  { id = "search", titleKey = "search" },
  { id = "check_error", titleKey = "check_error" },
  { id = "compile", titleKey = "compile" },
  { id = "analysis_import", titleKey = "analysis_import" },
  { id = "java_editor", titleKey = "java_editor" },
  { id = "layout_helper", titleKey = "layout_helper" },
  { id = "api", titleKey = "api_title" },
  { id = "resource", titleKey = "resource_browser" },
  { id = "build", titleKey = "build" },
  { id = "create_project", titleKey = "create_project" },
  { id = "project_settings", titleKey = "project_settings" },
  { id = "run", titleKey = "run_code" },
  { id = "logs", titleKey = "logs" },
  { id = "setting", titleKey = "setting" },
  { id = "help", titleKey = "help" },
}

local DEFAULT_IDS = {
  "save", "backup", "format", "analysis_import", "api", "resource",
  "search", "build", "create_project", "project_settings", "setting", "help",
}

local function catalogById()
  local map = {}
  for _, item in ipairs(CATALOG) do
    map[item.id] = item
  end
  return map
end

function _M.resolveTitle(item)
  if not item then return "" end
  if item.titleKey == "java_editor" then
    return "Java" .. (res.string.editor or "Editor")
  end
  local t = res.string[item.titleKey]
  if t and t ~= "" then return t end
  return item.id
end

function _M.getCatalog()
  local list = {}
  for _, item in ipairs(CATALOG) do
    list[#list + 1] = {
      id = item.id,
      titleKey = item.titleKey,
      title = _M.resolveTitle(item),
    }
  end
  return list
end

function _M.getDefaultIds()
  local copy = {}
  for i, id in ipairs(DEFAULT_IDS) do
    copy[i] = id
  end
  return copy
end

function _M.parseIds(raw)
  if type(raw) ~= "string" or raw == "" then
    return nil
  end
  local map = catalogById()
  local ids = {}
  local seen = {}
  for line in (raw .. "\n"):gmatch("(.-)\n") do
    local id = line:match("^%s*(.-)%s*$")
    if id ~= "" and map[id] and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  return #ids > 0 and ids or nil
end

function _M.getItem(id)
  return catalogById()[id]
end

return _M
