--- 视觉卡片流展平器：将 Session.messages() 转换为 RecyclerView 的数据源卡片列表。
--- 严密继承 ChatUI.lua 原有的工具回填算法，为每个卡片分配唯一的 stableId，供 DiffUtil 精准比对。
local _M = {}

local S = res.string

function _M.flatten(messages, opts)
  opts = opts or {}
  local cards = {}

  -- 1. 空会话欢迎卡片展平
  if (not messages or #messages == 0) and opts.welcome then
    cards[1] = {
      viewType = 6, -- TYPE_WELCOME
      stableId = "welcome_card",
      title = opts.welcome.title,
      body = opts.welcome.body,
    }
    return cards
  end

  if not messages or #messages == 0 then
    return cards
  end

  -- 2. 计算最新用户消息与最新 AI 助手消息的索引（用于展示操作行按钮）
  local lastUserIndex, lastAssistantIndex
  for i = #messages, 1, -1 do
    if not lastUserIndex and messages[i].role == "user" then lastUserIndex = i end
    if not lastAssistantIndex and messages[i].role == "assistant"
        and tostring(messages[i].content or "") ~= "" then
      lastAssistantIndex = i
    end
    if lastUserIndex and lastAssistantIndex then break end
  end

  local consumedTools = {}

  for messageIndex, msg in ipairs(messages) do
    if msg.role == "user" then
      cards[#cards + 1] = {
        viewType = 0, -- TYPE_USER
        stableId = "user_" .. (msg.id or tostring(messageIndex)),
        role = "user",
        content = tostring(msg.content or ""),
        message = msg,
        messageIndex = messageIndex,
        isLastUser = (messageIndex == lastUserIndex),
      }
    elseif msg.role == "assistant" then
      local content = msg.content or ""
      -- 仅当助手消息有正文或存在 continuation_state（如中断续写）时才展示气泡
      if content ~= "" or msg.continuation_state then
        cards[#cards + 1] = {
          viewType = 1, -- TYPE_ASSISTANT
          stableId = "asst_" .. (msg.id or tostring(messageIndex)),
          role = "assistant",
          content = content,
          message = msg,
          messageIndex = messageIndex,
          isLastAssistant = (messageIndex == lastAssistantIndex),
        }
      end

      -- 严格移植原工具配对算法：扫描后续连续的 tool 消息
      if msg.tool_calls then
        local resultById, resultWithoutId = {}, {}
        local scanIndex = messageIndex + 1
        while scanIndex <= #messages and messages[scanIndex].role == "tool" do
          local candidate = messages[scanIndex]
          if candidate.tool_call_id and candidate.tool_call_id ~= "" then
            resultById[candidate.tool_call_id] = { index = scanIndex, content = candidate.content or "" }
          else
            resultWithoutId[#resultWithoutId + 1] = { index = scanIndex, content = candidate.content or "" }
          end
          scanIndex = scanIndex + 1
        end

        local missingIndex = 1
        for tcIndex, tc in ipairs(msg.tool_calls) do
          local fn = tc["function"]
          local toolName = fn and fn.name or tc.name or ""
          local args = {}
          pcall(function() args = json.decode(fn and fn.arguments or tc.arguments or "{}") end)
          local tid = tc.id or ""
          local matched = tid ~= "" and resultById[tid] or nil
          if not matched then
            matched = resultWithoutId[missingIndex]
            if matched then missingIndex = missingIndex + 1 end
          end
          local result = matched and matched.content or nil
          if matched then consumedTools[matched.index] = true end

          cards[#cards + 1] = {
            viewType = 2, -- TYPE_TOOL
            stableId = "tool_" .. (tid ~= "" and tid or (messageIndex .. "_" .. tcIndex)),
            role = "tool",
            toolName = toolName,
            args = args,
            result = result,
            messageIndex = messageIndex,
          }
        end
      end
    elseif msg.role == "tool" then
      -- 孤立工具结果兜底展示（未被任何 assistant 关联的 tool 结果）
      local result = msg.content or ""
      if not consumedTools[messageIndex] and result ~= "" then
        cards[#cards + 1] = {
          viewType = 2, -- TYPE_TOOL
          stableId = "tool_orphan_" .. tostring(messageIndex),
          role = "tool",
          toolName = "tool_result",
          args = {},
          result = result,
          messageIndex = messageIndex,
        }
      end
      if msg.continuation_state then
        cards[#cards + 1] = {
          viewType = 1, -- TYPE_ASSISTANT
          stableId = "asst_cont_" .. tostring(messageIndex),
          role = "assistant",
          content = "",
          message = msg,
          messageIndex = messageIndex,
        }
      end
    end
  end

  -- 3. 尾部错误卡片兜底（倒序查找用户最后一次请求错误）
  for messageIndex = #messages, 1, -1 do
    local message = messages[messageIndex]
    if message.role == "user" and message.request_error then
      cards[#cards + 1] = {
        viewType = 5, -- TYPE_ERROR
        stableId = "error_" .. tostring(messageIndex),
        error = tostring(message.request_error),
        messageIndex = messageIndex,
      }
      break
    end
  end

  -- 4. 子代理实时任务进度卡片
  if opts.subtask and not opts.subtask.done then
    cards[#cards + 1] = {
      viewType = 7, -- TYPE_SUBTASK
      stableId = "subtask_active",
      subtask = opts.subtask,
    }
  end

  -- 5. 若有活动中的流式生成任务，压入独立的流式卡片
  if opts.activeStream and opts.activeStream.text then
    cards[#cards + 1] = {
      viewType = 4, -- TYPE_STREAMING
      stableId = "stream_active",
      text = opts.activeStream.text,
      streamId = opts.activeStream.id,
    }
  end

  return cards
end

return _M
