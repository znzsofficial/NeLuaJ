--- OpenAI-compatible request lifecycle: streaming, retries and cancellation.
local _M = {}
local Protocol = require("mods.agent.OpenAIProtocol")
local Handler = luajava.bindClass("android.os.Handler")
local Looper = luajava.bindClass("android.os.Looper")
local retryHandler = Handler(Looper.getMainLooper())
local config
local pendingRequest

function _M.configure(options)
  config = options or {}
end

local function requireConfig()
  if not config then error("OpenAIClient 未配置") end
  return config
end

local function finishOnce(callbacks)
  local finished = false
  return function(callback, ...)
    if finished then return end
    finished = true
    if callback then callback(...) end
  end
end

local function formatError(text, detail, cfg, requestUrl)
  detail = tostring(detail or "")
  if #detail > 500 then detail = detail:sub(1, 500) .. "…" end
  return tostring(text) .. (detail ~= "" and "\n响应: " .. detail or "")
    .. "\n模型: " .. cfg.getModel() .. "\n地址: " .. requestUrl
end

local function unstructuredToolCallError(text, cfg, requestUrl)
  local preview = tostring(text or "")
  if #preview > 500 then preview = preview:sub(1, 500) .. "…" end
  return "模型表示将调用工具，但未返回结构化 tool_calls。为避免把未执行的操作当作已完成，已停止本轮。"
    .. "\n模型回复: " .. preview
    .. "\n模型: " .. cfg.getModel() .. "\n地址: " .. requestUrl
end

function _M.sendStream(messages, callbacks)
  callbacks = callbacks or {}
  local finish = finishOnce(callbacks)
  local cfg = requireConfig()
  -- 模型路由：辅助任务（压缩摘要/标题生成）经 callbacks.modelOverride 指定
  -- 其他供应商/模型；未指定或字段不全时维持当前主模型。
  local override = callbacks.modelOverride
  if type(override) == "table" and override.model and override.model ~= "" then
    local wrapped = {}
    for key, value in pairs(cfg) do wrapped[key] = value end
    wrapped.getModel = function() return tostring(override.model) end
    wrapped.getApiUrl = function() return tostring(override.url or "") end
    wrapped.getApiKey = function() return tostring(override.key or "") end
    wrapped.useResponses = function() return override.responses == true end
    cfg = wrapped
  end
  local key = cfg.getApiKey()
  if key == "" then finish(callbacks.onError, "请先设置 API Key") return end

  local body, useResponses, lastMessage, requestProfile = Protocol.buildRequest(cfg, messages, callbacks)
  local followsToolResult = lastMessage and lastMessage.role == "tool"
  if callbacks.onPrepared then callbacks.onPrepared(cfg.estimateRequestUsage(body)) end
  local bodyStr = json.encode(body)
  if not bodyStr or bodyStr == "" then finish(callbacks.onError, "请求体编码失败") return end

  local requestUrl = Protocol.endpoint(cfg.getApiUrl(), useResponses)
  local headers = Protocol.requestHeaders(cfg.getApiUrl(), key)
  local httpClient = cfg.getHttpClient()
  local retries, attempt = cfg.getRetryCount(), 0
  local requestState = { cancelled = false }
  pendingRequest = requestState
  local function finishRequest(callback, ...)
    if pendingRequest == requestState then pendingRequest = nil end
    finish(callback, ...)
  end
  function requestState.cancel()
    if requestState.cancelled then return end
    requestState.cancelled = true
    if requestState.retry then retryHandler.removeCallbacks(requestState.retry) end
    pcall(function() httpClient.cancelAll() end)
    finishRequest(callbacks.onError, "cancelled")
  end

  local function request()
    if requestState.cancelled then return end
    attempt = attempt + 1
    httpClient.postJsonStream(requestUrl, bodyStr, headers,
      function(text)
        if not requestState.cancelled and callbacks.onChunk then callbacks.onChunk(tostring(text)) end
      end,
      function(arg1, arg2, explicitError, incomplete, rawResponseOutput, rawReasoningContent)
        if requestState.cancelled then return end
        local text = tostring(arg1 or "")
        local streamedReasoning = rawReasoningContent and tostring(rawReasoningContent) or nil
        if streamedReasoning == "" then streamedReasoning = nil end
        local isError = explicitError == true or text:match("^HTTP %d%d%d$") or text:match("^ERROR:")
        if isError then
          if attempt <= retries and Protocol.isRetryable(text) then
            if callbacks.onRetry then callbacks.onRetry() end
            requestState.retry = function() request() end
            retryHandler.postDelayed(requestState.retry, math.min(1200, attempt * 300))
            return
          end
          finishRequest(callbacks.onError, formatError(text, arg2, cfg, requestUrl))
          return
        end
        if arg2 and arg2 ~= "" then
          local parsed, reasoningContent = Protocol.parseToolCalls(arg2, cfg.normalizeToolName)
          if parsed and #parsed > 0 then
            reasoningContent = reasoningContent or streamedReasoning
            if incomplete == true then
              if text ~= "" then finishRequest(callbacks.onDone, text, true, nil, nil, streamedReasoning)
              else finishRequest(callbacks.onError, "Responses 输出在工具调用完成前被截断") end
            else
              local responseOutput = requestProfile.nativeResponsesHistory
                and Protocol.parseResponseOutput(rawResponseOutput) or nil
              finishRequest(callbacks.onToolCalls, parsed, text, reasoningContent, responseOutput, requestProfile.responsesOrigin)
            end
            return
          end
        end
        if text ~= "" and type(body.tools) == "table" and #body.tools > 0
            and Protocol.hasUnstructuredToolIntent(text) then
          finishRequest(callbacks.onError, unstructuredToolCallError(text, cfg, requestUrl))
          return
        end
        if text == "" then
          if followsToolResult and callbacks.onEmptyAfterTools then finishRequest(callbacks.onEmptyAfterTools)
          else finishRequest(callbacks.onError, "AI 未返回内容\n模型: " .. cfg.getModel()) end
          return
        end
        local responseOutput = requestProfile.nativeResponsesHistory
          and Protocol.parseResponseOutput(rawResponseOutput) or nil
        finishRequest(callbacks.onDone, text, incomplete == true, responseOutput, requestProfile.responsesOrigin, streamedReasoning)
      end)
  end
  request()
end

function _M.cancelPending()
  local request = pendingRequest
  pendingRequest = nil
  if request and request.cancel then request.cancel() end
end

function _M.testConnection(onResult)
  local cfg = requireConfig()
  if cfg.getApiKey() == "" then if onResult then onResult(false, "请先设置 API Key") end return end
  local useResponses = cfg.useResponses and cfg.useResponses() == true
  local body = useResponses
    and json.encode({ model = cfg.getModel(), input = "ping", max_output_tokens = 1 })
    or json.encode({ model = cfg.getModel(), messages = {{ role = "user", content = "ping" }}, max_tokens = 1, stream = false })
  local url = Protocol.endpoint(cfg.getApiUrl(), useResponses)
  cfg.getHttpClient().postJson(url, body, Protocol.requestHeaders(cfg.getApiUrl(), cfg.getApiKey()), function(code)
    local ok = tonumber(tostring(code or "")) == 200
    if onResult then onResult(ok, ok and "连接成功，模型 " .. cfg.getModel() or "HTTP " .. tostring(code)) end
  end)
end

return _M
