--- init.lua 读写：补丁更新已知字段，保留注释与未知键
--- 兼容 LuaActivity.initENV：theme / NeLuaJ_Theme、appname / app_name、debugmode / debug_mode
local _M = {}

-- 写入顺序（新建文件）
local MANAGED_ORDER = {
  "app_name",
  "package_name",
  "ver_name",
  "ver_code",
  "min_sdk",
  "target_sdk",
  "debug_mode",
  "NeLuaJ_Theme",
  "user_permission",
}

-- 补丁时会改写的键（含旧别名）
local MANAGED = {
  app_name = true,
  appname = true,
  package_name = true,
  ver_name = true,
  ver_code = true,
  version_name = true,
  version_code = true,
  min_sdk = true,
  target_sdk = true,
  debug_mode = true,
  debugmode = true,
  NeLuaJ_Theme = true,
  theme = true, -- 仅当值为 Theme_NeLuaJ_* 或与 NeLuaJ 同步时改写
  user_permission = true,
}

function _M.luaQuote(s)
  s = tostring(s or "")
  s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r")
  return '"' .. s .. '"'
end

function _M.isNeLuaJThemeName(name)
  name = tostring(name or "")
  return name:find("^Theme_NeLuaJ_") ~= nil
end

function _M.formatSimple(key, value)
  if key == "debug_mode" or key == "debugmode" then
    if value == true or value == "true" or value == 1 or value == "1" then
      return "true"
    end
    return "false"
  end
  -- theme 若是数字资源 id，原样输出数字
  if (key == "theme") and type(value) == "number" then
    return tostring(math.floor(value))
  end
  if (key == "theme") and tostring(value):match("^%d+$") then
    return tostring(value)
  end
  return _M.luaQuote(value)
end

function _M.formatPermissions(list)
  if type(list) ~= "table" or #list == 0 then
    return "user_permission = {\n}"
  end
  local lines = { "user_permission = {" }
  for _, p in ipairs(list) do
    lines[#lines + 1] = "  " .. _M.luaQuote(p) .. ","
  end
  lines[#lines + 1] = "}"
  return table.concat(lines, "\n")
end

function _M.build(fields)
  fields = fields or {}
  local lines = {}
  for _, key in ipairs(MANAGED_ORDER) do
    if key == "user_permission" then
      lines[#lines + 1] = _M.formatPermissions(fields.user_permission or {})
    elseif fields[key] ~= nil then
      lines[#lines + 1] = key .. " = " .. _M.formatSimple(key, fields[key])
    end
  end
  -- 新建默认只写 NeLuaJ_Theme；若显式要求同步 legacy theme 字符串
  if fields.sync_legacy_theme and fields.NeLuaJ_Theme then
    lines[#lines + 1] = "theme = " .. _M.luaQuote(fields.NeLuaJ_Theme)
  end
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function splitLines(text)
  local lines = {}
  text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  if text == "" then return lines end
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

local function lineKey(line)
  return line:match("^%s*([%a_][%w_]*)%s*=")
end

local function lineIndent(line)
  return line:match("^(%s*)") or ""
end

local function appendBlock(out, block, indent)
  indent = indent or ""
  local first = true
  for bl in (block .. "\n"):gmatch("(.-)\n") do
    if first then
      out[#out + 1] = indent .. bl
      first = false
    else
      out[#out + 1] = bl
    end
  end
end

local function skipTableBlock(lines, startIdx)
  local i = startIdx
  local depth = 0
  local started = false
  while i <= #lines do
    local line = lines[i]
    for c in line:gmatch("[{}]") do
      if c == "{" then
        depth = depth + 1
        started = true
      elseif c == "}" then
        depth = depth - 1
      end
    end
    if started and depth <= 0 then
      return i + 1
    end
    i = i + 1
  end
  return startIdx + 1
end

--- 从 raw 里解析 theme 赋值是否为 NeLuaJ 风格字符串
local function themeLineIsNeLuaJ(line)
  local q = line:match("=%s*[\"'](.-)[\"']")
  if q and _M.isNeLuaJThemeName(q) then return true end
  return false
end

--- 将 fields 补丁进 raw；保留注释与未知键
--- fields.NeLuaJ_Theme 为主；若存在可同步的 legacy theme 行则一并更新
function _M.patch(raw, fields)
  fields = fields or {}
  if raw == nil or raw == "" then
    return _M.build(fields)
  end
  local lines = splitLines(raw)
  local out = {}
  local found = {}
  local hasLegacyThemeLine = false
  local legacyThemeIsNeLuaJ = false
  local hasNeLuaJThemeLine = false

  -- 先扫一遍
  for _, line in ipairs(lines) do
    local key = lineKey(line)
    if key == "theme" then
      hasLegacyThemeLine = true
      if themeLineIsNeLuaJ(line) then legacyThemeIsNeLuaJ = true end
    elseif key == "NeLuaJ_Theme" then
      hasNeLuaJThemeLine = true
    end
  end

  local i = 1
  while i <= #lines do
    local line = lines[i]
    local key = lineKey(line)
    local indent = lineIndent(line)

    if key == "user_permission" and fields.user_permission ~= nil then
      found.user_permission = true
      appendBlock(out, _M.formatPermissions(fields.user_permission or {}), indent)
      i = skipTableBlock(lines, i)
    elseif key == "NeLuaJ_Theme" and fields.NeLuaJ_Theme ~= nil then
      found.NeLuaJ_Theme = true
      out[#out + 1] = indent .. "NeLuaJ_Theme = " .. _M.formatSimple("NeLuaJ_Theme", fields.NeLuaJ_Theme)
      i = i + 1
    elseif key == "theme" and fields.NeLuaJ_Theme ~= nil then
      -- 仅当原 theme 已是 NeLuaJ 风格，或显式 sync_legacy_theme，才改写成同一主题名
      -- 数字 / android.R.style 字符串保留不动
      if legacyThemeIsNeLuaJ or fields.sync_legacy_theme then
        found.theme = true
        out[#out + 1] = indent .. "theme = " .. _M.luaQuote(fields.NeLuaJ_Theme)
      else
        out[#out + 1] = line
      end
      i = i + 1
    elseif key == "app_name" and fields.app_name ~= nil then
      found.app_name = true
      out[#out + 1] = indent .. "app_name = " .. _M.formatSimple("app_name", fields.app_name)
      i = i + 1
    elseif key == "appname" and fields.app_name ~= nil then
      -- 旧键同步为相同显示名
      found.appname = true
      out[#out + 1] = indent .. "appname = " .. _M.formatSimple("appname", fields.app_name)
      i = i + 1
    elseif key == "package_name" and fields.package_name ~= nil then
      found.package_name = true
      out[#out + 1] = indent .. "package_name = " .. _M.formatSimple("package_name", fields.package_name)
      i = i + 1
    elseif (key == "ver_name" or key == "version_name") and fields.ver_name ~= nil then
      found[key] = true
      out[#out + 1] = indent .. key .. " = " .. _M.formatSimple(key, fields.ver_name)
      i = i + 1
    elseif (key == "ver_code" or key == "version_code") and fields.ver_code ~= nil then
      found[key] = true
      out[#out + 1] = indent .. key .. " = " .. _M.formatSimple(key, fields.ver_code)
      i = i + 1
    elseif key == "min_sdk" and fields.min_sdk ~= nil then
      found.min_sdk = true
      out[#out + 1] = indent .. "min_sdk = " .. _M.formatSimple("min_sdk", fields.min_sdk)
      i = i + 1
    elseif key == "target_sdk" and fields.target_sdk ~= nil then
      found.target_sdk = true
      out[#out + 1] = indent .. "target_sdk = " .. _M.formatSimple("target_sdk", fields.target_sdk)
      i = i + 1
    elseif (key == "debug_mode" or key == "debugmode") and fields.debug_mode ~= nil then
      found[key] = true
      out[#out + 1] = indent .. key .. " = " .. _M.formatSimple(key, fields.debug_mode)
      i = i + 1
    else
      out[#out + 1] = line
      i = i + 1
    end
  end

  -- 补全缺失托管字段
  local function need(key)
    return fields[key] ~= nil and not found[key]
  end

  local toAppend = {}
  if need("app_name") and not found.appname then
    toAppend[#toAppend + 1] = "app_name = " .. _M.formatSimple("app_name", fields.app_name)
  end
  if need("package_name") then
    toAppend[#toAppend + 1] = "package_name = " .. _M.formatSimple("package_name", fields.package_name)
  end
  if need("ver_name") and not found.version_name then
    toAppend[#toAppend + 1] = "ver_name = " .. _M.formatSimple("ver_name", fields.ver_name)
  end
  if need("ver_code") and not found.version_code then
    toAppend[#toAppend + 1] = "ver_code = " .. _M.formatSimple("ver_code", fields.ver_code)
  end
  if need("min_sdk") then
    toAppend[#toAppend + 1] = "min_sdk = " .. _M.formatSimple("min_sdk", fields.min_sdk)
  end
  if need("target_sdk") then
    toAppend[#toAppend + 1] = "target_sdk = " .. _M.formatSimple("target_sdk", fields.target_sdk)
  end
  if need("debug_mode") and not found.debugmode then
    toAppend[#toAppend + 1] = "debug_mode = " .. _M.formatSimple("debug_mode", fields.debug_mode)
  end
  if fields.NeLuaJ_Theme ~= nil and not hasNeLuaJThemeLine and not found.NeLuaJ_Theme then
    toAppend[#toAppend + 1] = "NeLuaJ_Theme = " .. _M.formatSimple("NeLuaJ_Theme", fields.NeLuaJ_Theme)
  end
  if fields.user_permission ~= nil and not found.user_permission then
    toAppend[#toAppend + 1] = _M.formatPermissions(fields.user_permission or {})
  end

  if #toAppend > 0 then
    while #out > 0 and out[#out]:match("^%s*$") do
      table.remove(out)
    end
    if #out > 0 then
      out[#out + 1] = ""
    end
    for _, line in ipairs(toAppend) do
      if line:find("\n", 1, true) then
        appendBlock(out, line, "")
      else
        out[#out + 1] = line
      end
    end
  end

  local body = table.concat(out, "\n")
  if not body:match("\n$") then
    body = body .. "\n"
  end
  return body
end

function _M.save(path, fields, fileUtil)
  fileUtil = fileUtil or LuaFileUtil
  local raw = ""
  pcall(function()
    if fileUtil.read then
      raw = fileUtil.read(path) or ""
    end
  end)
  local body
  if raw == "" then
    body = _M.build(fields)
  else
    body = _M.patch(raw, fields)
  end
  if fileUtil.writeOrCreate then
    return fileUtil.writeOrCreate(path, body) == true
  end
  local ok = false
  pcall(function()
    if File(path).exists() then
      ok = fileUtil.write(path, body) == true
    else
      fileUtil.create(path, body)
      ok = true
    end
  end)
  return ok
end

--- 从 loadLua 表解析主题名（兼容 theme / NeLuaJ_Theme）
function _M.resolveThemeName(init, fallback)
  fallback = fallback or "Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay"
  if not init then return fallback end
  local function get(k)
    local ok, v = pcall(function() return init[k] end)
    if ok and v ~= nil then
      local s = tostring(v)
      if s ~= "" and s ~= "nil" then return s end
    end
    return nil
  end
  local n = get("NeLuaJ_Theme")
  if n and _M.isNeLuaJThemeName(n) then return n end
  local t = get("theme")
  if t and _M.isNeLuaJThemeName(t) then return t end
  if n then return n end
  -- theme 为 android.R.style 名或数字时，不拿来当 NeLuaJ 选项
  return fallback
end

return _M
