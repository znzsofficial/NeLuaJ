--- MCP Streamable HTTP 客户端（仅 HTTP 系传输，不支持 stdio）
--- 配置存于 shared data "ai_mcp_servers"（JSON 数组）
local _M = {}
local ReentrantLock = luajava.bindClass("java.util.concurrent.locks.ReentrantLock")
local initLock = ReentrantLock()

local SERVERS_KEY = "ai_mcp_servers"
local DEFAULT_PROTO = "2025-06-18"

--- 默认预置服务器（公开端点，无需 API key；需要鉴权时可自行补 headers）
local DEFAULT_SERVERS = {
  { name = "context7", url = "https://mcp.context7.com/mcp", headers = {} },
  { name = "deepwiki", url = "https://mcp.deepwiki.com/mcp", headers = {} },
}

local function serverKey(server)
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

local function shortHash(text)
  local value = 0
  for index = 1, #text do value = (value * 131 + text:byte(index)) % 2147483647 end
  return string.format("%08x", value)
end

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

local function rpcErrorText(e)
  if type(e) == "table" then
    local msg = e.message or "JSON-RPC 错误"
    if e.code then msg = msg .. " (code " .. tostring(e.code) .. ")" end
    return msg
  end
  return tostring(e)
end

local function rpcRequest(server, method, params, id)
  local url = server.url or ""
  if url == "" then return nil, "服务器地址为空" end
  -- 恢复持久化的会话状态（getServers 每次返回新表，不能只存 server 字段）
  local key = serverKey(server)
  local st = _M._serverState and _M._serverState[key]
  if st then
    if not server.sessionId and st.sessionId then server.sessionId = st.sessionId end
    if not server.protocolVersion and st.protocolVersion then server.protocolVersion = st.protocolVersion end
  end
  local headers = {}
  if type(server.headers) == "table" then
    for k, v in pairs(server.headers) do
      headers[k] = tostring(v)
    end
  end
  -- 注意：不要在此手动设置 Content-Type，okhttp.postJson 会从请求体自动附带
  -- application/json; charset=utf-8，重复添加会导致部分服务器返回 400
  headers["Accept"] = "application/json, text/event-stream"
  -- 状态化服务器：后续请求必须带上 initialize 返回的会话 ID
  if server.sessionId and server.sessionId ~= "" then
    headers["Mcp-Session-Id"] = server.sessionId
  end
  local proto = server.protocolVersion or DEFAULT_PROTO
  local sentSessionId = server.sessionId
  headers["MCP-Protocol-Version"] = proto
  headers["Mcp-Method"] = method
  if params and params.name then
    headers["Mcp-Name"] = params.name
  end
  -- 不要向调用方的 arguments 表写入协议元数据。
  local paramsObj = {}
  for k, v in pairs(params or {}) do paramsObj[k] = v end
  paramsObj._meta = {
    ["io.modelcontextprotocol/protocolVersion"] = proto,
    ["io.modelcontextprotocol/clientInfo"] = {
      name = "NeLuaJ+",
      version = "1.0",
    },
  }
  local payload = {
    jsonrpc = "2.0",
    method = method,
    params = paramsObj,
  }
  if id ~= false then payload.id = id or 1 end
  local body = json.encode(payload)
  if not body or body == "" then return nil, "请求体编码失败" end
  local okCall, res = pcall(function()
    return okhttp.postJson(url, body, headers)
  end)
  if not okCall then return nil, "请求异常: " .. tostring(res) end
  if res == nil then return nil, "无响应" end
  -- 会话 ID：从 initialize 响应头捕获，持久化到 url 缓存
  local okSid, sid = pcall(function()
    if res.headers and res.headers() then
      local h = res.headers()
      if h.get then return h.get("Mcp-Session-Id") end
    end
    if res.header then return res.header("Mcp-Session-Id") end
    return nil
  end)
  if okSid and sid and sid ~= "" then
    local st2 = _M._serverState[key]
    if not sentSessionId or not st2 or not st2.sessionId or st2.sessionId == sentSessionId then
      server.sessionId = sid
      if st2 then st2.sessionId = sid else _M._serverState[key] = { sessionId = sid } end
    end
  end
  local okCode, code = pcall(function() return res.code() end)
  if okCode and type(code) == "number" and code >= 400 then
    -- 读取错误响应体，便于定位（如协议版本不支持、缺少会话等）
    local errDetail = ""
    local okErrBody, errBody = pcall(function()
      return res.body().string()
    end)
    if okErrBody and errBody and errBody ~= "" then
      local e = errBody:gsub("%s+", " ")
      if #e > 150 then e = e:sub(1, 150) .. "…" end
      errDetail = "：" .. e
    end
    if code == 404 and sentSessionId and sentSessionId ~= "" then
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
    pcall(function() res.close() end)
    return true, nil
  end
  local okBody, respBody = pcall(function()
    return res.body().string()
  end)
  if not okBody then return nil, "读取响应失败: " .. tostring(respBody) end
  local data = respBody or ""
  if data:find("^%s*data:") or data:find("\ndata:") then
    local lastJson = nil
    for line in data:gmatch("[^\r\n]+") do
      local l = line:gsub("^%s+", "")
      if l:sub(1, 5) == "data:" then
        local v = l:sub(6):gsub("^%s+", "")
        if v ~= "" and v ~= "[DONE]" then
          lastJson = v
        end
      end
    end
    if lastJson then
      data = lastJson
    else
      return nil, "SSE 响应中没有数据"
    end
  end
  local okJ, decoded = pcall(json.decode, data)
  if not okJ then return nil, "JSON 解析失败: " .. data:sub(1, 200) end
  return decoded, nil
end

-- ─── 生命周期 ──

_M._initCache = {}
_M._serverState = {}  -- url -> { protocolVersion = ..., sessionId = ... }（跨会话持久化）

local function serverState(url)
  local st = _M._serverState[url]
  if not st then
    st = {}
    _M._serverState[url] = st
  end
  return st
end

function _M.ensureInitialized(server)
  local key = serverKey(server)
  if _M._initCache[key] then return true end
  initLock.lock()
  local ok, result, err = pcall(function()
    if _M._initCache[key] then return true end
    local proto, initErr = _M.initialize(server)
    if not proto then return nil, initErr end
    _M._initCache[key] = proto
    return true
  end)
  initLock.unlock()
  if not ok then return nil, "初始化异常: " .. tostring(result) end
  return result, err
end

function _M.initialize(server)
  local key = serverKey(server)
  local res, err = rpcRequest(server, "initialize", {
    protocolVersion = DEFAULT_PROTO,
    capabilities = {},
    clientInfo = { name = "NeLuaJ+", version = "1.0" },
  })
  if not res then return nil, err end
  if res.error then return nil, rpcErrorText(res.error) end
  local proto = DEFAULT_PROTO
  if res.result and res.result.protocolVersion then
    proto = tostring(res.result.protocolVersion)
  end
  server.protocolVersion = proto
  local st = serverState(key)
  st.protocolVersion = proto
  -- MCP 初始化握手的第二步：通知服务器后续请求可以开始。
  local _, notifyErr = rpcRequest(server, "notifications/initialized", {}, false)
  if notifyErr then return nil, notifyErr end
  if server.sessionId and server.sessionId ~= "" then st.sessionId = server.sessionId end
  return proto, nil
end

-- ─── 工具 ──

_M._toolsCache = {}

function _M.listTools(server)
  local key = serverKey(server)
  local cached = _M._toolsCache[key]
  if cached and cached.time and (os.time() - cached.time) < 300 then
    return cached.tools
  end
  for attempt = 1, 2 do
    local okInit, initErr = _M.ensureInitialized(server)
    if not okInit then return nil, initErr end
    local tools, cursor = {}, nil
    for page = 1, 20 do
      local res, err = rpcRequest(server, "tools/list", cursor and { cursor = cursor } or {})
      if not res then
        if err == "MCP_SESSION_EXPIRED" and attempt == 1 then break end
        return nil, err
      end
      if res.error then return nil, rpcErrorText(res.error) end
      if res.result and type(res.result.tools) == "table" then
        for _, tool in ipairs(res.result.tools) do tools[#tools + 1] = tool end
      end
      cursor = res.result and res.result.nextCursor
      if not cursor or cursor == "" then
        _M._toolsCache[key] = { time = os.time(), tools = tools }
        return tools
      end
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
  local res, err = rpcRequest(server, "tools/call", params)
  if err == "MCP_SESSION_EXPIRED" then
    local retryInit, retryErr = _M.ensureInitialized(server)
    if not retryInit then return nil, retryErr end
    res, err = rpcRequest(server, "tools/call", params)
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
  for serverIndex, server in ipairs(_M.getServers()) do
    local tools = _M.listTools(server)
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
    for publicName, route in pairs(routes) do _M._toolRoutes[publicName] = route end
  end
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
      function(merged)
        _M._refreshing = false
        if generation ~= (_M._configGeneration or 0) then
          _M.refreshToolsAsync()
          return
        end
        if type(merged) == "table" then
          _M._mergedTools = merged
          _M._mergedAt = os.time()
        end
        local waiters = _M._refreshWaiters
        _M._refreshWaiters = {}
        for _, waiter in ipairs(waiters) do pcall(waiter, merged) end
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
  if _M._mergedTools and _M._mergedAt and (os.time() - _M._mergedAt) < 300 then
    return _M._mergedTools
  end
  _M.refreshToolsAsync()
  return _M._mergedTools
end

--- 异步调用 MCP 工具；onResult(ok, text)（主线程回调）
function _M.callToolAsync(server, toolName, args, onResult)
  local okLaunch = pcall(function()
    xTask(
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
