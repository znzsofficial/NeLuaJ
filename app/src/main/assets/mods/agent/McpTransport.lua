--- MCP 的两种 HTTP 传输。协议协商、缓存和工具路由仍留在 MCPClient。
local _M = {}

function _M.create(deps)
  local client = deps.client
  local http = deps.http
  local protocol = deps.protocol

  local function httpRequest(server, method, params, id, extraHeaders)
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

  local function sseRequest(server, method, params, id)
    local key = deps.serverKey(server)
    local connectionState = deps.serverState(key)
    local connection = connectionState.sseConnection
    if not connection then return nil, "旧版 MCP SSE 连接未建立" end
    if not connection.isUsable() then
      pcall(function() connection.close() end)
      connectionState.sseConnection = nil
      connectionState.mode = nil
      connectionState.sseAttempted = nil
      client._initCache[key] = nil
      return nil, "旧版 MCP SSE 连接已断开: " .. tostring(connection.getError() or "")
    end
    local endpoint = connection.awaitEndpoint(10000)
    if not endpoint or endpoint == "" then
      return nil, "旧版 MCP SSE 未提供消息端点: " .. tostring(connection.getError() or "超时")
    end
    local payload = protocol.newRequest(method, params, id, deps.nextRequestId)
    local requestId = payload.id
    local okBody, body = pcall(json.encode, payload)
    if not okBody or not body or body == "" then return nil, "请求体编码失败" end
    if requestId then connection.prepareResponse(tostring(requestId)) end
    local okPost, response = pcall(function()
      return http.postJson(endpoint, body, deps.legacySseHeaders(server), -1)
    end)
    if not okPost or not response then
      if requestId then connection.cancelResponse(tostring(requestId)) end
      return nil, "旧版 MCP POST 失败: " .. tostring(response)
    end
    local code = tonumber(response.code()) or 0
    if code < 200 or code >= 300 then
      local detail = ""
      pcall(function() detail = tostring(response.body() or "") end)
      if requestId then connection.cancelResponse(tostring(requestId)) end
      return nil, "HTTP " .. tostring(code) .. "（" .. method .. "）"
        .. (detail ~= "" and "：" .. detail:sub(1, 500) or "")
    end
    if not requestId then return true, nil end
    local raw = connection.awaitResponse(tostring(requestId), deps.sseTimeout)
    if not raw then
      if not connection.isUsable() then
        pcall(function() connection.close() end)
        connectionState.sseConnection = nil
        connectionState.mode = nil
        connectionState.sseAttempted = nil
        client._initCache[key] = nil
        return nil, "旧版 MCP SSE 连接已断开: " .. tostring(connection.getError() or "")
      end
      return nil, "旧版 MCP SSE 等待响应超时"
    end
    local okJson, decoded = pcall(json.decode, raw)
    if not okJson then return nil, "旧版 MCP SSE JSON 解析失败: " .. tostring(decoded) end
    return decoded, nil
  end

  return { http = httpRequest, sse = sseRequest }
end

return _M
