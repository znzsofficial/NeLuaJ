--- Streamable HTTP。协议协商、缓存和工具路由仍留在 MCPClient。
local _M = {}

function _M.create(deps)
  local client = deps.client
  local http = deps.http
  local protocol = deps.protocol

  return function(server, method, params, id, extraHeaders)
    local url = server.url or ""
    if url == "" then return nil, "服务器地址为空" end
    local valid, validationError = deps.validateServer(server)
    if not valid then return nil, validationError end
    local key = deps.serverKey(server)
    local st = deps.serverState(key)
    st.server = server
    if st and method ~= "initialize" then
      if not server.sessionId and st.sessionId then server.sessionId = st.sessionId end
      if not server.protocolVersion and st.protocolVersion then
        server.protocolVersion = st.protocolVersion
      end
    end
    local headers = {}
    if type(server.headers) == "table" then
      for name, value in pairs(server.headers) do
        if not deps.transportHeaders[tostring(name):lower()] then headers[name] = tostring(value) end
      end
    end
    headers["Accept"] = "application/json, text/event-stream"
    local proto = server.protocolVersion or deps.defaultProtocol
    if deps.usesLegacySession(proto) and server.sessionId and server.sessionId ~= "" then
      headers["Mcp-Session-Id"] = server.sessionId
    end
    for name, value in pairs(extraHeaders or {}) do headers[name] = tostring(value) end
    local sentSessionId = server.sessionId
    headers["MCP-Protocol-Version"] = proto
    headers["Mcp-Method"] = method
    if params and (params.name or params.uri) then
      headers["Mcp-Name"] = deps.encodeHeaderValue(params.name or params.uri)
    end
    local paramsObj = {}
    for name, value in pairs(params or {}) do paramsObj[name] = value end
    paramsObj._meta = { ["io.modelcontextprotocol/protocolVersion"] = proto }
    if deps.isModernProtocol(proto) then
      paramsObj._meta["io.modelcontextprotocol/clientInfo"] = { name = "NeLuaJ+", version = "1.0" }
      paramsObj._meta["io.modelcontextprotocol/clientCapabilities"] = {}
    end
    local payload = protocol.newRequest(method, paramsObj, id, deps.nextRequestId)
    local requestId = payload.id
    local body = json.encode(payload)
    if not body or body == "" then return nil, "请求体编码失败" end
    local okCall, res = pcall(function()
      return http.postJson(url, body, headers, requestId or -1)
    end)
    if not okCall then return nil, "请求异常: " .. tostring(res) end
    if res == nil then return nil, "无响应" end
    local okSid, sid = pcall(function() return res.header("Mcp-Session-Id") end)
    if deps.usesLegacySession(proto) and okSid and sid and sid ~= "" then
      local current = client._serverState[key]
      if not sentSessionId or not current or not current.sessionId
          or current.sessionId == sentSessionId then
        server.sessionId = sid
        current.sessionId = sid
        current.server = server
      end
    end
    local okCode, code = pcall(function() return res.code() end)
    if okCode and type(code) == "number" and code >= 400 then
      local errDetail = ""
      local okErrBody, errBody = pcall(function() return res.body() end)
      if okErrBody and errBody and errBody ~= "" then
        local compact = errBody:gsub("%s+", " ")
        if #compact > 500 then compact = compact:sub(1, 500) .. "…" end
        errDetail = "：" .. compact
      end
      if code == 404 and deps.usesLegacySession(proto) and sentSessionId and sentSessionId ~= "" then
        local current = client._serverState[key]
        if current and current.sessionId and current.sessionId ~= sentSessionId then
          server.sessionId = current.sessionId
        else
          if server.sessionId == sentSessionId then server.sessionId = nil end
          client._serverState[key] = nil
          client._initCache[key] = nil
        end
        client._toolsCache[key] = nil
        return nil, "MCP_SESSION_EXPIRED"
      end
      return nil, "HTTP " .. tostring(code) .. "（" .. tostring(method) .. "）" .. errDetail
    end
    if id == false then return true, nil end
    local okBody, respBody = pcall(function() return res.body() end)
    if not okBody then return nil, "读取响应失败: " .. tostring(respBody) end
    local data = respBody or ""
    local okJson, decoded = pcall(json.decode, data)
    if not okJson then return nil, "JSON 解析失败: " .. data:sub(1, 200) end
    return decoded, nil
  end
end

return _M

