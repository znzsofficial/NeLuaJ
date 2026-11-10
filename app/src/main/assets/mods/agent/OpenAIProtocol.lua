--- OpenAI-compatible protocol adaptation: request encoding and tool-call decoding.
local _M = {}

local function cloneValue(value)
  if type(value) ~= "table" then return value end
  local copy = {}
  for key, item in pairs(value) do copy[key] = cloneValue(item) end
  return copy
end

local function splitUrl(url)
  local base, query = tostring(url or ""):match("^([^?]*)(.*)$")
  return base or "", query or ""
end

local function apiHost(apiUrl)
  return (splitUrl(apiUrl):match("^https?://([^/%?:]+)") or ""):lower()
end

local function isAzureOpenAiHost(host)
  return host:match("^[%w%-]+%.openai%.azure%.com$") ~= nil
end

local function normalizeJsonArguments(args)
  if type(args) == "table" then
    if #args > 0 and next(args, #args) == nil then
      return "{}"
    end
    if type(json) == "table" and type(json.encode) == "function" then
      local ok, encoded = pcall(json.encode, args)
      if ok and type(encoded) == "string" and encoded:match("^%s*%{") then
        return encoded
      end
    end
    return "{}"
  end
  local s = tostring(args or ""):gsub("^%s*(.-)%s*$", "%1")
  if s == "" or s == "null" or s == "nil" then return "{}" end
  if s:sub(1, 1) ~= "{" or s:sub(-1) ~= "}" then return "{}" end
  local ok, decoded = false, nil
  if type(json) == "table" and type(json.decode) == "function" then
    ok, decoded = pcall(json.decode, s)
  end
  if ok and type(decoded) == "table" and not (#decoded > 0 and next(decoded, #decoded) == nil) then
    return s
  end
  return "{}"
end

local function sanitizeToolParameters(params)
  local p = type(params) == "table" and cloneValue(params) or { type = "object", properties = {} }
  if p.type ~= "object" then
    p.type = "object"
  end
  if type(p.properties) ~= "table" then
    p.properties = {}
  end
  return p
end

local function sanitizeTools(tools)
  if type(tools) ~= "table" then return {} end
  local cleaned = {}
  for _, tool in ipairs(tools) do
    if type(tool) == "table" then
      local t = cloneValue(tool)
      local fn = t["function"] or t
      if t.type == "function" and fn.name and fn.name ~= "" then
        local params = sanitizeToolParameters(fn.parameters)
        if t["function"] then
          t["function"].name = tostring(fn.name)
          t["function"].description = tostring(fn.description or "")
          t["function"].parameters = params
        else
          t = {
            type = "function",
            ["function"] = {
              name = tostring(fn.name),
              description = tostring(fn.description or ""),
              parameters = params,
            },
          }
        end
        cleaned[#cleaned + 1] = t
      end
    end
  end
  return cleaned
end

local function isDashscopeHost(host)
  return host:match("^dashscope[%w%-]*%.aliyuncs%.com$") ~= nil
end

local function isMiMoHost(host)
  return host == "xiaomimimo.com" or host:match("%.xiaomimimo%.com$") ~= nil
end

local function isOfficialResponsesHost(host)
  return host == "api.openai.com"
    or host == "api.deepseek.com"
    or host == "api.x.ai"
    or host == "api.stepfun.com"
    or isAzureOpenAiHost(host)
    or isDashscopeHost(host)
end

function _M.usesNativeResponsesHistory(apiUrl)
  -- Official Responses APIs require their complete output item sequence when
  -- history is replayed. Compatible relays often accept only portable
  -- function_call fields and can misread item UUIDs as function IDs.
  return isOfficialResponsesHost(apiHost(apiUrl))
end

function _M.responsesOrigin(apiUrl)
  local base = splitUrl(apiUrl)
  local host = apiHost(apiUrl)
  if isAzureOpenAiHost(host) then
    local origin = (base:match("^https?://[^/%?#]+") or ""):lower()
    return origin .. "/openai/v1"
  end
  return (base:match("^https?://[^/%?#]+") or ""):lower()
end

local function stripTerminalEndpoint(base)
  base = base:gsub("/+$", "")
  return base:gsub("/chat/completions$", ""):gsub("/responses$", "")
end

local function withXaiV1(base, apiUrl)
  if apiHost(apiUrl) == "api.x.ai" and not base:match("/v1$") then
    return (base:match("^https?://[^/%?#]+") or base) .. "/v1"
  end
  return base
end

function _M.endpoint(apiUrl, useResponses)
  local base, query = splitUrl(apiUrl)
  base = stripTerminalEndpoint(base)
  base = withXaiV1(base, apiUrl)
  local isAzure = isAzureOpenAiHost(apiHost(apiUrl))
  if not useResponses then
    if not isAzure or base:match("/openai/deployments/[^/]+$") then
      return base .. "/chat/completions" .. query
    end
    if base:match("/openai/v1$") then return base .. "/chat/completions" .. query end
    if base:match("/openai$") then return base .. "/v1/chat/completions" .. query end
    local origin = base:match("^https?://[^/%?#]+") or base
    return origin .. "/openai/v1/chat/completions" .. query
  end
  if isAzure then
    -- The legacy Azure deployment route does not expose Responses beneath the
    -- deployment. The deployment name belongs in the model field instead.
    base = base:gsub("(/openai)/deployments/[^/]+$", "%1")
    if base:match("/openai/v1$") then return base .. "/responses" .. query end
    if base:match("/openai$") then return base .. "/v1/responses" .. query end
    local origin = base:match("^https?://[^/%?#]+") or base
    return origin .. "/openai/v1/responses" .. query
  end
  -- The official DeepSeek Responses endpoint omits the commonly stored /v1.
  if apiHost(apiUrl) == "api.deepseek.com" and base:match("/v1$") then
    base = base:gsub("/v1$", "")
  end
  return base .. "/responses" .. query
end

function _M.requestHeaders(apiUrl, key)
  local host = apiHost(apiUrl)
  local headers = { ["Content-Type"] = "application/json" }
  -- Azure OpenAI uses api-key for API-key authentication, unlike the
  -- Bearer scheme used by the other OpenAI-compatible official endpoints.
  -- Azure and Xiaomi MiMo, including Token Plan, authenticate with api-key.
  -- MiMo also accepts Bearer, but Token Plan examples only document api-key.
  if isAzureOpenAiHost(host) or isMiMoHost(host) then headers["api-key"] = key
  else headers["Authorization"] = "Bearer " .. key end
  return headers
end

function _M.authHeaders(apiUrl, key)
  local headers = _M.requestHeaders(apiUrl, key)
  headers["Content-Type"] = nil
  return headers
end

function _M.modelsEndpoint(apiUrl)
  local base, query = splitUrl(apiUrl)
  base = withXaiV1(stripTerminalEndpoint(base), apiUrl)
  if base == "" then return "" end
  return base .. "/models" .. query
end

function _M.balanceRequest(apiUrl)
  local host = apiHost(apiUrl)
  local origin = (splitUrl(apiUrl):match("^https?://[^/%?#]+") or ""):lower()
  if origin == "" then return nil end
  if host == "api.deepseek.com" then
    return origin .. "/user/balance", "deepseek"
  end
  if host == "api.siliconflow.cn" or host == "api.siliconflow.com" then
    return origin .. "/v1/user/info", "siliconflow"
  end
  if host == "api.moonshot.cn" or host == "api.moonshot.ai" then
    return origin .. "/v1/users/me/balance", "moonshot"
  end
  if host == "openrouter.ai" then
    return origin .. "/api/v1/credits", "openrouter"
  end
  -- Pay-as-you-go and Token Plan publish model lists, but no balance API.
  if isMiMoHost(host) then return nil end
  local base = stripTerminalEndpoint(splitUrl(apiUrl))
  if base == "" then return nil end
  return base .. "/dashboard/billing/subscription", "subscription"
end

local function decodeJson(body)
  if type(json) ~= "table" or type(json.decode) ~= "function" then return nil end
  local ok, decoded = pcall(json.decode, tostring(body or ""))
  if not ok or type(decoded) ~= "table" then return nil end
  return decoded
end

local function modelIdOf(item)
  if type(item) == "string" then return item end
  if type(item) ~= "table" then return nil end
  local id = item.id or item.model or item.name
  if id == nil then return nil end
  return tostring(id):gsub("^%s*(.-)%s*$", "%1")
end

local function collectIds(list, ids, seen)
  if type(list) ~= "table" then return end
  local function add(item)
    local id = modelIdOf(item)
    if not id or id == "" or seen[id] then return end
    seen[id] = true
    ids[#ids + 1] = id
  end
  if #list > 0 then
    for index = 1, #list do add(list[index]) end
  else
    for _, item in pairs(list) do add(item) end
  end
end

function _M.parseModelIds(body)
  local decoded = decodeJson(body)
  if not decoded then return nil end
  local ids, seen = {}, {}
  collectIds(decoded.data or decoded.models or decoded, ids, seen)
  table.sort(ids)
  return ids
end

local function textOf(value)
  if value == nil then return "0" end
  return tostring(value)
end

function _M.parseBalance(kind, body)
  local decoded = decodeJson(body)
  if not decoded then return nil end
  if kind == "deepseek" then
    local infos = {}
    local source = decoded.balance_infos
    if type(source) == "table" then
      for index = 1, #source do
        local info = source[index]
        if type(info) == "table" and info.total_balance ~= nil then
          infos[#infos + 1] = {
            currency = textOf(info.currency),
            total = textOf(info.total_balance),
            topped_up = textOf(info.topped_up_balance),
            granted = textOf(info.granted_balance),
          }
        end
      end
    end
    if #infos == 0 then return nil end
    return { kind = "deepseek", available = decoded.is_available ~= false, infos = infos }
  end
  if kind == "siliconflow" then
    local data = type(decoded.data) == "table" and decoded.data or decoded
    if data.totalBalance == nil and data.balance == nil then return nil end
    return {
      kind = "siliconflow",
      total = textOf(data.totalBalance or data.balance),
      charge = textOf(data.chargeBalance),
      gift = textOf(data.balance),
    }
  end
  if kind == "moonshot" then
    local data = type(decoded.data) == "table" and decoded.data or decoded
    if data.available_balance == nil then return nil end
    return {
      kind = "moonshot",
      available = textOf(data.available_balance),
      cash = textOf(data.cash_balance),
      voucher = textOf(data.voucher_balance),
    }
  end
  if kind == "openrouter" then
    local data = type(decoded.data) == "table" and decoded.data or decoded
    local total = tonumber(data.total_credits)
    if not total then return nil end
    local used = tonumber(data.total_usage) or 0
    return {
      kind = "openrouter",
      remaining = string.format("%.4f", total - used),
      total = string.format("%.4f", total),
      used = string.format("%.4f", used),
    }
  end
  if kind == "subscription" then
    local amount = tonumber(decoded.hard_limit_usd or decoded.system_hard_limit_usd or decoded.soft_limit_usd)
    if not amount then return nil end
    return { kind = "subscription", amount = string.format("%.4f", amount) }
  end
  return nil
end

local function supportsTemperature(apiUrl, model)
  -- GPT-5, GPT-6 and o-series models reject temperature.
  -- 某些通过中转站代理的模型（如 o1, o3, o4, gpt-5, gpt-6 等）如果附带 temperature 会直接报 400：
  -- "The request could not be processed. Please check the request parameters."
  -- 因此对所有以 o1, o3, o4, gpt-5, gpt-6 开头的模型名称全面禁用 temperature。
  model = tostring(model or ""):lower()
  local mName = model:match("[^/]+$") or model
  if mName:match("^o[134]") or mName:match("^gpt%-[56]") then
    return false
  end

  local host = apiHost(apiUrl)
  if host == "api.x.ai" then
    return not model:match("^grok%-4")
      and not model:match("^grok%-3%-mini")
      and not model:match("^grok%-code")
  end
  return true
end

local function retainsResponsesReasoning(apiUrl, model)
  -- Native output items preserve reasoning for strict Responses APIs. This is
  -- only a fallback for old DeepSeek conversations created before that state
  -- was stored; relays must not receive provider-specific reasoning items.
  return apiHost(apiUrl) == "api.deepseek.com"
    and tostring(model or ""):lower():match("^deepseek%-") ~= nil
end

local function retainsChatReasoning(apiUrl, model)
  local host = apiHost(apiUrl)
  model = tostring(model or ""):lower()
  -- Moonshot-compatible Kimi endpoints require their reasoning field on the
  -- next Chat Completions turn. Keep the documented model alias for relays.
  return host == "api.moonshot.cn" or host == "api.moonshot.ai"
    or isMiMoHost(host)
    or model:match("^kimi[-%./]") ~= nil
    or model:match("/kimi[-%.]") ~= nil
    or model:match("^mimo%-") ~= nil
    or model:match("/mimo%-") ~= nil
end

local function usesGlmToolStream(apiUrl, model)
  local host = apiHost(apiUrl)
  model = tostring(model or ""):lower()
  return host == "open.bigmodel.cn"
    or (model:match("^glm[-%.]") ~= nil and (
      host:match("%.maas%.aliyuncs%.com$") ~= nil
      or isDashscopeHost(host)
    ))
end

local function pairsResponsesToolOutputs(apiUrl, model)
  -- DashScope's Qwen Responses implementation expects a tool result directly
  -- after its function_call item. Other strict endpoints receive the complete
  -- prior output sequence before their tool outputs, as documented by OpenAI.
  return isDashscopeHost(apiHost(apiUrl))
    and tostring(model or ""):lower():match("^qwen") ~= nil
end

local function repairToolHistory(messages)
  local repaired, sequence, index = {}, 0, 1
  local function fallbackId()
    sequence = sequence + 1
    return "call_history_" .. tostring(sequence)
  end
  while index <= #messages do
    local message = messages[index]
    if message.role == "assistant" and message.tool_calls then
      local pending, callOrder, callNames = {}, {}, {}
      for _, call in ipairs(message.tool_calls) do
        call.id = call.id and call.id ~= "" and call.id or fallbackId()
        local fn = call["function"] or call
        if fn then
          fn.arguments = normalizeJsonArguments(fn.arguments)
          if fn.name and fn.name ~= "" then
            callNames[call.id] = tostring(fn.name)
          end
        end
        pending[call.id] = true
        callOrder[#callOrder + 1] = call.id
      end
      local group, nextIndex, missingIndex = { message }, index + 1, 1
      while nextIndex <= #messages and messages[nextIndex].role == "tool" do
        local toolMessage = messages[nextIndex]
        if not toolMessage.tool_call_id or toolMessage.tool_call_id == "" then
          while callOrder[missingIndex] and not pending[callOrder[missingIndex]] do missingIndex = missingIndex + 1 end
          toolMessage.tool_call_id = callOrder[missingIndex]
        end
        if toolMessage.tool_call_id and pending[toolMessage.tool_call_id] then
          if (not toolMessage.name or toolMessage.name == "") and callNames[toolMessage.tool_call_id] then
            toolMessage.name = callNames[toolMessage.tool_call_id]
          end
          if not toolMessage.content or toolMessage.content == "" then
            toolMessage.content = "{}"
          end
          pending[toolMessage.tool_call_id] = nil
          group[#group + 1] = toolMessage
        end
        nextIndex = nextIndex + 1
      end
      if next(pending) == nil then
        for _, item in ipairs(group) do repaired[#repaired + 1] = item end
      elseif message.content and message.content ~= "" then
        message.tool_calls = nil
        message.response_output = nil
        message.response_origin = nil
        repaired[#repaired + 1] = message
      end
      index = nextIndex
    else
      repaired[#repaired + 1] = message
      index = index + 1
    end
  end
  return repaired
end

local function encodeLegacyFunctionHistory(messages)
  local encoded = {}
  local index = 1
  while index <= #messages do
    local message = messages[index]
    if message.role == "assistant" and message.legacy_function_call then
      local calls = message.tool_calls or {}
      local call = calls[1]
      local fn = call and (call["function"] or call)
      local name = fn and tostring(fn.name or "") or ""
      if #calls == 1 and name ~= "" then
        encoded[#encoded + 1] = {
          role = "assistant",
          content = tostring(message.content or ""),
          function_call = {
            name = name,
            arguments = normalizeJsonArguments(fn.arguments),
          },
        }
        local result = messages[index + 1]
        if result and result.role == "tool" and tostring(result.tool_call_id or "") == tostring(call.id or "") then
          encoded[#encoded + 1] = {
            role = "function",
            name = name,
            content = tostring(result.content or ""),
          }
          index = index + 2
        else
          index = index + 1
        end
      else
        message.legacy_function_call = nil
        encoded[#encoded + 1] = message
        index = index + 1
      end
    else
      message.legacy_function_call = nil
      encoded[#encoded + 1] = message
      index = index + 1
    end
  end
  return encoded
end

local function prepareMessages(messages, toolsEnabled, retainReasoning, stripItemIds)
  local prepared = cloneValue(messages)
  if stripItemIds then
    -- item_id belongs to a Responses output item, not the Chat Completions
    -- tool_calls schema. A conversation can switch protocols between turns;
    -- never leak this UUID into a compatible Chat Completions request.
    for _, message in ipairs(prepared) do
      for _, call in ipairs(message.tool_calls or {}) do call.item_id = nil end
      message.response_output = nil
      message.response_origin = nil
    end
  end
  if not toolsEnabled then
    for _, message in ipairs(prepared) do
      message.response_output = nil
      message.response_origin = nil
    end
  end
  if toolsEnabled then
    prepared = repairToolHistory(prepared)
  end
  if not retainReasoning then
    -- Ordinary Chat Completions turns must not send provider reasoning.
    for _, message in ipairs(prepared) do message.reasoning_content = nil end
  end
  if toolsEnabled and stripItemIds then
    return encodeLegacyFunctionHistory(prepared)
  end
  return prepared
end

local function copyResponseItems(items)
  if type(items) ~= "table" then return nil end
  local copied = {}
  for _, item in ipairs(items) do
    if type(item) == "table" and item.type then copied[#copied + 1] = cloneValue(item) end
  end
  return #copied > 0 and copied or nil
end

local function responsesInput(messages, includeReasoning, includeNativeOutput, nativeOrigin, includeFallbackItemIds, pairToolOutputs)
  local instructions, input, consumed = {}, {}, {}
  local function appendOutputForCall(messagesIndex, callId)
    for toolIndex = messagesIndex + 1, #messages do
      local toolMessage = messages[toolIndex]
      if toolMessage.role ~= "tool" then break end
      if not consumed[toolIndex] and tostring(toolMessage.tool_call_id or "") == tostring(callId or "") then
        input[#input + 1] = {
          type = "function_call_output",
          call_id = tostring(toolMessage.tool_call_id),
          output = tostring(toolMessage.content or ""),
        }
        consumed[toolIndex] = true
        return
      end
    end
  end
  for index, message in ipairs(messages) do
    if message.role == "system" or message.role == "developer" then
      instructions[#instructions + 1] = tostring(message.content or "")
    elseif message.role == "tool" then
      if not consumed[index] then
        input[#input + 1] = { type = "function_call_output", call_id = tostring(message.tool_call_id or ""), output = tostring(message.content or "") }
      end
    elseif includeNativeOutput and message.response_output
        and message.response_origin == nativeOrigin then
      -- Preserve every non-tool output item produced by the official Responses
      -- endpoint, including encrypted reasoning, assistant messages and calls.
      -- Tool results remain separate persisted tool messages below.
      local output = copyResponseItems(message.response_output)
      if output then
        for _, item in ipairs(output) do
          input[#input + 1] = item
          if pairToolOutputs and item.type == "function_call" then
            appendOutputForCall(index, item.call_id)
          end
        end
      end
    else
      if message.content and message.content ~= "" then input[#input + 1] = { role = message.role, content = tostring(message.content) } end
      if includeReasoning and message.reasoning_content and message.reasoning_content ~= "" then
        input[#input + 1] = { type = "reasoning", content = { { type = "reasoning_text", text = tostring(message.reasoning_content) } } }
      end
      for _, call in ipairs(message.tool_calls or {}) do
        local fn = call["function"] or call
        local functionCall = {
          type = "function_call",
          call_id = tostring(call.id or ""),
          name = tostring(fn.name or ""),
          arguments = normalizeJsonArguments(fn.arguments),
        }
        -- Older conversations predate persisted raw output. Preserve their
        -- known function item id for strict endpoints as the best fallback.
        if includeFallbackItemIds
            and (not message.response_origin or message.response_origin == nativeOrigin)
            and call.item_id and call.item_id ~= "" then
          functionCall.id = tostring(call.item_id)
        end
        input[#input + 1] = functionCall
        if pairToolOutputs then
          -- Qwen requires every function result directly after its call.
          appendOutputForCall(index, call.id)
        end
      end
    end
  end
  return table.concat(instructions, "\n\n"), input
end

local function collectTools(cfg)
  local tools = {}
  for _, tool in ipairs(cfg.getBuiltinTools()) do tools[#tools + 1] = tool end
  local mcpTools = cfg.getMcpTools()
  if type(mcpTools) == "table" then for _, tool in ipairs(mcpTools) do tools[#tools + 1] = tool end end
  return tools
end

local function responsesTools(tools)
  local out = {}
  for _, tool in ipairs(tools) do
    local fn = tool["function"] or tool
    if tool.type == "function" and fn.name then
      out[#out + 1] = {
        type = "function",
        name = fn.name,
        description = fn.description,
        parameters = sanitizeToolParameters(fn.parameters),
      }
    end
  end
  return out
end

local function legacyFunctions(tools)
  local out = {}
  for _, tool in ipairs(tools) do
    local fn = tool["function"] or tool
    if tool.type == "function" and fn.name then
      out[#out + 1] = {
        name = fn.name,
        description = fn.description,
        parameters = sanitizeToolParameters(fn.parameters),
      }
    end
  end
  return out
end

local function hasLegacyFunctionHistory(messages)
  for _, message in ipairs(messages or {}) do
    if message.role == "assistant" and message.legacy_function_call then return true end
  end
  return false
end

local function sanitizeMessagesForOpenAI(messages, retainReasoning, legacyFunctionMode)
  local cleaned = {}
  local pendingToolCalls = {} -- call_id -> { name = "..." }

  for _, msg in ipairs(messages or {}) do
    local role = msg.role
    local item = { role = role }
    local include = true

    if role == "assistant" then
      if type(msg.content) == "table" then
        item.content = cloneValue(msg.content)
      elseif msg.content and msg.content ~= "" then
        item.content = tostring(msg.content)
      elseif msg.tool_calls and #msg.tool_calls > 0 then
        -- 官方 OpenAI 规范：当包含 tool_calls 时，content 可以为 null，但部分转发中转站
        --（如 OneAPI / NewAPI）在反序列化时若 content 为 null 或空可能会校验失败；
        -- 对此给出标准空串保证 schema 兼容性
        item.content = ""
      else
        item.content = ""
      end

      if msg.tool_calls and #msg.tool_calls > 0 then
        local validCalls = {}
        for _, tc in ipairs(msg.tool_calls) do
          local fn = tc["function"] or tc
          local name = fn.name or tc.name
          if name and name ~= "" then
            local callId = tc.id and tc.id ~= "" and tc.id or ("call_" .. tostring(#validCalls + 1))
            validCalls[#validCalls + 1] = {
              id = callId,
              type = "function",
              ["function"] = {
                name = tostring(name),
                arguments = normalizeJsonArguments(fn.arguments),
              }
            }
            pendingToolCalls[callId] = { name = tostring(name) }
          end
        end
        if #validCalls > 0 then
          item.tool_calls = validCalls
        end
      end

      if retainReasoning and msg.reasoning_content and msg.reasoning_content ~= "" then
        item.reasoning_content = tostring(msg.reasoning_content)
      end

      if legacyFunctionMode and type(msg.function_call)=='table' and msg.function_call.name then
        item.function_call = {name=tostring(msg.function_call.name),
          arguments=normalizeJsonArguments(msg.function_call.arguments)}
      end

      -- 如果既无文本也无 tool_calls/function_call，不产生空 assistant
      if (item.content == "" or item.content == nil) and not item.tool_calls and not item.function_call then
        include = false
      end

    elseif role == "function" and legacyFunctionMode then
      item.name = tostring(msg.name or "")
      item.content = tostring(msg.content or "")
      if item.content == "" then item.content = "{}" end

    elseif role == "tool" then
      local callId = msg.tool_call_id
      -- 孤立 tool 消息如果找不到对应 assistant.tool_calls，将其转为 user 提示信息以满足 OpenAI/Gemini 校验
      local content = tostring(msg.content or "")
      if content == "" then content = "{}" end
      if callId and pendingToolCalls[callId] then
        item.tool_call_id = tostring(callId)
        item.content = content
        local callInfo = pendingToolCalls[callId]
        if type(callInfo) == "table" and callInfo.name and callInfo.name ~= "" then
          item.name = tostring(callInfo.name)
        elseif msg.name and tostring(msg.name) ~= "" then
          item.name = tostring(msg.name)
        end
        pendingToolCalls[callId] = nil
      else
        item.role = "user"
        item.content = "[Tool Output]\n" .. content
      end

    elseif role == "user" or role == "system" or role == "developer" then
      if type(msg.content) == "table" then
        item.content = cloneValue(msg.content)
      else
        item.content = tostring(msg.content or "")
        if item.content == "" then
          -- OpenAI / Gemini 要求 user/system content 不能为空
          item.content = "..."
        end
      end
    else
      -- 未知 role 统一当作 user
      item.role = "user"
      if type(msg.content) == "table" then
        item.content = cloneValue(msg.content)
      else
        item.content = tostring(msg.content or "...")
      end
    end

    if include then
      cleaned[#cleaned + 1] = item
    end
  end

  return cleaned
end

function _M.buildRequest(cfg, messages, callbacks)
  callbacks = callbacks or {}
  local model, apiUrl = cfg.getModel(), cfg.getApiUrl()
  local toolsEnabled = not callbacks.disableTools
  local useResponses = cfg.useResponses and cfg.useResponses() == true
  local nativeHistory = useResponses and _M.usesNativeResponsesHistory(apiUrl)
  local legacyFunctionMode = not useResponses and hasLegacyFunctionHistory(messages)
  local responseOrigin = _M.responsesOrigin(apiUrl)
  local retainReasoning = useResponses and retainsResponsesReasoning(apiUrl, model) or retainsChatReasoning(apiUrl, model)
  local prepared = prepareMessages(messages, toolsEnabled, retainReasoning, not useResponses)

  local function isGeminiTarget(url, m)
    local host = apiHost(url)
    return host:find("googleapis%.com") ~= nil or tostring(m or ""):lower():find("gemini", 1, true) ~= nil
  end

  local isGemini = isGeminiTarget(apiUrl, model)
  local continuing = prepared[#prepared] and prepared[#prepared].continuation_state ~= nil
  local function isPrunableAssistant(msg, preserveContinuation)
    if not msg or msg.role ~= "assistant" then return false end
    -- 若助手消息带有未完成或挂起的工具调用，末尾必须裁剪
    if msg.tool_calls and #msg.tool_calls > 0 then return true end
    local content = tostring(msg.content or "")
    if content == "" then return true end
    -- 仅当是非延续态（非续写请求）且面向 Gemini 时才裁剪末尾非空 assistant
    if isGemini and not preserveContinuation then return true end
    return false
  end

  -- Gemini / Google 官方 OpenAI 兼容层规范：请求消息列表末尾必须是用户 (user) 或工具结果 (tool/function) 轮次，
  -- 绝不允许以模型助手 (assistant) 轮次作为请求结尾。若末尾有残留的空 assistant 或未完结 assistant，将其裁剪以符合规范。
  while #prepared > 0 and isPrunableAssistant(prepared[#prepared], continuing) do
    table.remove(prepared, #prepared)
    continuing = false
  end

  -- 对兼容层（非 Responses API）的消息序列进行深度清洗：
  -- 1. 过滤内部扩展字段（如 request_error、response_origin、continuation_state 等）
  -- 2. 补齐孤立/丢失对应的 tool 消息，将其降级包装为普通用户消息
  -- 3. 避免空文本导致 Gemini 或某些转发中转站硬性抛 400
  if not useResponses then
    prepared = sanitizeMessagesForOpenAI(prepared, retainReasoning, legacyFunctionMode)
    -- 再次确保末尾不以非法 assistant 结尾
    while #prepared > 0 and isPrunableAssistant(prepared[#prepared], continuing) do
      table.remove(prepared, #prepared)
      continuing = false
    end
  end

  -- Keep the partial answer, but give Gemini a user turn to continue from.
  if isGemini and continuing and prepared[#prepared] and prepared[#prepared].role == "assistant" then
    prepared[#prepared + 1] = { role = "user", content = "Continue from where you stopped. Do not repeat the previous content." }
  end

  -- Gemini / CPA 规范：请求 contents 数组绝不可为空。
  -- 当中转站把开头的 system / developer 消息提取为 systemInstruction 后，
  -- 若剩余消息中无任何对话轮次（user 或 tool/function），Gemini 会报：
  -- "Gemini requires a non-empty contents array; provide user content and complete tool history"
  -- 因此在所有剪裁和清洗之后，若不存在对话轮次，追加一个兜底 user 消息保证 contents 非空。
  local hasConversationTurn = false
  for _, m in ipairs(prepared) do
    if m.role == "user" or m.role == "tool" or m.role == "function" then
      hasConversationTurn = true
      break
    end
  end
  if not hasConversationTurn then
    prepared[#prepared + 1] = {
      role = "user",
      content = "...",
    }
  end

  local body = useResponses and {
    model = model, stream = true, max_output_tokens = callbacks.maxTokens or cfg.getMaxTokens(),
  } or {
    model = model, messages = prepared, stream = true, max_tokens = callbacks.maxTokens or cfg.getMaxTokens(),
  }
  if supportsTemperature(apiUrl, model) then body.temperature = cfg.getTemperature() end
  local mName = tostring(model or ""):lower():match("[^/]+$") or tostring(model or ""):lower()
  local isReasoningModel = mName:match("^o[134]") or mName:match("^gpt%-[56]")
  if not useResponses and (isMiMoHost(apiHost(apiUrl)) or isReasoningModel) then
    body.max_completion_tokens = body.max_tokens
    body.max_tokens = nil
  end
  if useResponses and apiHost(apiUrl) == "api.x.ai" then
    -- Grok only replays reasoning when the encrypted item is requested and
    -- sent back inside the stored response output.
    body.include = { "reasoning.encrypted_content" }
  end
  if useResponses then
    body.instructions, body.input = responsesInput(
      prepared,
      retainsResponsesReasoning(apiUrl, model),
      nativeHistory,
      responseOrigin,
      nativeHistory,
      pairsResponsesToolOutputs(apiUrl, model)
    )
  end
  if toolsEnabled then
    -- callbacks.builtinTools：单请求工具集覆盖（子代理排除部分工具时使用）
    local tools = type(callbacks.builtinTools) == "table" and callbacks.builtinTools or collectTools(cfg)
    tools = sanitizeTools(tools)
    if legacyFunctionMode then
      body.functions = legacyFunctions(tools)
      if #body.functions > 0 then body.function_call = "auto" end
    else
      body.tools = useResponses and responsesTools(tools) or tools
      if #body.tools > 0 then
        body.tool_choice = "auto"
        if not useResponses and usesGlmToolStream(apiUrl, model) then body.tool_stream = true end
      end
    end
  end
  return body, useResponses, prepared[#prepared], {
    nativeResponsesHistory = nativeHistory,
    responsesOrigin = responseOrigin,
  }
end

function _M.parseToolCalls(encoded, normalizeToolName)
  local ok, calls = pcall(json.decode, tostring(encoded))
  if not ok or type(calls) ~= "table" then return nil end
  local parsed, reasoningContent = {}, nil
  for index, call in ipairs(calls) do
    local fn = call["function"]
    local name = normalizeToolName(call.name or (type(fn) == "table" and fn.name))
    local args = call.arguments or (type(fn) == "table" and fn.arguments)
    if name ~= "" then
      if not reasoningContent and call.reasoning_content then reasoningContent = tostring(call.reasoning_content) end
      parsed[#parsed + 1] = {
        id = call.id and call.id ~= "" and call.id or "call_" .. tostring(index),
        item_id = call.item_id,
        name = name,
        arguments = normalizeJsonArguments(type(args) == "table" and json.encode(args) or args),
        legacy_function_call = call.legacy_function_call == true,
      }
    end
  end
  return parsed, reasoningContent
end

function _M.parseResponseOutput(encoded)
  if encoded == nil or encoded == "" then return nil end
  local ok, output = pcall(json.decode, tostring(encoded))
  if not ok or type(output) ~= "table" then return nil end
  local parsed = {}
  for _, item in ipairs(output) do
    if type(item) == "table" and item.type then parsed[#parsed + 1] = item end
  end
  return #parsed > 0 and parsed or nil
end

function _M.hasUnstructuredToolIntent(text)
  local lower = tostring(text or ""):lower()
  -- This is diagnostics only, not a retry trigger. Match explicit first-person
  -- intent so ordinary explanations about tools remain valid assistant text.
  local phrases = {
    "我将调用", "我会调用", "正在调用", "我需要调用",
    "我将使用", "我会使用", "正在使用", "我需要使用",
    "i will call", "i'll call", "i am calling", "i need to call",
    "i will use", "i'll use", "i am using", "i need to use",
    "going to call", "going to use",
  }
  for _, phrase in ipairs(phrases) do
    if text:find(phrase, 1, true) or lower:find(phrase, 1, true) then return true end
  end
  return false
end

function _M.isRetryable(message)
  message = tostring(message)
  if message:lower():match("cancel") then return false end
  if message:match("^HTTP 429") then return true end
  return not message:match("^HTTP 4")
end

return _M
