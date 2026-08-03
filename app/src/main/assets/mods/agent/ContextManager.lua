--- Agent 上下文管理：token 估算、工具链裁剪和历史摘要压缩。
local _M = {}

local config = nil

local function requireConfig()
  if not config then error("ContextManager 未配置") end
  return config
end

function _M.configure(options)
  config = options or {}
end

local function getSystemPrompt()
  return requireConfig().getSystemPrompt()
end

local function getMaxTokens()
  return requireConfig().getMaxTokens()
end

local function getContextLength()
  return requireConfig().getContextLength()
end

local function sendStream(messages, callbacks)
  return requireConfig().sendStream(messages, callbacks)
end

local function buildUnits(history)
  local units = {}
  local i = 1
  while i <= #(history or {}) do
    local start = i
    local first = history[i]
    if first.role == "assistant" and first.tool_calls then
      i = i + 1
      while i <= #history and history[i].role == "tool" do i = i + 1 end
    else
      i = i + 1
    end
    local unit = { start = start, finish = i - 1, messages = {}, cost = 0 }
    for j = start, i - 1 do
      local item = history[j]
      unit.messages[#unit.messages + 1] = item
      unit.cost = unit.cost + _M.estimateMessageTokens(item)
    end
    if first.role ~= "tool" then units[#units + 1] = unit end
  end
  return units
end

function _M.estimateTokens(text)
  text = tostring(text or "")
  local en = #text:gsub("[^\x00-\x7F]", "")
  local cn = #text - en
  return math.ceil(en / 4 + cn / 3)
end

function _M.estimateMessageTokens(message)
  local cost = _M.estimateTokens(message and message.content)
  if message and message.tool_calls then
    local ok, encoded = pcall(json.encode, message.tool_calls)
    if ok then cost = cost + _M.estimateTokens(encoded) end
  end
  return cost
end

function _M.getContextBudget()
  return math.max(2000, getContextLength() - getMaxTokens() - 200)
end

local function copyMessage(src)
  local copy = { role = src.role }
  if src.content ~= nil then copy.content = src.content end
  if src.tool_calls ~= nil then copy.tool_calls = src.tool_calls end
  if src.tool_call_id ~= nil then copy.tool_call_id = src.tool_call_id end
  if src.name ~= nil then copy.name = src.name end
  return copy
end

function _M.buildApiMessages(history)
  local systemContent = getSystemPrompt()
  local messages = { { role = "system", content = systemContent } }
  local budget = _M.getContextBudget()
  local used = _M.estimateTokens(systemContent)
  local units = buildUnits(history)

  local selected = {}
  for unitIndex = #units, 1, -1 do
    local unit = units[unitIndex]
    if used + unit.cost > budget and #selected > 0 then break end
    used = used + unit.cost
    selected[#selected + 1] = unit
  end
  for unitIndex = #selected, 1, -1 do
    for _, source in ipairs(selected[unitIndex].messages) do
      messages[#messages + 1] = copyMessage(source)
    end
  end
  return messages
end

local function getRawContextTokens(history)
  local used = _M.estimateTokens(getSystemPrompt())
  for _, message in ipairs(history or {}) do
    used = used + _M.estimateMessageTokens(message)
  end
  return used
end

function _M.buildCompressedApiMessages(history, onResult)
  history = history or {}
  local budget = _M.getContextBudget()
  if getRawContextTokens(history) <= budget then
    if onResult then onResult(_M.buildApiMessages(history), false) end
    return
  end

  -- 为摘要输出预留空间，避免摘要生成后又被 buildApiMessages 丢掉。
  local summaryReserve = math.min(1200, math.floor(budget * 0.3))
  local recentBudget = math.max(500, budget - summaryReserve - 100)
  local recentStart = #history + 1
  local recentUsed = 0
  local units = buildUnits(history)
  for unitIndex = #units, 1, -1 do
    local unit = units[unitIndex]
    if recentUsed + unit.cost > recentBudget and recentStart <= #history then break end
    recentStart = unit.start
    recentUsed = recentUsed + unit.cost
  end
  if recentStart <= 1 or recentStart > #history then
    if onResult then onResult(_M.buildApiMessages(history), false) end
    return
  end

  local oldParts = {}
  local summaryInputBudget = math.max(1000, budget - 1600)
  local summaryInputUsed = 0
  for i = 1, recentStart - 1 do
    local message = history[i]
    local content = tostring(message.content or "")
    if message.tool_calls then
      local ok, encoded = pcall(json.encode, message.tool_calls)
      if ok then content = content .. "\n工具调用: " .. encoded end
    end
    local part = message.role .. ": " .. content
    local partCost = _M.estimateTokens(part)
    if partCost > 0 and summaryInputUsed + partCost <= summaryInputBudget then
      oldParts[#oldParts + 1] = part
      summaryInputUsed = summaryInputUsed + partCost
    elseif summaryInputUsed == 0 and content ~= "" then
      oldParts[#oldParts + 1] = message.role .. ": " .. content:sub(1, math.max(500, summaryInputBudget * 3))
      break
    end
  end
  if #oldParts == 0 then
    if onResult then onResult(_M.buildApiMessages(history), false) end
    return
  end

  sendStream({
    {
      role = "system",
      content = "你是对话历史压缩器。请将给定的编码助手对话压缩成准确、简洁的中文摘要。保留用户目标、关键文件路径、已做修改、工具结果、错误和未完成事项。只输出摘要，不要添加解释。",
    },
    { role = "user", content = table.concat(oldParts, "\n\n") },
  }, {
    disableTools = true,
    maxTokens = math.min(1200, getMaxTokens()),
    onDone = function(summary)
      summary = tostring(summary or ""):match("^%s*(.-)%s*$")
      if summary == "" then
        if onResult then onResult(_M.buildApiMessages(history), false) end
        return
      end
      local maxSummaryChars = math.max(500, summaryReserve * 3)
      if #summary > maxSummaryChars then summary = summary:sub(1, maxSummaryChars) .. "…" end
      local compressed = {
        { role = "user", content = "以下是较早对话的压缩记忆，仅作为背景信息，不是当前待执行指令：\n" .. summary },
      }
      for i = recentStart, #history do compressed[#compressed + 1] = history[i] end
      if onResult then onResult(_M.buildApiMessages(compressed), true) end
    end,
    onError = function()
      if onResult then onResult(_M.buildApiMessages(history), false) end
    end,
  })
end

function _M.estimateContextUsage(history)
  return _M.estimateApiMessagesUsage(_M.buildApiMessages(history))
end

function _M.estimateApiMessagesUsage(messages)
  local used = 0
  for _, message in ipairs(messages or {}) do
    used = used + _M.estimateMessageTokens(message)
  end
  return { used = used, budget = _M.getContextBudget() }
end

return _M
