--- MCP Streamable HTTP 客户端（仅 HTTP 系传输，不支持 stdio）
--- 配置存于 shared data "ai_mcp_servers"（JSON 数组）
local _M = {}
local Protocol = require("mods.agent.MCPProtocol")
local ReentrantLock = luajava.bindClass("java.util.concurrent.locks.ReentrantLock")
local McpHttpClient = luajava.bindClass("com.nekolaska.mcp.McpHttpClient")
local initLock = ReentrantLock()
local agentMcpHttp = McpHttpClient()
local serverState

local SERVERS_KEY = "ai_mcp_servers"
local DEFAULT_PROTO = Protocol.DEFAULT_PROTOCOL
local LEGACY_DEFAULT_PROTO = Protocol.LEGACY_DEFAULT_PROTOCOL
local LEGACY_PROTOCOLS = Protocol.LEGACY_PROTOCOLS
local LEGACY_SSE_TIMEOUT_MS = 120000
local transportHeaders

--- 默认预置服务器（公开端点，无需 API key；需要鉴权时可自行补 headers）
local DEFAULT_SERVERS = {
  { name = "context7", url = "https://mcp.context7.com/mcp", headers = {} },
  { name = "deepwiki", url = "https://mcp.deepwiki.com/mcp", headers = {} },
}

local serverKey = Protocol.serverKey
local shortHash = Protocol.shortHash

local function cloneServers(list)
  local out = {}
  for _, s in ipairs(list or {}) do
    local c = {}
    for k, v in pairs(s) do
      if type(v) == "table" then
        local vc = {}
        for k2, v2 in pairs(v) do vc[k2] = v2 end
        c[k] = vc
      else
        c[k] = v
      end
    end
    out[#out + 1] = c
  end
  return out
end

local function closeServerStates()
  for _, state in pairs(_M._serverState or {}) do
    if state.server and state.sessionId and state.sessionId ~= "" then
      local headers = {}
      for key, value in pairs(state.server.headers or {}) do
        if not transportHeaders or not transportHeaders[tostring(key):lower()] then
          headers[key] = tostring(value)
        end
      end
      headers["Mcp-Session-Id"] = state.sessionId
      headers["MCP-Protocol-Version"] = state.protocolVersion or LEGACY_DEFAULT_PROTO
      pcall(function() agentMcpHttp.deleteSession(state.server.url, headers) end)
    end
    if state.sseConnection then pcall(function() state.sseConnection.close() end) end
  end
end

-- ─── 配置读写 ──

function _M.getServers()
  local raw = this.getSharedData(SERVERS_KEY, "")
  if raw == "" then
    local seeded = cloneServers(DEFAULT_SERVERS)
    _M.setServers(seeded)
    return seeded
  end
  local ok, arr = pcall(json.decode, raw)
  if not ok or type(arr) ~= "table" then return {} end
  return arr
end

--- 返回默认预置服务器列表（副本，不改动配置）
function _M.getDefaultServers()
  return cloneServers(DEFAULT_SERVERS)
end

function _M.setServers(list)
  local ok, enc = pcall(json.encode, list or {})
  if ok then
    closeServerStates()
    this.setSharedData(SERVERS_KEY, enc)
    _M._toolsCache = {}
    _M._initCache = {}
    _M._serverState = {}
    _M._mergedTools = nil
    _M._mergedAt = 0
    _M._toolRoutes = {}
    _M._configGeneration = (_M._configGeneration or 0) + 1
  end
end

-- ─── JSON-RPC 基础请求（同步）──

local rpcErrorText = Protocol.rpcErrorText

local function nextRequestId()
  _M._nextRequestId = (_M._nextRequestId or 0) + 1
  if _M._nextRequestId > 2147483647 then _M._nextRequestId = 1 end
  return _M._nextRequestId
end

local supportedProtocols = Protocol.supportedProtocols
local usesLegacySession = Protocol.usesLegacySession
local isModernProtocol = Protocol.isModernProtocol
local collectMcpParamHeaders = Protocol.collectParamHeaders
local validateMcpHeaderSchema = Protocol.validateHeaderSchema
local encodeHeaderValue = Protocol.encodeHeaderValue

local function validateServer(server)
  local headers = server and server.headers
  local hasHeaders = type(headers) == "table" and next(headers) ~= nil
  local ok, reason = pcall(function()
    return agentMcpHttp.validateServerUrl(tostring(server and server.url or ""), hasHeaders)
  end)
  if not ok then return nil, tostring(reason) end
  if reason and reason ~= "" then return nil, tostring(reason) end
  return true
end

function _M.validateServer(server)
  return validateServer(server)
end

transportHeaders = {
  ["accept"] = true,
  ["content-type"] = true,
  ["mcp-method"] = true,
  ["mcp-name"] = true,
  ["mcp-protocol-version"] = true,
  ["mcp-session-id"] = true,
}

local function rpcRequest(server, method, params, id, extraHeaders)
  local url = server.url or ""
  if url == "" then return nil, "服务器地址为空" end
  local valid, validationError = validateServer(server)
  if not valid then return nil, validationError end
  -- 恢复持久化的会话状态（getServers 每次返回新表，不能只存 server 字段）
  local key = serverKey(server)
  local st = serverState(key)
  st.server = server
  if st and method ~= "initialize" then
    if not server.sessionId and st.sessionId then server.sessionId = st.sessionId end
    if not server.protocolVersion and st.protocolVersion then server.protocolVersion = st.protocolVersion end
  end
  local headers = {}
  if type(server.headers) == "table" then
    for k, v in pairs(server.headers) do
      -- Transport headers come from the negotiated request state. Let custom
      -- configuration supply authentication and vendor headers only.
      if not transportHeaders[tostring(k):lower()] then headers[k] = tostring(v) end
    end
  end
  -- 注意：不要在此手动设置 Content-Type，okhttp.postJson 会从请求体自动附带
  -- application/json; charset=utf-8，重复添加会导致部分服务器返回 400
  headers["Accept"] = "application/json, text/event-stream"
  local proto = server.protocolVersion or DEFAULT_PROTO
  -- 2026-07-28 removed Streamable HTTP sessions. Keep the legacy session
  -- path only for older servers that explicitly still use it.
  if usesLegacySession(proto) and server.sessionId and server.sessionId ~= "" then
    headers["Mcp-Session-Id"] = server.sessionId
  end
  for key, value in pairs(extraHeaders or {}) do headers[key] = tostring(value) end
  local sentSessionId = server.sessionId
  headers["MCP-Protocol-Version"] = proto
  headers["Mcp-Method"] = method
  if params and (params.name or params.uri) then
    headers["Mcp-Name"] = encodeHeaderValue(params.name or params.uri)
  end
  -- 不要向调用方的 arguments 表写入协议元数据。
  local paramsObj = {}
  for k, v in pairs(params or {}) do paramsObj[k] = v end
  paramsObj._meta = {
    ["io.modelcontextprotocol/protocolVersion"] = proto,
  }
  if isModernProtocol(proto) then
    paramsObj._meta["io.modelcontextprotocol/clientInfo"] = {
      name = "NeLuaJ+",
      version = "1.0",
    }
    paramsObj._meta["io.modelcontextprotocol/clientCapabilities"] = {}
  end
  local payload = {
    jsonrpc = "2.0",
    method = method,
    params = paramsObj,
  }
  local requestId = id == false and nil or (id or nextRequestId())
  if requestId then payload.id = requestId end
  local body = json.encode(payload)
  if not body or body == "" then return nil, "请求体编码失败" end
  local okCall, res = pcall(function()
    return agentMcpHttp.postJson(url, body, headers, requestId or -1)
  end)
  if not okCall then return nil, "请求异常: " .. tostring(res) end
  if res == nil then return nil, "无响应" end
  -- Legacy servers may mint a session ID. New Streamable HTTP servers do not.
  local okSid, sid = pcall(function() return res.header("Mcp-Session-Id") end)
  if usesLegacySession(proto) and okSid and sid and sid ~= "" then
    local st2 = _M._serverState[key]
    if not sentSessionId or not st2 or not st2.sessionId or st2.sessionId == sentSessionId then
      server.sessionId = sid
      st2.sessionId = sid
      st2.server = server
    end
  end
  local okCode, code = pcall(function() return res.code() end)
  if okCode and type(code) == "number" and code >= 400 then
    -- 读取错误响应体，便于定位（如协议版本不支持、缺少会话等）
    local errDetail = ""
    local okErrBody, errBody = pcall(function()
      return res.body()
    end)
    if okErrBody and errBody and errBody ~= "" then
      local e = errBody:gsub("%s+", " ")
      if #e > 500 then e = e:sub(1, 500) .. "…" end
      errDetail = "：" .. e
    end
    if code == 404 and usesLegacySession(proto) and sentSessionId and sentSessionId ~= "" then
      local currentState = _M._serverState[key]
      if currentState and currentState.sessionId and currentState.sessionId ~= sentSessionId then
        server.sessionId = currentState.sessionId
      else
        if server.sessionId == sentSessionId then server.sessionId = nil end
        _M._serverState[key] = nil
        _M._initCache[key] = nil
      end
      _M._toolsCache[key] = nil
      return nil, "MCP_SESSION_EXPIRED"
    end
    return nil, "HTTP " .. tostring(code) .. "（" .. tostring(method) .. "）" .. errDetail
  end
  -- 通知没有响应体，2xx 即视为成功，不进入 JSON 解析。
  if id == false then
    return true, nil
  end
  local okBody, respBody = pcall(function() return res.body() end)
  if not okBody then return nil, "读取响应失败: " .. tostring(respBody) end
  local data = respBody or ""
  local okJ, decoded = pcall(json.decode, data)
  if not okJ then return nil, "JSON 解析失败: " .. data:sub(1, 200) end
  return decoded, nil
end

local function legacySseHeaders(server)
  local headers = { Accept = "text/event-stream" }
  for key, value in pairs(server.headers or {}) do
    if not transportHeaders[tostring(key):lower()] then headers[key] = tostring(value) end
  end
  return headers
end

local function shouldTryLegacySse(err)
  local message = tostring(err or "")
  return message:match("^HTTP 400") ~= nil
    or message:match("^HTTP 404") ~= nil
    or message:match("^HTTP 405") ~= nil
end

local function legacySseRequest(server, method, params, id)
  local key = serverKey(server)
  local state = serverState(key)
  local connection = state.sseConnection
  if not connection then return nil, "旧版 MCP SSE 连接未建立" end
  if not connection.isUsable() then
    pcall(function() connection.close() end)
    state.sseConnection = nil
    state.mode = nil
    state.sseAttempted = nil
    _M._initCache[key] = nil
    return nil, "旧版 MCP SSE 连接已断开: " .. tostring(connection.getError() or "")
  end
  local endpoint = connection.awaitEndpoint(10000)
  if not endpoint or endpoint == "" then
    return nil, "旧版 MCP SSE 未提供消息端点: " .. tostring(connection.getError() or "超时")
  end
  local requestId = id == false and nil or (id or nextRequestId())
  local payload = { jsonrpc = "2.0", method = method, params = params or {} }
  if requestId then payload.id = requestId end
  local okBody, body = pcall(json.encode, payload)
  if not okBody or not body or body == "" then return nil, "请求体编码失败" end
  if requestId then connection.prepareResponse(tostring(requestId)) end
  local okPost, response = pcall(function()
    return agentMcpHttp.postJson(endpoint, body, legacySseHeaders(server), -1)
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
  local raw = connection.awaitResponse(tostring(requestId), LEGACY_SSE_TIMEOUT_MS)
  if not raw then
    if not connection.isUsable() then
      pcall(function() connection.close() end)
      state.sseConnection = nil
      state.mode = nil
      state.sseAttempted = nil
      _M._initCache[key] = nil
      return nil, "旧版 MCP SSE 连接已断开: " .. tostring(connection.getError() or "")
    end
    return nil, "旧版 MCP SSE 等待响应超时"
  end
  local okJson, decoded = pcall(json.decode, raw)
  if not okJson then return nil, "旧版 MCP SSE JSON 解析失败: " .. tostring(decoded) end
  return decoded, nil
end

local function requestForServer(server)
  local state = _M._serverState[serverKey(server)]
  if state and state.mode == "legacy_sse" then return legacySseRequest end
  return rpcRequest
end

-- ─── 生命周期 ──

_M._initCache = {}
_M._serverState = {}  -- server key -> { protocolVersion = ..., sessionId = ... }（进程内缓存）

serverState = function(key)
  local st = _M._serverState[key]
  if not st then
    st = {}
    _M._serverState[key] = st
  end
  return st
end

function _M.ensureInitialized(server)
  local key = serverKey(server)
  if _M._initCache[key] then return true end
  initLock.lock()
  local ok, result, err = pcall(function()
    if _M._initCache[key] then return true end
    local state = serverState(key)
    if state.mode == "modern" then
      server.protocolVersion = state.protocolVersion or server.protocolVersion or DEFAULT_PROTO
      _M._initCache[key] = server.protocolVersion
      return true
    end
    local modernErr, legacyProtocol
    if state.mode ~= "legacy" and state.mode ~= "legacy_sse" then
      local modern, probeErr, advertisedLegacyProtocol = _M.probeModern(server)
      modernErr = probeErr
      legacyProtocol = advertisedLegacyProtocol
      state.modernProbeError = probeErr
      if modern then
        _M._initCache[key] = state.protocolVersion or server.protocolVersion or DEFAULT_PROTO
        return true
      end
      if probeErr and probeErr.isModern then
        return nil, probeErr.message or "现代 MCP 探测失败"
      end
      state.mode = "legacy"
      server.protocolVersion = legacyProtocol or LEGACY_DEFAULT_PROTO
    end
    local proto, initErr = _M.initialize(server)
    if not proto then
      local state = serverState(key)
      local probeErr = modernErr or state.modernProbeError
      if state.mode == "legacy" and not state.sseAttempted
          and (shouldTryLegacySse(probeErr and probeErr.message) or shouldTryLegacySse(initErr)) then
        state.sseAttempted = true
        local connection = agentMcpHttp.openSse(server.url, legacySseHeaders(server))
        state.sseConnection = connection
        local endpoint = connection.awaitEndpoint(10000)
        if endpoint and endpoint ~= "" then
          state.mode = "legacy_sse"
          server.protocolVersion = legacyProtocol or LEGACY_DEFAULT_PROTO
          proto, initErr = _M.initialize(server)
        else
          initErr = tostring(initErr or "") .. "; HTTP+SSE 回退失败: "
            .. tostring(connection.getError() or "未收到 endpoint 事件")
          pcall(function() connection.close() end)
          state.sseConnection = nil
        end
      end
      if not proto then return nil, initErr end
    end
    _M._initCache[key] = proto
    return true
  end)
  initLock.unlock()
  if not ok then return nil, "初始化异常: " .. tostring(result) end
  return result, err
end

function _M.probeModern(server)
  local key = serverKey(server)
  local candidates, tried = {}, {}
  local legacyProtocol
  local function addCandidate(protocol)
    protocol = tostring(protocol or "")
    if isModernProtocol(protocol) and not tried[protocol] then
      tried[protocol] = true
      candidates[#candidates + 1] = protocol
    end
  end
  addCandidate(server.protocolVersion or DEFAULT_PROTO)
  addCandidate(DEFAULT_PROTO)
  local index = 1
  local lastErr
  local modernProtocolAdvertised = false
  while index <= #candidates do
    local protocol = candidates[index]
    server.protocolVersion = protocol
    local res, err = rpcRequest(server, "tools/list", {})
    if res and not res.error then
      local state = serverState(key)
      state.mode = "modern"
      state.protocolVersion = protocol
      state.sessionId = nil
      server.sessionId = nil
      return true
    end
    local errorData = res and res.error
    lastErr = err or rpcErrorText(errorData)
    for _, supported in ipairs(supportedProtocols(errorData or lastErr)) do
      -- Error messages commonly repeat the rejected request version before
      -- listing the versions the server actually supports.
      if supported ~= protocol then
        if isModernProtocol(supported) then
          modernProtocolAdvertised = true
          addCandidate(supported)
        elseif not legacyProtocol or supported > legacyProtocol then
          legacyProtocol = supported
        end
      end
    end
    index = index + 1
  end
  local modern = modernProtocolAdvertised
    or tostring(lastErr or ""):find("Header mismatch", 1, true)
    or tostring(lastErr or ""):find("HeaderMismatch", 1, true)
    or tostring(lastErr or ""):find("-32020", 1, true)
    or tostring(lastErr or ""):find("-32021", 1, true)
    or tostring(lastErr or ""):find("-32022", 1, true)
  return nil, { message = lastErr or "现代 MCP 探测失败", isModern = modern }, legacyProtocol
end

function _M.initialize(server)
  local key = serverKey(server)
  -- A fresh initialize request must never carry a stale session from a prior
  -- connection. The negotiated response below will restore a new session ID.
  server.sessionId = nil
  local existingState = serverState(key)
  existingState.sessionId = nil
  local request = requestForServer(server)
  local candidates, tried = {}, {}
  local function addCandidate(protocol)
    protocol = tostring(protocol or "")
    if protocol ~= "" and usesLegacySession(protocol) and not tried[protocol] then
      tried[protocol] = true
      candidates[#candidates + 1] = protocol
    end
  end
  addCandidate(server.protocolVersion)
  for _, protocol in ipairs(LEGACY_PROTOCOLS) do addCandidate(protocol) end

  local res, err, proto
  local index = 1
  while index <= #candidates do
    local requested = candidates[index]
    server.protocolVersion = requested
    res, err = request(server, "initialize", {
      protocolVersion = requested,
      capabilities = {},
      clientInfo = { name = "NeLuaJ+", version = "1.0" },
    })
    if res and not res.error then
      proto = tostring(res.result and res.result.protocolVersion or requested)
      break
    end
    local errorData = res and res.error
    err = err or rpcErrorText(errorData)
    for _, supported in ipairs(supportedProtocols(errorData or err)) do addCandidate(supported) end
    index = index + 1
  end
  if not proto then return nil, err or "初始化失败" end
  if isModernProtocol(proto) then return nil, "服务器要求无状态 MCP 协议 " .. proto end
  server.protocolVersion = proto
  local st = serverState(key)
  if st.mode ~= "legacy_sse" then st.mode = "legacy" end
  st.protocolVersion = proto
  local _, notifyErr = request(server, "notifications/initialized", {}, false)
  if notifyErr then return nil, notifyErr end
  if server.sessionId and server.sessionId ~= "" then st.sessionId = server.sessionId end
  return proto, nil
end

-- ─── 工具 ──

_M._toolsCache = {}

function _M.listTools(server)
  local key = serverKey(server)
  local cached = _M._toolsCache[key]
  if cached and cached.time and (os.time() - cached.time) < (cached.ttl or 300) then
    return cached.tools
  end
  for attempt = 1, 2 do
    local okInit, initErr = _M.ensureInitialized(server)
    if not okInit then return nil, initErr end
    local initializedCache = _M._toolsCache[key]
    if initializedCache and initializedCache.time
        and (os.time() - initializedCache.time) < (initializedCache.ttl or 300) then
      return initializedCache.tools
    end
    local tools, cursor, hasCursor = {}, nil, false
    local cacheTtl
    local state = _M._serverState[key]
    local validateHeaders = state and isModernProtocol(state.protocolVersion)
    for page = 1, 20 do
      local res, err = requestForServer(server)(server, "tools/list", hasCursor and { cursor = cursor } or {})
      if not res then
        local errorText = tostring(err or "")
        if (errorText == "MCP_SESSION_EXPIRED" or errorText:find("旧版 MCP SSE 连接已断开", 1, true))
            and attempt == 1 then
          break
        end
        return nil, errorText ~= "" and errorText or "MCP tools/list 无响应"
      end
      if res.error then return nil, rpcErrorText(res.error) end
      if res.result and type(res.result.tools) == "table" then
        for _, tool in ipairs(res.result.tools) do
          local schema = type(tool) == "table" and (tool.inputSchema or tool.input_schema) or nil
          local valid, reason = not validateHeaders or validateMcpHeaderSchema(schema)
          if valid then
            tools[#tools + 1] = tool
          else
            print("MCP 工具已忽略: " .. tostring(tool and tool.name or "?") .. "（" .. tostring(reason) .. "）")
          end
        end
      end
      local ttlMs = tonumber(res.result and res.result.ttlMs)
      if ttlMs then
        local pageTtl = math.max(0, ttlMs / 1000)
        cacheTtl = cacheTtl == nil and pageTtl or math.min(cacheTtl, pageTtl)
      end
      local nextCursor = res.result and res.result.nextCursor
      if nextCursor == nil then
        _M._toolsCache[key] = { time = os.time(), tools = tools, ttl = cacheTtl or 300 }
        return tools
      end
      cursor = tostring(nextCursor)
      hasCursor = true
      if page == 20 then return nil, "MCP 工具分页超过 20 页上限" end
    end
  end
  return nil, "MCP 会话已过期"
end

function _M.callTool(server, toolName, args)
  local okInit, initErr = _M.ensureInitialized(server)
  if not okInit then return nil, initErr end
  local params = {
    name = toolName,
    arguments = args or {},
  }
  local key = serverKey(server)
  local function headersForTool()
    local state = _M._serverState[key]
    local schema
    local cached = _M._toolsCache[key]
    for _, tool in ipairs(cached and cached.tools or {}) do
      if tostring(tool.name or "") == tostring(toolName) then
        schema = tool.inputSchema or tool.input_schema
        break
      end
    end
    return state and isModernProtocol(state.protocolVersion)
      and collectMcpParamHeaders(schema, params.arguments) or nil
  end
  local paramHeaders = headersForTool()
  local request = requestForServer(server)
  local res, err = request(server, "tools/call", params, nil, paramHeaders)
  if err and (err:find("HeaderMismatch", 1, true) or err:find("-32020", 1, true)) then
    -- A modern server may have changed x-mcp-header annotations. Refresh the
    -- schema once, then mirror the newly declared headers on the retry.
    _M._toolsCache[key] = nil
    local refreshed = _M.listTools(server)
    if refreshed then
      paramHeaders = headersForTool()
      res, err = requestForServer(server)(server, "tools/call", params, nil, paramHeaders)
    end
  end
  if err == "MCP_SESSION_EXPIRED" then
    local retryInit, retryErr = _M.ensureInitialized(server)
    if not retryInit then return nil, retryErr end
    res, err = requestForServer(server)(server, "tools/call", params, nil, paramHeaders)
  end
  if err and err:find("旧版 MCP SSE 连接已断开", 1, true) then
    local retryInit, retryErr = _M.ensureInitialized(server)
    if not retryInit then return nil, retryErr end
    res, err = requestForServer(server)(server, "tools/call", params, nil, paramHeaders)
  end
  if not res then return nil, err end
  if res.error then return nil, rpcErrorText(res.error) end
  local result = res.result or {}
  local parts = {}
  if type(result.content) == "table" then
    for _, item in ipairs(result.content) do
      if type(item) == "table" then
        if item.type == "text" then
          parts[#parts + 1] = tostring(item.text or "")
        elseif item.type == "image" then
          parts[#parts + 1] = "[图片内容]"
        else
          parts[#parts + 1] = tostring(item.text or item.data or "")
        end
      end
    end
  end
  if result.structuredContent ~= nil then
    local okEnc, enc = pcall(json.encode, result.structuredContent)
    if okEnc then parts[#parts + 1] = enc end
  end
  local text = table.concat(parts, "\n")
  if result.isError then
    return nil, (text ~= "" and text or "工具调用失败（服务器标记 isError）")
  end
  return text, nil
end

-- ─── OpenAI 工具格式转换 ──

local function serverNamespace(server)
  local sname = tostring(server.name or "mcp")
  return sname:gsub("[^%w_%-]", "_")
end

local function toolToOpenAi(server, serverIndex, ns, tool)
  local inputSchema = tool.inputSchema or tool.input_schema
  if type(inputSchema) ~= "table" then
    inputSchema = { type = "object", properties = {} }
  end
  local cleanTool = tostring(tool.name):gsub("[^%w_%-]", "_")
  local publicIdentity = tostring(server.name or "") .. "\n" .. tostring(server.url or "")
    .. "\n" .. tostring(serverIndex) .. "\n" .. tostring(tool.name)
  local suffix = shortHash(publicIdentity)
  local publicName = ("mcp__" .. ns .. "__" .. cleanTool):sub(1, 54) .. "__" .. suffix
  return {
    type = "function",
    ["function"] = {
      name = publicName,
      description = tostring(tool.description or ""),
      parameters = inputSchema,
    },
  }, publicName
end

_M._toolRoutes = {}

function _M.resolveToolRoute(name)
  local route = _M._toolRoutes[tostring(name or "")]
  if not route then return nil end
  for _, server in ipairs(_M.getServers()) do
    if serverKey(server) == serverKey(route.server) then return route end
  end
  return nil
end

function _M.findServer(ns)
  for _, server in ipairs(_M.getServers()) do
    if serverNamespace(server) == ns then
      return server
    end
  end
  return nil
end

--- 返回可直接并入 body.tools 的 OpenAI 工具列表
--- 同步版本：仅在后台线程调用，禁止在主线程执行（会触发 NetworkOnMainThreadException）
function _M.getOpenAiTools(generation)
  local merged = {}
  local routes = {}
  local mergedTtl
  for serverIndex, server in ipairs(_M.getServers()) do
    local tools = _M.listTools(server)
    local cached = _M._toolsCache[serverKey(server)]
    if cached and cached.ttl ~= nil then
      mergedTtl = mergedTtl == nil and cached.ttl or math.min(mergedTtl, cached.ttl)
    end
    if type(tools) == "table" then
      local ns = serverNamespace(server)
      for _, tool in ipairs(tools) do
        if type(tool) == "table" and tool.name then
          local converted, publicName = toolToOpenAi(server, serverIndex, ns, tool)
          converted["function"].name = publicName
          merged[#merged + 1] = converted
          routes[publicName] = { server = server, tool = tostring(tool.name) }
        end
      end
    end
  end
  if generation == nil or generation == (_M._configGeneration or 0) then
    _M._toolRoutes = routes
  end
  return merged, mergedTtl or 300
end

local function publishCachedOpenAiTools()
  local merged, routes = {}, {}
  local mergedTtl
  local now = os.time()
  local foundCache = false
  for serverIndex, server in ipairs(_M.getServers()) do
    local cached = _M._toolsCache[serverKey(server)]
    local ttl = cached and tonumber(cached.ttl) or 300
    if cached and cached.time and (ttl <= 0 or (now - cached.time) < ttl) then
      foundCache = true
      mergedTtl = mergedTtl == nil and ttl or math.min(mergedTtl, ttl)
      local ns = serverNamespace(server)
      for _, tool in ipairs(cached.tools or {}) do
        if type(tool) == "table" and tool.name then
          local converted, publicName = toolToOpenAi(server, serverIndex, ns, tool)
          merged[#merged + 1] = converted
          routes[publicName] = { server = server, tool = tostring(tool.name) }
        end
      end
    end
  end
  if not foundCache then return nil end
  _M._toolRoutes = routes
  _M._mergedTools = merged
  _M._mergedTtl = mergedTtl or 300
  _M._mergedAt = now
  return merged
end

--- 测试连接：initialize + tools/list（同步，仅在后台线程调用）
function _M.testServer(server)
  local okInit, initErr = _M.ensureInitialized(server)
  if not okInit then return false, initErr end
  local tools = _M.listTools(server)
  if not tools then return false, "tools/list 失败" end
  return true, "连接成功，发现 " .. #tools .. " 个工具"
end

-- ─── 异步封装（后台 IO 线程执行，主线程读取缓存）──

_M._mergedTools = nil
_M._mergedAt = 0
_M._refreshing = false
_M._refreshWaiters = {}

--- 后台刷新所有服务器的工具并缓存合并结果；完成后在回调中返回 merged 列表
function _M.refreshToolsAsync(onDone)
  if onDone then _M._refreshWaiters[#_M._refreshWaiters + 1] = onDone end
  if _M._refreshing then return end
  _M._refreshing = true
  local generation = _M._configGeneration or 0
  local okLaunch = pcall(function()
    xTask(
      function()
        return _M.getOpenAiTools(generation)
      end,
      function(merged, mergedTtl)
        _M._refreshing = false
        if generation ~= (_M._configGeneration or 0) then
          -- Keep waiters for the replacement task. Starting it while the old
          -- task is still marked active would otherwise deadlock refreshes.
          _M.refreshToolsAsync()
          return
        end
        if type(merged) == "table" then
          _M._mergedTools = merged
          _M._mergedTtl = tonumber(mergedTtl) or 300
          _M._mergedAt = os.time()
        end
        local waiters = _M._refreshWaiters
        _M._refreshWaiters = {}
        for _, waiter in ipairs(waiters) do pcall(waiter, _M._mergedTools) end
      end,
      "io"
    )
  end)
  if not okLaunch then
    _M._refreshing = false
    local waiters = _M._refreshWaiters
    _M._refreshWaiters = {}
        for _, waiter in ipairs(waiters) do pcall(waiter, nil) end
  end
end

--- 主线程安全：返回已缓存的合并工具（可能为 nil），触发一次后台刷新
function _M.getCachedOpenAiTools()
  if _M._mergedTools and (_M._mergedTtl or 300) <= 0 then
    -- ttlMs=0 means revalidate before reuse, not that the response just
    -- received is unusable. Keep the current snapshot visible while the next
    -- list request refreshes it in the background.
    _M.refreshToolsAsync()
    return _M._mergedTools
  end
  if _M._mergedTools and _M._mergedAt
      and (os.time() - _M._mergedAt) < (_M._mergedTtl or 300) then
    return _M._mergedTools
  end
  if not _M._mergedTools then
    local cached = publishCachedOpenAiTools()
    if cached then
      _M.refreshToolsAsync()
      return cached
    end
  end
  _M.refreshToolsAsync()
  return nil
end

--- 异步调用 MCP 工具；onResult(ok, text)（主线程回调）
function _M.callToolAsync(server, toolName, args, onResult)
  local job
  local okLaunch = pcall(function()
    job = xTask(
      function()
        local okInit, initErr = _M.ensureInitialized(server)
        if not okInit then return { ok = false, text = initErr } end
        local text, err = _M.callTool(server, toolName, args)
        if text then return { ok = true, text = text } end
        return { ok = false, text = err }
      end,
      function(res)
        if onResult then
          if type(res) == "table" then
            pcall(onResult, res.ok == true, res.text)
          else
            pcall(onResult, false, "后台任务异常: " .. tostring(res))
          end
        end
      end,
      "io"
    )
  end)
  if not okLaunch and onResult then pcall(onResult, false, "无法启动后台任务") end
  return job
end

function _M.cancelPending()
  pcall(function() agentMcpHttp.cancelAll() end)
end

--- 异步测试连接；onResult(ok, msg)（主线程回调）
function _M.testServerAsync(server, onResult)
  local okLaunch = pcall(function()
    xTask(
      function()
        local ok, msg = _M.testServer(server)
        return { ok = ok == true, msg = msg }
      end,
      function(res)
        if type(res) == "table" and res.ok == true then publishCachedOpenAiTools() end
        if onResult then
          if type(res) == "table" then
            pcall(onResult, res.ok == true, res.msg)
          else
            pcall(onResult, false, "后台任务异常: " .. tostring(res))
          end
        end
      end,
      "io"
    )
  end)
  if not okLaunch and onResult then pcall(onResult, false, "无法启动后台任务") end
end

return _M
