local Validator = require "mods.project.templates.Validator"
local Registry = require "mods.project.templates.Registry"
local M = {}

function M.luaQuote(value)
  return '"' .. value:gsub('[%z\1-\31\\"\127]', function(char)
    if char == "\\" then return "\\\\" end
    if char == '"' then return '\\"' end
    return string.format("\\%03d", char:byte())
  end) .. '"'
end

local function text(value)
  return (value:gsub("[&<>]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" }):gsub("([\\`*_{}%[%]#!|])", "\\%1"))
end

function M.tokens(config)
  local permissions = {}
  for _, permission in ipairs(config.permissions) do permissions[#permissions + 1] = M.luaQuote(permission) end
  return { appNameLua = M.luaQuote(config.appName), packageNameLua = M.luaQuote(config.packageName),
    themeNameLua = M.luaQuote(config.themeName), debugModeLua = tostring(config.debugMode),
    useInternetLua = tostring(config.useInternet), hasSystemActionBarLua = tostring(config.hasSystemActionBar),
    permissionsLua = "{" .. table.concat(permissions, ", ") .. "}",
    appNameText = text(config.appName), packageNameText = text(config.packageName), themeNameText = text(config.themeName) }
end

function M.render(source, tokens)
  assert(type(source) == "string", "asset reader must return text")
  -- Scan the template, never the replacement: literal {{...}} in user text stays literal.
  local cursor, output = 1, {}
  while true do
    local first, last, key = source:find("{{([A-Za-z][A-Za-z0-9]*)}}", cursor)
    local part = source:sub(cursor, first and first - 1 or #source)
    assert(not part:find("{{", 1, true) and not part:find("}}", 1, true), "malformed template placeholder")
    output[#output + 1] = part
    if not first then break end
    assert(tokens[key] ~= nil, "unknown template placeholder: " .. key)
    output[#output + 1] = tokens[key]
    cursor = last + 1
  end
  return table.concat(output)
end

function M.files(manifest, config, readAsset, onFile)
  local result, paths, hasMain = {}, { ["init.lua"] = true }, false
  local tokens = M.tokens(config)
  local function add(path, source, raw)
    if onFile then onFile(path) end
    assert(Validator.relativePath(path), "invalid output path: " .. tostring(path))
    assert(Validator.relativePath(source), "invalid source path: " .. tostring(source))
    local folded = path:lower()
    assert(not paths[folded], "duplicate output path: " .. path)
    for existing in pairs(paths) do
      assert(existing:sub(1, #folded + 1) ~= folded .. "/" and folded:sub(1, #existing + 1) ~= existing .. "/", "file/directory conflict: " .. path)
    end
    paths[folded] = true
    if path == "main.lua" then hasMain = true end
    local content = readAsset(source)
    assert(type(content) == "string", "asset missing: " .. source)
    result[#result + 1] = { path = path, content = raw and content or M.render(content, tokens) }
  end
  assert(type(manifest.files) == "table" and #manifest.files > 0, "manifest has no files")
  for _, file in ipairs(manifest.files) do
    local selected = true
    for key, value in pairs(file.when or {}) do
      assert(key == "themeFamily" or key == "systemActionBar", "unknown file condition: " .. key)
      local actual = key == "themeFamily" and config.themeFamily or config.hasSystemActionBar
      if actual ~= value then selected = false end
    end
    if selected then
      assert(Validator.relativePath(file.source), "invalid template source")
      assert(file.sourceRoot == nil or file.sourceRoot == "shared", "unknown sourceRoot")
      local source = file.source:sub(1, 17) == "templates/shared/" and file.source or
        (file.sourceRoot == "shared" and "templates/shared/files/" or "templates/" .. manifest.id .. "/files/") .. file.source
      add(file.path, source, file.raw == true)
    end
  end
  for _, id in ipairs(config.modules) do
    local item = Registry.MODULES[id]
    add(item.path, item.source, true)
    if id == "vconsole" then
      local main
      for _, file in ipairs(result) do if file.path == "main.lua" then main = file end end
      assert(main, "vConsole requires main.lua")
      main.content = main.content .. '\nrequire "vConsole"\n'
    end
  end
  if #config.modules > 0 then
    add("MODULES.md", "templates/shared/modules/README.md", true)
  end
  assert(hasMain, "template must produce main.lua")
  result[#result + 1] = { path = "init.lua", content = table.concat({
    "app_name = " .. tokens.appNameLua, "package_name = " .. tokens.packageNameLua,
    'ver_name = "1.0"', 'ver_code = "1"', 'min_sdk = "26"', 'target_sdk = "33"',
    "debug_mode = " .. tokens.debugModeLua, "NeLuaJ_Theme = " .. tokens.themeNameLua,
    "user_permission = " .. tokens.permissionsLua, "",
  }, "\n") }
  return result
end

return M
