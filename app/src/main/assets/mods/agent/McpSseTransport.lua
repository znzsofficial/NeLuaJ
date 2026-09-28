--- 旧版 HTTP+SSE。协议协商、缓存和工具路由仍留在 MCPClient。
local _M = {}

function _M.create(deps)
  local client = deps.client
  local http = deps.http
  local protocol = deps.protocol

  return function(server, method, params, id)
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
end

return _M
