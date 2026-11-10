--- 旧版 HTTP+SSE。协议协商、缓存和工具路由仍留在 MCPClient。
local _M = {}

function _M.create(deps)
  local client = deps.client
  local http = deps.http
  local protocol = deps.protocol

  return function(server, method, params, id, extraHeaders, group)
    if group and group.isCancelled() then return nil, "MCP_CANCELLED" end
    local key = deps.serverKey(server)
    local connectionState = deps.serverState(key)
    local connection = connectionState.sseConnection
    if not connection then return nil, "旧版 MCP SSE 连接未建立" end
    local function disconnected()
      pcall(function() connection.close() end)
      if connectionState.sseConnection == connection then
        connectionState.sseConnection = nil
        connectionState.mode = nil
        connectionState.sseAttempted = nil
        client._initCache[key] = nil
      end
      return nil, "旧版 MCP SSE 连接已断开: " .. tostring(connection.getError() or "")
    end
    -- A cancelled initializer may leave a healthy shared stream still waiting
    -- for its endpoint. isUsable() is false in that state, not just on failure.
    if connection.getError() then return disconnected() end
    local endpoint
    if group then endpoint = connection.awaitEndpoint(10000, group)
    else endpoint = connection.awaitEndpoint(10000) end
    if group and group.isCancelled() then return nil, "MCP_CANCELLED" end
    if connection.getError() then return disconnected() end
    if not endpoint or endpoint == "" then
      return nil, "旧版 MCP SSE 未提供消息端点: " .. tostring(connection.getError() or "超时")
    end
    local payload = protocol.newRequest(method, params, id, deps.nextRequestId)
    local requestId = payload.id
    local okBody, body = pcall(json.encode, payload)
    if not okBody or not body or body == "" then return nil, "请求体编码失败" end
    local function cancelResponse()
      if not requestId then return end
      if group then connection.cancelResponse(tostring(requestId), group)
      else connection.cancelResponse(tostring(requestId)) end
    end
    local okPost, response = pcall(function()
      if requestId then
        if group then connection.prepareResponse(tostring(requestId), group)
        else connection.prepareResponse(tostring(requestId)) end
      end
      if group then return http.postJson(endpoint, body, deps.legacySseHeaders(server), -1, group) end
      return http.postJson(endpoint, body, deps.legacySseHeaders(server), -1)
    end)
    if group and group.isCancelled() then
      cancelResponse()
      return nil, "MCP_CANCELLED"
    end
    if not okPost or not response then
      cancelResponse()
      return nil, "旧版 MCP POST 失败: " .. tostring(response)
    end
    local code = tonumber(response.code()) or 0
    if code < 200 or code >= 300 then
      local detail = ""
      pcall(function() detail = tostring(response.body() or "") end)
      cancelResponse()
      return nil, "HTTP " .. tostring(code) .. "（" .. method .. "）"
        .. (detail ~= "" and "：" .. detail:sub(1, 500) or "")
    end
    if not requestId then return true, nil end
    local raw
    if group then raw = connection.awaitResponse(tostring(requestId), deps.sseTimeout, group)
    else raw = connection.awaitResponse(tostring(requestId), deps.sseTimeout) end
    if group and group.isCancelled() then return nil, "MCP_CANCELLED" end
    if not raw then
      if not connection.isUsable() then
        return disconnected()
      end
      return nil, "旧版 MCP SSE 等待响应超时"
    end
    local okJson, decoded = pcall(json.decode, raw)
    if not okJson then return nil, "旧版 MCP SSE JSON 解析失败: " .. tostring(decoded) end
    return decoded, nil
  end
end

return _M
