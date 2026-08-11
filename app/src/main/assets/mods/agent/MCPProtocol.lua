--- Stateless MCP protocol helpers: identity, negotiation and JSON-RPC encoding.
local _M = {}
local Base64 = luajava.bindClass("android.util.Base64")

_M.DEFAULT_PROTOCOL = "2026-07-28"
_M.LEGACY_DEFAULT_PROTOCOL = "2025-11-25"
_M.LEGACY_PROTOCOLS = { "2025-11-25", "2025-06-18", "2025-03-26" }

function _M.serverKey(server)
  local parts = { tostring(server.url or "") }
  local headers = server.headers
  if type(headers) == "table" then
    local keys = {}
    for key in pairs(headers) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    for _, key in ipairs(keys) do parts[#parts + 1] = key .. "=" .. tostring(headers[key]) end
  end
  return table.concat(parts, "\n")
end

function _M.shortHash(text)
  local value = 0
  for index = 1, #text do value = (value * 131 + text:byte(index)) % 2147483647 end
  return string.format("%08x", value)
end

function _M.supportedProtocols(value)
  local protocols, seen = {}, {}
  local function collect(item)
    if type(item) == "table" then
      for _, nested in pairs(item) do collect(nested) end
      return
    end
    for protocol in tostring(item or ""):gmatch("%d%d%d%d%-%d%d%-%d%d") do
      if not seen[protocol] then seen[protocol] = true; protocols[#protocols + 1] = protocol end
    end
  end
  collect(value)
  return protocols
end

function _M.usesLegacySession(protocol)
  return tostring(protocol or "") < _M.DEFAULT_PROTOCOL
end

function _M.isModernProtocol(protocol)
  return not _M.usesLegacySession(protocol)
end

function _M.rpcErrorText(error)
  if type(error) ~= "table" then return tostring(error) end
  local message = error.message or "JSON-RPC 错误"
  if error.code then message = message .. " (code " .. tostring(error.code) .. ")" end
  return message
end

function _M.encodeHeaderValue(value)
  local text = tostring(value or "")
  local plain = text ~= "" and text:sub(1, 1) ~= " " and text:sub(-1) ~= " "
    and not text:find("[^ -~]") and not (text:sub(1, 9) == "=?base64?" and text:sub(-2) == "?=")
  if plain then return text end
  local bytes = luajava.newInstance("java.lang.String", text).getBytes("UTF-8")
  return "=?base64?" .. tostring(Base64.encodeToString(bytes, Base64.NO_WRAP)) .. "?="
end

function _M.collectParamHeaders(schema, args)
  local headers = {}
  local function visit(node, values)
    if type(node) ~= "table" or type(node.properties) ~= "table" then return end
    for key, property in pairs(node.properties) do
      if type(property) == "table" then
        local value = type(values) == "table" and values[key] or nil
        local headerName = property["x-mcp-header"]
        if headerName and value ~= nil and (type(value) == "string" or type(value) == "boolean"
            or (type(value) == "number" and property.type == "integer" and value >= -9007199254740991 and value <= 9007199254740991)) then
          headerName = tostring(headerName)
          if headerName:match("^[!#$%%&'*+.^_`|~%w%-]+$") then
            headers["Mcp-Param-" .. headerName] = _M.encodeHeaderValue(value)
          end
        end
        visit(property, value)
      end
    end
  end
  visit(schema, args)
  return headers
end

function _M.validateHeaderSchema(schema)
  local valid, reason, seen = true, nil, {}
  local function visit(node, allowAnnotation, staticPath)
    if not valid or type(node) ~= "table" then return end
    local headerName = node["x-mcp-header"]
    if headerName then
      if not allowAnnotation then valid, reason = false, "x-mcp-header 只能位于静态 properties 路径"; return end
      headerName = tostring(headerName)
      if not headerName:match("^[!#$%%&'*+.^_`|~%w%-]+$") then valid, reason = false, "x-mcp-header 名称无效"
      elseif node.type ~= "string" and node.type ~= "boolean" and node.type ~= "integer" then valid, reason = false, "x-mcp-header 只能用于 string、boolean 或 integer 参数"
      elseif seen[headerName:lower()] then valid, reason = false, "x-mcp-header 名称重复"
      else seen[headerName:lower()] = true end
      if not valid then return end
    end
    for key, nested in pairs(node) do
      if key == "properties" and type(nested) == "table" then
        for _, property in pairs(nested) do visit(property, staticPath, staticPath) end
      elseif key ~= "x-mcp-header" then
        if type(nested) == "table" then visit(nested, false, false) end
      end
    end
  end
  visit(schema, false, true)
  return valid, reason
end

local function selectResponse(message, expectedId)
  if type(message) ~= "table" then return nil end
  if message.jsonrpc == "2.0" and (message.result ~= nil or message.error ~= nil)
      and (expectedId == nil or message.id == expectedId) then return message end
  for _, item in ipairs(message) do
    local response = selectResponse(item, expectedId)
    if response then return response end
  end
end

function _M.decodeSseResponse(data, expectedId)
  local response, fallback, decodeError, eventData = nil, nil, nil, {}
  local function finishEvent()
    if #eventData == 0 then return end
    local payload = table.concat(eventData, "\n")
    eventData = {}
    if payload == "[DONE]" then return end
    local ok, decoded = pcall(json.decode, payload)
    if not ok then decodeError = tostring(decoded); return end
    local matched = selectResponse(decoded, expectedId)
    if matched then fallback = matched; if expectedId == nil or matched.id == expectedId then response = matched end end
  end
  for rawLine in (tostring(data or "") .. "\n"):gmatch("(.-)\n") do
    local line = rawLine:gsub("\r$", "")
    if line == "" then finishEvent()
    elseif line:sub(1, 5) == "data:" then
      local value = line:sub(6)
      eventData[#eventData + 1] = value:sub(1, 1) == " " and value:sub(2) or value
    end
  end
  finishEvent()
  return response or fallback, decodeError
end

return _M
