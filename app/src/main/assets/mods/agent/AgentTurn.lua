--- Agent 回合状态机：generation 守卫、加载状态、keepalive、压缩触发、
--- 请求生命周期与工具循环。UI 通过 configure 注入视图钩子参与渲染与确认，
--- 本模块不持有任何视图引用；后台执行（前台服务）可直接观察和驱动本模块。
local _M = {}

local AgentChat = require("mods.agent.AgentChat")
local Session = require("mods.agent.SessionState")
local AsyncScope = require("mods.agent.AsyncScope")
local TodoManager = require("mods.agent.TodoManager")
local SubagentRunner = require("mods.agent.SubagentRunner")
local Contracts = require("mods.agent.Contracts")
local S = res.string


-- ─── 视图钩子（ChatUI 在 configure 时注入）──

local hooks = {}

-- ─── 回合状态 ──
-- loading 与原 ChatUI.isLoading 语义一致；generation/stopRequested/
-- activeStream/failedToolCalls/retryPayloads 亦与原模块级状态一一对应。

local state = {
  loading = false,
  generation = 0,
  stopRequested = false,
  activeStream = nil,
  activeToolStop = nil,
  retryPayloads = setmetatable({}, { __mode = "k" }),
  failedToolCalls = {},
}
local nextStreamId = 0

local function streamSnapshot()
  local stream = state.activeStream
  if not stream then return nil end
  return { id = stream.id, generation = stream.generation, text = stream.text }
end

local function publishStream()
  if hooks.onStreamChanged then hooks.onStreamChanged(streamSnapshot()) end
end

local function clearStream()
  state.activeStream = nil
  publishStream()
end

local function getMessages() return Session.messages() end

local function captureScope()
  state.scope = AsyncScope.capture(Session.projectPath(), Session.id(), state.generation)
end

local function isCurrentScope(scope)
  return scope and AsyncScope.matches(scope, Session.projectPath(), Session.id(), state.generation)
end

-- generation 相同只说明没有被 invalidate。还要核对请求开始时的工程和会话。
local function isCurrent(generation)
  return generation == state.generation
    and AsyncScope.matches(state.scope, Session.projectPath(), Session.id(), generation)
end

-- ─── 前台保活服务：回合进行中提升进程优先级并持有唤醒锁，息屏也能继续。
-- pcall 兜底：旧安装或类缺失时静默降级，绝不影响对话本身。

local function keepAliveAcquire()
  pcall(function()
    luajava.bindClass("com.nekolaska.ai.AgentKeepAliveService").acquire(activity)
  end)
end

local function keepAliveRelease()
  pcall(function()
    luajava.bindClass("com.nekolaska.ai.AgentKeepAliveService").release(activity)
  end)
end

-- ─── 加载状态 ──

function _M.showLoading()
  local was = state.loading
  state.loading = true
  -- 会话级“任务进行中”标记：进程被杀后用于中断提示；仅在状态翻转时落盘
  if not was and hooks.setConversationRunning then pcall(hooks.setConversationRunning, true) end
  if hooks.showViews then hooks.showViews() end
end

function _M.setLoadingStatus(text)
  if hooks.setLoadingStatusView then hooks.setLoadingStatusView(text, state.loading) end
end

function _M.hideLoading()
  local was = state.loading
  state.loading = false
  keepAliveRelease()
  if was and hooks.setConversationRunning then pcall(hooks.setConversationRunning, false) end
  -- 回合从进行中转为空闲时通知 UI（会话标题生成等收尾动作）
  if was and hooks.onTurnSettled then pcall(hooks.onTurnSettled) end
  if hooks.hideViews then hooks.hideViews() end
end

function _M.isActive() return state.loading end

function _M.generation() return state.generation end

function _M.activeStream() return streamSnapshot() end

function _M.rerenderStream()
  local stream = state.activeStream
  if stream and stream.generation == state.generation then
    publishStream()
  end
end

function _M.bumpGeneration()
  state.generation = state.generation + 1
  return state.generation
end

function _M.retryPayloadFor(message) return state.retryPayloads[message] end

-- 用户主动停止：保持当前 generation，让取消回调能保存已生成的部分文本。
function _M.requestStop()
  state.stopRequested = true
  pcall(SubagentRunner.cancel)
  if hooks.cancelToolConfirm then hooks.cancelToolConfirm() end
  local stopTool = state.activeToolStop
  state.activeToolStop = nil
  if stopTool then pcall(stopTool) end
  AgentChat.cancelPendingRequest()
  if AgentChat.cancelPendingTools then AgentChat.cancelPendingTools() end
  _M.hideLoading()
end

-- 彻底作废当前回合：切工程、清空会话、新建会话时调用。
function _M.invalidate()
  state.stopRequested = true
  pcall(SubagentRunner.cancel)
  if hooks.cancelToolConfirm then hooks.cancelToolConfirm() end
  state.generation = state.generation + 1
  state.stopRequested = false
  clearStream()
  AgentChat.cancelPendingRequest()
  if AgentChat.cancelPendingTools then AgentChat.cancelPendingTools() end
  local stopTool = state.activeToolStop
  state.activeToolStop = nil
  if stopTool then pcall(stopTool) end
  _M.hideLoading()
  return state.generation
end

-- ─── 工具循环（确认对话框在 UI 钩子里做）──

local executeToolCalls

local function finishStopped(toolCalls, index, args, turnScope, pendingText, taskInfo)
  -- 严格时空守卫：Fail-Closed 原则，未携带有效当前会话作用域一律禁止落盘
  if not isCurrentScope(turnScope) then return end
  local messages = getMessages()
  local placeholder
  -- Responses API 要求每个 function_call 都有配对的 function_call_output，
  -- 即使中途停止也要为剩余调用补上结果。
  for remaining = index, #toolCalls do
    local call = toolCalls[remaining]
    local callArgs = args
    if remaining ~= index or type(callArgs) ~= "table" then
      callArgs = {}
      pcall(function() callArgs = json.decode(call.arguments) end)
      if type(callArgs) ~= "table" then callArgs = {} end
    end
    local content = remaining == index and pendingText or S.ai_stopped
    if hooks.addToolBubble then
      hooks.addToolBubble(call.name, callArgs, content)
    end
    messages[#messages + 1] = {
      role = "tool",
      tool_call_id = call.id,
      content = content,
      task_info = remaining == index and taskInfo or nil,
    }
    if remaining == index then placeholder = messages[#messages] end
  end
  local stateMessage = messages[#messages]
  if stateMessage and stateMessage.role == "tool" then
    stateMessage.continuation_state = "stopped"
  end
  hooks.saveHistory()
  hooks.refreshMessageList()
  pcall(function()
    if MainActivity and MainActivity.RecyclerView then MainActivity.RecyclerView.update() end
  end)
  return placeholder
end

-- 并行批次执行：整批只读工具并发调度，结果全部回调后按调用顺序落盘，
-- 产生的历史与串行路径完全一致（配对顺序确定）。停止时先结算批次，
-- 再精确取消尚未完成的本批句柄，避免同步取消回调重新推进回合。
local function executeToolCallsParallel(calls, toolCalls, results, onAllDone, generation, turnScope)
  local total = #calls
  local pending = total
  local collected = {}
  local taskInfos = {}
  local handles, cancelled = {}, {}
  local stoppingBatch = false
  local function cancelPending(i)
    local handle = handles[i]
    if not collected[i] and not cancelled[i] and type(handle) == "table" and handle.cancel then
      cancelled[i] = true
      pcall(handle.cancel)
    end
  end
  local settled = false
  local stopBatch
  local function flush(stopping)
    if settled or not isCurrentScope(turnScope) then return end
    settled = true
    stoppingBatch = stopping
    if stopping then
      for i = 1, total do cancelPending(i) end
    end
    if not isCurrentScope(turnScope) then return end
    if state.activeToolStop == stopBatch then state.activeToolStop = nil end
    local messages = getMessages()
    for j = 1, total do
      local entry = collected[j]
      local content = entry and tostring(entry.result or "") or S.ai_stopped
      local toolOk, fileResult
      if entry then toolOk, fileResult = entry.ok, entry.fileResult end
      messages[#messages + 1] = { role = "tool", tool_call_id = calls[j].id, content = content,
        tool_ok = toolOk, file_result = fileResult, task_info = entry and entry.taskInfo or taskInfos[j] }
      results[#results + 1] = { tool_call_id = calls[j].id, content = content,
        tool_ok = toolOk, file_result = fileResult, task_info = entry and entry.taskInfo or taskInfos[j] }
      if entry then
        state.failedToolCalls[entry.key] = entry.ok == false and content:sub(1, 1000) or nil
      end
    end
    if stopping and messages[#messages] then messages[#messages].continuation_state = "stopped" end
    hooks.saveHistory()
    hooks.refreshMessageList()
    if not stopping then onAllDone(results) end
  end
  stopBatch = function() flush(true) end
  state.activeToolStop = stopBatch
  _M.setLoadingStatus(S.ai_tool_pending .. " · " .. S.ai_parallel_batch:format(total))
  for i = 1, total do
    if settled or state.stopRequested or not isCurrentScope(turnScope) then break end
    local call = calls[i]
    local tc = toolCalls[i]
    tc.name = call.name
    local argsEncoded, encodedArgs = pcall(json.encode, call.args)
    local toolCallKey = call.name .. "\n"
      .. (argsEncoded and tostring(encodedArgs) or tostring(tc.arguments or ""))
    local handle = AgentChat.executeToolAsync(call.name, call.args, function(resultStr, toolOk, fileResult, taskInfo)
      -- 严格时空守卫：世代或会话作用域已失效时，绝对禁止向活跃会话追加数据
      if settled or collected[i] or (generation and not isCurrent(generation)) or not isCurrentScope(turnScope) then return end
      collected[i] = { id = call.id, result = resultStr, ok = toolOk, key = toolCallKey, fileResult = fileResult, taskInfo = taskInfo }
      pending = pending - 1
      if taskInfo and taskInfo.waitState == "timed_out" then
        state.stopRequested = true
        flush(true)
        _M.hideLoading()
        return
      end
      if state.stopRequested then flush(true)
      elseif pending == 0 then flush(false) end
    end, { scope = turnScope, toolCallId = call.id, onWaitEnd = function(info)
      if settled or not isCurrentScope(turnScope) or collected[i] then return end
      taskInfos[i] = info
      state.stopRequested = true
      flush(true)
      _M.hideLoading()
    end })
    handles[i] = handle
    if stoppingBatch then cancelPending(i) end
    if type(handle) == "table" then taskInfos[i] = taskInfos[i] or { taskId = handle.taskId, scope = turnScope, toolCallId = call.id } end
  end
end

executeToolCalls = function(toolCalls, index, results, onAllDone, generation)
  if generation and not isCurrent(generation) then return end
  if state.stopRequested then return end
  -- 首轮先尝试整批并行：全部为只读白名单且免确认时并发执行；
  -- 混批、含写入/需确认/重复失败调用时自动回退串行路径，语义不变
  if index == 1 and AgentChat.classifyParallelBatch then
    local calls = AgentChat.classifyParallelBatch(toolCalls, state.failedToolCalls)
    if calls then
      local parallelScope = AsyncScope.capture(Session.projectPath(), Session.id(), generation or state.generation)
      executeToolCallsParallel(calls, toolCalls, results, onAllDone, generation, parallelScope)
      return
    end
  end
  if index > #toolCalls then
    -- 文件操作后刷新编辑器
    pcall(function()
      if MainActivity and MainActivity.RecyclerView then
        MainActivity.RecyclerView.update()
      end
    end)
    onAllDone(results)
    return
  end

  local tc = toolCalls[index]
  local args = {}
  local argsOk, argsError = pcall(function() args = json.decode(tc.arguments) end)
  if not argsOk or type(args) ~= "table" then
    args = {}
    argsError = argsOk and "工具参数必须是 JSON 对象" or tostring(argsError)
  end
  tc.name = AgentChat.normalizeToolName(tc.name, args)
  if tc.name == "run_lua" and (not args.code or args.code == "") and args.content then
    args.code = args.content
    args.content = nil
  end
  local argsEncoded, encodedArgs = pcall(json.encode, args)
  local toolCallKey = tc.name .. "\n" .. (argsEncoded and tostring(encodedArgs) or tostring(tc.arguments or ""))

  _M.setLoadingStatus(S.ai_tool_pending .. " · " .. (hooks.toolDisplayName and hooks.toolDisplayName(tc.name) or tc.name))
  local stopped = false
  local accepted = false
  local started = false
  local taskHandle, taskInfo, placeholder
  local stopHandle
  local turnScope = AsyncScope.capture(Session.projectPath(), Session.id(), generation or state.generation)
  local parentMessage, parentBaseContent
  local childFacts = {}
  local function applyChildFacts()
    if not parentMessage or #childFacts == 0 or not isCurrentScope(turnScope) then return end
    parentBaseContent = parentBaseContent or tostring(parentMessage.content or "")
    parentMessage.child_file_results = childFacts
    local lines = { parentBaseContent, "子任务文件事务最终事实（不代表父任务整体成功）：" }
    for _, fact in ipairs(childFacts) do
      lines[#lines + 1] = tostring(fact.file_result.transactionId or "未知事务") .. " · "
        .. tostring(fact.file_result.outcome or "结果已返回") .. "：" .. tostring(fact.content or "")
    end
    parentMessage.content = table.concat(lines, "\n")
  end
  local function onLateFileResult(text, ok, fileResult, childInfo, parentInfo)
    if tc.name ~= "run_subtask" or type(fileResult) ~= "table" or not isCurrentScope(turnScope) then return end
    local id = fileResult.transactionId or (childInfo and childInfo.transactionId)
    local entry = { content = text, tool_ok = ok, file_result = fileResult, task_info = childInfo,
      parent_task_id = parentInfo and parentInfo.taskId }
    local replaced = false
    for i, fact in ipairs(childFacts) do
      local oldId = fact.file_result.transactionId or (fact.task_info and fact.task_info.transactionId)
      if (id and oldId == id) or (not id and fact.file_result == fileResult) then
        childFacts[i], replaced = entry, true
        break
      end
    end
    if not replaced then childFacts[#childFacts + 1] = entry end
    applyChildFacts()
    if parentMessage then hooks.saveHistory(); hooks.refreshMessageList() end
  end
  local function finish()
    if not stopped then
      stopped = true
      if not taskInfo and type(taskHandle) == "table" then
        taskInfo = AgentChat.getTaskSnapshot and AgentChat.getTaskSnapshot(taskHandle.taskId)
          or { taskId = taskHandle.taskId, scope = turnScope, toolCallId = tc.id }
      end
      local writing = started and (tc.name == "create_file" or tc.name == "apply_patch"
        or tc.name == "delete_file" or tc.name == "rename_file" or tc.name == "write_file"
        or tc.name == "create_folder" or tc.name == "delete_folder"
        or tc.name == "append_file" or tc.name == "replace_in_file"
        or (taskInfo and taskInfo.fileMutation))
      local text = writing and "已请求取消，文件事务结果待确认" or nil
      if taskInfo and taskInfo.waitState == "timed_out" then
        text = "等待超时，已请求取消" .. (writing and "，文件事务结果待确认" or "")
      end
      placeholder = finishStopped(toolCalls, index, args, turnScope, text, taskInfo)
      parentMessage = placeholder
      applyChildFacts()
      if placeholder and #childFacts > 0 then hooks.saveHistory(); hooks.refreshMessageList() end
    end
  end

  local function proceedWithResult(resultStr, stopAfterResult, toolOk, fileResult, info)
    if not isCurrentScope(turnScope) then return end
    -- Cooperative cancellation may synchronously deliver the final file fact
    -- before requestStop invokes activeToolStop. Create its placeholder first.
    if state.stopRequested and not stopped and not accepted and fileResult then
      taskInfo = info or taskInfo
      finish()
    end
    if not stopped and not accepted and info and info.waitState == "timed_out" then
      taskInfo = info
      state.stopRequested = true
      finish()
      if state.activeToolStop == stopHandle then state.activeToolStop = nil end
      _M.hideLoading()
    end
    if stopped then
      if placeholder and fileResult and not accepted then
        accepted = true
        placeholder.content, placeholder.tool_ok = resultStr, toolOk
        placeholder.file_result, placeholder.task_info = fileResult, info or taskInfo
        hooks.saveHistory()
        hooks.refreshMessageList()
      end
      return
    end
    -- 仅清属于自己的停止句柄：过期回调不得抹掉当前回合的句柄
    if state.activeToolStop == stopHandle then state.activeToolStop = nil end
    if stopped or accepted or state.stopRequested or not isCurrentScope(turnScope) then return end
    accepted = true
    local failed = toolOk == false
    if toolOk == nil then failed = hooks.isToolError(tc.name, resultStr) end
    results[#results + 1] = {
      tool_call_id = tc.id,
      content = resultStr,
      tool_ok = toolOk,
      file_result = fileResult,
      task_info = info,
    }
    -- Persist each completed tool before proceeding. A later stop must not
    -- lose evidence of already-executed operations from the conversation.
    local messages = getMessages()
    messages[#messages + 1] = {
      role = "tool",
      tool_call_id = tc.id,
      content = resultStr,
      tool_ok = toolOk,
      file_result = fileResult,
      task_info = info,
    }
    parentMessage = messages[#messages]
    applyChildFacts()
    -- 任务计划状态在主线程提交：update 在工具线程只做规范化，
    -- 此处与下方 saveHistory 合并为一次落盘（携带 tool 结果与新计划）
    if tc.name == "update_todos" then pcall(TodoManager.commitPending) end
    -- 执行器的结构化标志优先（true=成功，false=失败）；旧式工具（nil）回退到文本嗅探
    if failed then
      state.failedToolCalls[toolCallKey] = tostring(resultStr):sub(1, 1000)
    else
      state.failedToolCalls[toolCallKey] = nil
    end
    hooks.saveHistory()
    hooks.refreshMessageList()
    if stopAfterResult then
      _M.hideLoading()
      clearStream()
      local messages2 = getMessages()
      messages2[#messages2 + 1] = {
        role = "assistant",
        content = "工具调用已停止：相同的工具名和参数已失败，未继续重复执行。请检查上一次错误并修改请求。",
      }
      hooks.saveHistory()
      hooks.refreshMessageList()
      return
    end
    if state.stopRequested then
      -- 当前调用的真实结果已在上文落盘，补齐从下一条开始的停止占位
      if not stopped then
        stopped = true
        finishStopped(toolCalls, index + 1, nil, turnScope)
      end
      return
    end
    executeToolCalls(toolCalls, index + 1, results, onAllDone, generation)
  end

  local function executeCurrentTool()
    if started or accepted or stopped or state.stopRequested or not isCurrentScope(turnScope) then return end
    started = true
    stopHandle = finish
    state.activeToolStop = stopHandle
    taskHandle = AgentChat.executeToolAsync(tc.name, args, function(resultStr, toolOk, fileResult, info)
      proceedWithResult(resultStr, nil, toolOk, fileResult, info)
    end, { scope = turnScope, toolCallId = tc.id, onLateFileResult = onLateFileResult, onWaitEnd = function(info)
      if accepted or stopped or not isCurrentScope(turnScope) then return end
      taskInfo = info
      state.stopRequested = true
      finish()
      if state.activeToolStop == stopHandle then state.activeToolStop = nil end
      _M.hideLoading()
    end })
  end

  if argsError then
    local errorText = "工具参数 JSON 无效，未执行 " .. tostring(tc.name) .. ": " .. tostring(argsError)
    state.failedToolCalls[toolCallKey] = errorText
    proceedWithResult(errorText)
    return
  end

  local previousFailure = state.failedToolCalls[toolCallKey]
  if previousFailure then
    proceedWithResult("为防止重复失败，未再次执行相同工具调用。\n前一次错误: " .. previousFailure, true)
    return
  end

  if AgentChat.shouldAutoApprove(tc.name, args) then
    executeCurrentTool()
  elseif (AgentChat.requiresConfirmation and AgentChat.requiresConfirmation(tc.name, args))
      or AgentChat.isDestructiveTool(tc.name) then
    hooks.showToolConfirm(tc.name, args, function()
      if (generation and not isCurrent(generation)) or state.stopRequested then
        finish()
        return
      end
      executeCurrentTool()
    end, function()
      if started or accepted or stopped then return end
      if (generation and not isCurrent(generation)) or state.stopRequested then
        finish()
        return
      end
      proceedWithResult(S.ai_user_denied)
    end)
  else
    executeCurrentTool()
  end
end

-- ─── 请求生命周期 ──

function _M.sendRaw(apiMessages, isContinue)
  local generation = state.generation
  captureScope()
  local messages = getMessages()
  local requestUserIndex
  -- 跳过压缩摘要合成的 user 消息，错误与重试要挂到真实的用户消息上
  for index = #messages, 1, -1 do
    local candidate = messages[index]
    if candidate.role == "user" and not candidate.compressed_summary then
      requestUserIndex = index
      break
    end
  end
  local requestMessage = requestUserIndex and messages[requestUserIndex]
  if requestMessage and requestMessage.request_error then
    requestMessage.request_error = nil
    hooks.saveHistory()
    hooks.refreshMessageList()
  end
  state.stopRequested = false
  local function isCurrentRequest() return isCurrent(generation) end
  if not isContinue then
    state.failedToolCalls = {}
  end
  _M.showLoading()
  keepAliveAcquire()

  -- 上下文用量显示：估算本次将发送的 token 数
  if hooks.updateContextUsage then
    hooks.updateContextUsage(AgentChat.estimateApiMessagesUsage(apiMessages))
  end

  local fullResponse = ""
  local toolsDispatched = false
  nextStreamId = nextStreamId + 1
  local streamState = { id = nextStreamId, generation = generation, text = "" }
  state.activeStream = streamState
  publishStream()

  AgentChat.sendStream(apiMessages, {
    onPrepared = function(usage)
      if not isCurrentRequest() or type(usage) ~= "table" then return end
      -- 会话用量统计：累计主请求数与估算输入 token（纯展示，不做限制）
      if hooks.reportUsage then pcall(hooks.reportUsage, usage.used) end
      if hooks.updateContextUsage then hooks.updateContextUsage(usage) end
    end,
    onChunk = function(chunk)
      if not isCurrentRequest() then return end
      _M.setLoadingStatus(S.ai_generating)
      fullResponse = fullResponse .. chunk
      streamState.text = fullResponse
      publishStream()
    end,
    -- 自动重试前清空已流出的内容，避免失败段落重复拼接
    onRetry = function()
      if not isCurrentRequest() then return end
      fullResponse = ""
      streamState.text = ""
      _M.setLoadingStatus(S.ai_retrying)
      publishStream()
    end,
    onToolCalls = function(toolCalls, text, reasoningContent, responseOutput, responseOrigin)
      if toolsDispatched or not isCurrentRequest() or state.stopRequested then return end
      toolsDispatched = true
      -- 不调用 hideLoading，保持加载状态直到续请求完成
      if text and text ~= "" and text ~= fullResponse then
        fullResponse = text
        streamState.text = text
      end

      -- 保存 assistant 消息（含 tool_calls）
      local assistantMsg = { role = "assistant" }
      if text and text ~= "" then
        assistantMsg.content = text
      end
      if reasoningContent and tostring(reasoningContent) ~= "" then
        assistantMsg.reasoning_content = tostring(reasoningContent)
      end
      if type(responseOutput) == "table" and #responseOutput > 0 and responseOrigin and responseOrigin ~= "" then
        assistantMsg.response_output = responseOutput
        assistantMsg.response_origin = responseOrigin
      end
      assistantMsg.tool_calls = {}
      for _, tc in ipairs(toolCalls) do
        assistantMsg.tool_calls[#assistantMsg.tool_calls + 1] = {
          id = tc.id,
          item_id = tc.item_id,
          type = "function",
          ["function"] = {
            name = tc.name,
            arguments = tc.arguments,
          },
        }
        if tc.legacy_function_call then assistantMsg.legacy_function_call = true end
      end
      local messages = getMessages()
      messages[#messages + 1] = assistantMsg
      hooks.saveHistory()
      clearStream()
      hooks.refreshMessageList()

      -- 执行工具调用
      executeToolCalls(toolCalls, 1, {}, function(results)
        if not isCurrentRequest() or state.stopRequested then return end
        -- 可选回合上限（ai_max_rounds，默认 0 = 不限制）：仅在工具续环时计数，
        -- 用户新消息即重置；手动“继续”不经过此处，不会被上限卡住
        local maxRounds = AgentChat.getMaxRounds and AgentChat.getMaxRounds() or 0
        state.roundsThisTurn = (state.roundsThisTurn or 0) + 1
        if maxRounds > 0 and state.roundsThisTurn > maxRounds then
          _M.hideLoading()
          local msgs = getMessages()
          msgs[#msgs + 1] = {
            role = "assistant",
            content = S.ai_round_limit:format(maxRounds),
            continuation_state = "round_limit",
          }
          hooks.saveHistory()
          hooks.refreshMessageList()
          state.generation = state.generation + 1
          state.stopRequested = false
          return
        end
        _M.send(true)
      end, generation)
    end,
    onEmptyAfterTools = function()
      if not isCurrentRequest() then return end
      _M.hideLoading()
      clearStream()
      -- The tool result is already in history. Do not add a blank assistant
      -- message, otherwise the next continuation may lose the tool context.
      local messages = getMessages()
      local stateMessage = messages[#messages]
      if stateMessage and stateMessage.role == "tool" then
        stateMessage.continuation_state = "empty_after_tools"
        hooks.saveHistory()
      end
      hooks.refreshMessageList()
    end,
    onDone = function(text, incomplete, responseOutput, responseOrigin, reasoningContent)
      if not isCurrentRequest() then return end
      _M.hideLoading()
      clearStream()
      local assistantMsg = { role = "assistant", content = text }
      if type(responseOutput) == "table" and #responseOutput > 0 and responseOrigin and responseOrigin ~= "" then
        assistantMsg.response_output = responseOutput
        assistantMsg.response_origin = responseOrigin
      end
      if reasoningContent and tostring(reasoningContent) ~= "" then
        assistantMsg.reasoning_content = tostring(reasoningContent)
      end
      if incomplete == true then assistantMsg.continuation_state = "incomplete" end
      local messages = getMessages()
      messages[#messages + 1] = assistantMsg
      hooks.saveHistory()
      hooks.refreshMessageList()
    end,
    onError = function(err)
      if toolsDispatched or not isCurrentRequest() then return end
      _M.hideLoading()
      clearStream()
      -- 用户主动停止：保留已生成部分，不显示错误
      if tostring(err):lower():match("cancel") then
        local messages = getMessages()
        local stateMessage = { role = "assistant", content = fullResponse, continuation_state = "stopped" }
        messages[#messages + 1] = stateMessage
        hooks.saveHistory()
        hooks.refreshMessageList()
        state.generation = state.generation + 1
        state.stopRequested = false
        return
      end
      local messages = getMessages()
      local requestMessage = requestUserIndex and messages[requestUserIndex]
      if not requestMessage or requestMessage.role ~= "user" then
        for i = #messages, 1, -1 do
          if messages[i].role == "user" then
            requestMessage = messages[i]
            break
          end
        end
      end
      if requestMessage and requestMessage.role == "user" then
        requestMessage.request_error = tostring(err)
        state.retryPayloads[requestMessage] = apiMessages
      end
      hooks.saveHistory()
      hooks.refreshMessageList()
      if hooks.onRequestError then hooks.onRequestError(err) end
    end,
  })
end

function _M.send(isContinue, userMsg)
  local generation = state.generation
  captureScope()
  -- 与旧 sendMessage/继续按钮的显式清位一致：上一回合的停止标记不能拦截新请求
  state.stopRequested = false
  if not isContinue then state.roundsThisTurn = 0 end
  _M.showLoading()
  -- 摘要请求本身也是一次模型调用，先保活再压缩，避免息屏时被 Doze 挂起
  keepAliveAcquire()
  local messages = getMessages()
  local requestHistory = messages
  -- Compression may be asynchronous; snapshot the continuation marker before
  -- the continue button clears it on the original UI message.
  if isContinue then
    requestHistory = {}
    for i, message in ipairs(messages) do
      local copy = {}
      for key, value in pairs(message) do copy[key] = value end
      requestHistory[i] = copy
    end
  end
  if userMsg and userMsg ~= "" then
    requestHistory = {}
    for i, message in ipairs(messages) do
      requestHistory[i] = message
    end
    local last = requestHistory[#requestHistory]
    if last and last.role == "user" then
      requestHistory[#requestHistory] = {}
      for key, value in pairs(last) do
        requestHistory[#requestHistory][key] = value
      end
      requestHistory[#requestHistory].content = userMsg
    end
  end
  AgentChat.buildCompressedApiMessages(requestHistory, function(apiMessages, compressed, compressedHistory)
    if not isCurrent(generation) or state.stopRequested then return end
    -- 自动压缩结果持久化到会话：后续发送不再重复摘要，直到再次超出预算。
    -- 带 userMsg 的重发基于请求副本压缩，副本里含编辑器上下文，不能落盘；
    -- 仅当压缩确实让历史变小或首条被摘要替换时才替换，避免无意义的重复落盘。
    if compressed and compressedHistory and #compressedHistory > 0 and not userMsg then
      local changed = #compressedHistory ~= #messages
        or not messages[1]
        or tostring(compressedHistory[1].content) ~= tostring(messages[1].content)
      if changed then
        Session.setMessages(compressedHistory)
        Session.resetTurns()
        hooks.saveHistory()
        hooks.refreshMessageList()
        print(S.ai_compress_auto_done:format(#compressedHistory))
      end
    end
    _M.sendRaw(apiMessages, isContinue)
  end)
end

function _M.compress(onDone)
  if state.loading then return false end
  state.generation = state.generation + 1
  local generation = state.generation
  captureScope()
  _M.showLoading()
  keepAliveAcquire()
  AgentChat.buildCompressedApiMessages(getMessages(), function(apiMessages, compressed)
    if not isCurrent(generation) then return end
    _M.hideLoading()
    if not compressed then
      print(S.ai_compress_unavailable)
      return
    end
    local compacted = {}
    for i = 2, #apiMessages do compacted[#compacted + 1] = apiMessages[i] end
    Session.setMessages(compacted)
    Session.resetTurns()
    hooks.saveHistory()
    hooks.refreshMessageList()
    print(S.ai_compress_done:format(#Session.messages()))
    if onDone then pcall(onDone) end
  end, true)
  return true
end

function _M.retry(payload)
  if state.loading then return false end
  _M.bumpGeneration()
  state.roundsThisTurn = 0
  if type(payload) == "table" and #payload > 0 then _M.sendRaw(payload, false)
  else _M.send(false) end
  return true
end

function _M.compressAndRetry(payload)
  if state.loading then return false end
  local generation = _M.bumpGeneration()
  captureScope()
  state.stopRequested = false
  state.roundsThisTurn = 0
  _M.showLoading()
  keepAliveAcquire()
  -- A captured retry payload may contain editor context. Compress only the
  -- outgoing request; do not persist it as conversation history.
  AgentChat.buildCompressedApiMessages(payload or getMessages(), function(apiMessages, compressed)
    if not isCurrent(generation) or state.stopRequested then return end
    if not compressed or type(apiMessages) ~= "table" or #apiMessages == 0 then
      _M.hideLoading()
      print(S.ai_compress_unavailable)
      return -- Leave the error card and its retry payload intact.
    end
    _M.sendRaw(apiMessages, false)
  end, true)
  return true
end

-- ─── 配置 ──
-- 消息、用量和撤销栈直接来自 SessionState。保存、刷新和确认仍由界面注入。

function _M.configure(options)
  hooks = Contracts.callbacks("AgentTurn", options, {
    "saveHistory", "refreshMessageList", "isToolError", "showToolConfirm",
  }, {
    "showViews", "hideViews", "setLoadingStatusView", "isPanelVisible",
    "scrollDown", "updateContextUsage", "addToolBubble", "cancelToolConfirm",
    "toolDisplayName", "reportUsage", "onTurnSettled",
    "setConversationRunning", "onRequestError", "onStreamChanged",
  })
end

return _M
