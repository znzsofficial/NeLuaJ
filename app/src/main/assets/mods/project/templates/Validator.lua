local Theme = require "mods.utils.ProjectTheme"
local Registry = require "mods.project.templates.Registry"
local M = {}
local function reserved(part)
  local base = part:match("^[^.]+") or part
  base = base:upper()
  return base == "CON" or base == "PRN" or base == "AUX" or base == "NUL" or base:match("^COM[1-9]$") or base:match("^LPT[1-9]$")
end

function M.relativePath(path)
  if type(path) ~= "string" or path == "" or path:find("[%z\1-\31\\:]") or path:sub(1, 1) == "/" then return false end
  if path:sub(-1) == "/" or path:find("//", 1, true) then return false end
  for part in path:gmatch("[^/]+") do
    if part == "." or part == ".." or part:match("[%. ]$") or reserved(part) or part:find('[<>"|?*]') then return false end
  end
  return true
end

local function contains(list, value)
  for _, item in ipairs(list or {}) do if item == value then return true end end
  return false
end

local keywords = {}
for word in ("abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while true false null _"):gmatch("%S+") do keywords[word] = true end

function M.packageName(value)
  if type(value) ~= "string" or not value:find(".", 1, true) or value:find("..", 1, true) or value:match("^%.") or value:match("%.$") then return false end
  for segment in value:gmatch("[^.]+") do
    if not segment:match("^[A-Za-z_][A-Za-z_0-9]*$") or keywords[segment] then return false end
  end
  return true
end

function M.validate(options, manifest)
  assert(type(options) == "table", "options must be a table")
  local name = options.appName
  assert(type(name) == "string" and name ~= "" and name:match("%S"), "application name is required")
  assert(#name <= 180 and name == name:match("^%s*(.-)%s*$") and not name:find("[/\\%z\1-\31:<>|?*]") and name ~= "." and name ~= ".." and not name:match("[%. ]$"), "invalid application name")
  assert(not reserved(name), "reserved application name")
  assert(M.packageName(options.packageName), "invalid package name")
  local root = options.rootPath
  assert(type(root) == "string" and root ~= "" and not root:find("[%z\1-\31]"), "rootPath is required")
  root = root:gsub("\\", "/"):gsub("/+$", "")
  if root == "" then root = "/" end
  if root:match("^[A-Za-z]:$") and options.rootPath:match("[/\\]$") then root = root .. "/" end
  assert(root:sub(1, 1) == "/" or root:match("^[A-Za-z]:/"), "rootPath must be absolute")
  for part in root:gmatch("[^/]+") do assert(part ~= "." and part ~= "..", "rootPath must not contain traversal") end
  local theme = options.themeName or Theme.DEFAULT
  assert(Theme.find(theme), "unknown theme")
  local family = Theme.isCompat(theme) and "compat" or (Theme.isMaterialComponent(theme) and "mc" or (Theme.isDynamic(theme) and "dynamic" or "m3"))
  assert(contains(manifest.themeFamilies, family), "template does not support theme family: " .. family)
  local defaults = manifest.defaults or {}
  local function boolean(key, fallback)
    local value = options[key]
    if value == nil then value = defaults[key] end
    if value == nil then value = fallback end
    assert(type(value) == "boolean", key .. " must be boolean")
    return value
  end
  local internet, debugMode = boolean("useInternet", false), boolean("debugMode", true)
  local required = manifest.requiredPermissions or {}
  assert(not contains(required, "INTERNET") or internet, "template requires INTERNET permission")
  local capabilities = manifest.optionalCapabilities or {}
  assert(not internet or contains(required, "INTERNET") or contains(capabilities, "internet"), "template does not allow internet capability")
  assert(options.debugMode == nil or contains(capabilities, "debug"), "template does not allow debug override")
  local modules, seen = {}, {}
  assert(options.modules == nil or type(options.modules) == "table", "modules must be an array")
  local moduleCount, lastModule = 0, 0
  for key, id in pairs(options.modules or {}) do
    assert(type(key) == "number" and key >= 1 and key % 1 == 0, "modules must be a dense array")
    moduleCount = moduleCount + 1
    lastModule = math.max(lastModule, key)
    assert(type(id) == "string" and Registry.MODULES[id], "unknown module: " .. tostring(id))
  end
  assert(moduleCount == lastModule, "modules must be a dense array")
  for _, id in ipairs(options.modules or {}) do
    assert(not seen[id], "duplicate module: " .. id)
    seen[id] = true
    modules[#modules + 1] = id
  end
  assert(#modules == 0 or contains(capabilities, "modules"), "template does not allow modules")
  local permissions, permissionSet = {}, {}
  for _, permission in ipairs(required) do
    assert(type(permission) == "string" and permission:match("^[A-Z_]+$"), "invalid required permission")
    if not permissionSet[permission] then permissions[#permissions + 1] = permission; permissionSet[permission] = true end
  end
  if internet and not permissionSet.INTERNET then permissions[#permissions + 1] = "INTERNET" end
  return { templateId = manifest.id, appName = name, packageName = options.packageName,
    themeName = theme, themeFamily = family, hasSystemActionBar = Theme.hasSystemActionBar(theme),
    rootPath = root, projectPath = root .. (root:sub(-1) == "/" and "" or "/") .. name,
    useInternet = internet, debugMode = debugMode, modules = modules, permissions = permissions }
end

return M
