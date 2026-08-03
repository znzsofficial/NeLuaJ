--- OpenAI-compatible chat completions client.
--- Owns request construction, tool-call normalization, streaming and retries.
local _M = {}
local Thread = luajava.bindClass("java.lang.Thread")

local config

function _M.configure(options)
  config = options or {}
end

local function requireConfig()
  if not config then error("OpenAIClient 未配置") end
  return config
end

local function cloneValue(value)
  if type(value) ~= "table" then return value end
  local copy = {}
  for key, item in pairs(value) do copy[key] = cloneValue(item) end
  return copy
end

local function endpoint()
  local url = requireConfig().getApiUrl()
  if not url:match("/chat/completions$") then
    url = url:gsub("/+$", "") .. "/chat/completions"
  end
  return url
end

local function supportsTools(callbacks)
  local model = requireConfig().getModel():lower()
  return not callbacks.disableTools
    and not model:match("reasoner")
    and not model:match("r1%-")
    and not model:match("^o1")
    and not model:match("^o3")
end

local function repairToolHistory(messages)
  local pending
  local sequence = 0
  local function fallbackId()
    sequence = sequence + 1
    return "call_history_" .. tostring(sequence)
  end
  for _, message in ipairs(messages) do
    if message.role == "assistant" and message.tool_calls then
      pending = {}
      for _, call in ipairs(message.tool_calls) do
        call.id = call.id and call.id ~= "" and call.id or fallbackId()
        pending[#pending + 1] = call.id
      end
    elseif message.role == "tool" and pending and #pending > 0 then
      if not message.tool_call_id or message.tool_call_id == "" then
        message.tool_call_id = table.remove(pending, 1)
      else
        for index, id in ipairs(pending) do
          if id == message.tool_call_id then table.remove(pending, index) break end
        end
      end
    else
      pending = nil
    end
  end
end

local function prepareMessages(messages, toolsEnabled)
  local sendMessages = cloneValue(messages)
  if not toolsEnabled then
    local filtered = {}
    for _, message in ipairs(sendMessages) do
      if message.role == "tool" then
      elseif message.role == "assistant" and message.tool_calls then
        if message.content and message.content ~= "" then
          message.tool_calls = nil
          filtered[#filtered + 1] = message
        end
      else
        filtered[#filtered + 1] = message
      end
    end
    return filtered
  end
  repairToolHistory(sendMessages)
  return sendMessages
end

local function finishOnce(callbacks)
  local finished = false
  return function(callback, ...)
    if finished then return end
    finished = true
    if callback then callback(...) end
  end
end

function _M.sendStream(messages, callbacks)
  callbacks = callbacks or {}
  local finish = finishOnce(callbacks)
  local cfg = requireConfig()
  local key = cfg.getApiKey()
  if key == "" then finish(callbacks.onError, "请先设置 API Key") return end

  local enabled = supportsTools(callbacks)
  local body = {
    model = cfg.getModel(),
    messages = prepareMessages(messages, enabled),
    stream = true,
    max_tokens = callbacks.maxTokens or cfg.getMaxTokens(),
    temperature = cfg.getTemperature(),
  }
  if enabled then
    body.tools = {}
    for _, tool in ipairs(cfg.getBuiltinTools()) do body.tools[#body.tools + 1] = tool end
    local mcpTools = cfg.getMcpTools()
    if type(mcpTools) == "table" then
      for _, tool in ipairs(mcpTools) do body.tools[#body.tools + 1] = tool end
    end
  end
  if callbacks.onPrepared then callbacks.onPrepared(cfg.estimateRequestUsage(body)) end

  local bodyStr = json.encode(body)
  if not bodyStr or bodyStr == "" then finish(callbacks.onError, "请求体编码失败") return end
  local headers = {
    ["Authorization"] = "Bearer " .. key,
    ["Content-Type"] = "application/json",
  }
  local retries, attempt = cfg.getRetryCount(), 0
  local function retryable(message)
    message = tostring(message)
    if message:lower():match("cancel") then return false end
    if message:match("^HTTP 429") then return true end
    if message:match("^HTTP 4") then return false end
    return true
  end
  local function request()
    attempt = attempt + 1
    cfg.getHttpClient().postJsonStream(endpoint(), bodyStr, headers,
      function(text) if callbacks.onChunk then callbacks.onChunk(tostring(text)) end end,
      function(arg1, arg2)
        local text = tostring(arg1 or "")
        local isError = text:match("^HTTP") or text:match("^Stream") or text:match("^ERROR:") or text:match("^java")
        if isError then
          if attempt <= retries and retryable(text) then
            if callbacks.onRetry then callbacks.onRetry() end
            Thread.sleep(math.min(1200, attempt * 300))
            request()
            return
          end
          local detail = tostring(arg2 or "")
          if #detail > 500 then detail = detail:sub(1, 500) .. "…" end
          finish(callbacks.onError, text .. (detail ~= "" and "\n响应: " .. detail or "")
            .. "\n模型: " .. cfg.getModel() .. "\n地址: " .. endpoint())
          return
        end
        if arg2 and arg2 ~= "" then
          local ok, calls = pcall(json.decode, tostring(arg2))
          if ok and type(calls) == "table" then
            local parsed = {}
            for index, call in ipairs(calls) do
              local fn = call["function"]
              local name = call.name or (type(fn) == "table" and fn.name)
              local args = call.arguments or (type(fn) == "table" and fn.arguments)
              name = cfg.normalizeToolName(name)
              if name ~= "" then
                parsed[#parsed + 1] = {
                  id = call.id and call.id ~= "" and call.id or "call_" .. tostring(index),
                  name = name,
                  arguments = type(args) == "table" and json.encode(args) or (args or "{}"),
                }
              end
            end
            if #parsed > 0 then finish(callbacks.onToolCalls, parsed, text) return end
            if text ~= "" then finish(callbacks.onDone, text) return end
          end
        end
        if text == "" then finish(callbacks.onError, "AI 未返回内容\n模型: " .. cfg.getModel()) return end
        finish(callbacks.onDone, text)
      end)
  end
  request()
end

function _M.testConnection(onResult)
  local cfg = requireConfig()
  if cfg.getApiKey() == "" then if onResult then onResult(false, "请先设置 API Key") end return end
  local body = json.encode({ model = cfg.getModel(), messages = {{ role = "user", content = "ping" }}, max_tokens = 1, stream = false })
  cfg.getHttpClient().postJson(endpoint(), body, { ["Authorization"] = "Bearer " .. cfg.getApiKey() }, function(code)
    local ok = tonumber(tostring(code or "")) == 200
    if onResult then onResult(ok, ok and "连接成功，模型 " .. cfg.getModel() or "HTTP " .. tostring(code)) end
  end)
end

return _M
