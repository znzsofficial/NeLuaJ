--- Agent 回合状态机：generation 守卫、加载状态、keepalive、压缩触发、
--- 请求生命周期与工具循环。UI 通过 configure 注入视图钩子参与渲染与确认，
--- 本模块不持有任何视图引用；后台执行（前台服务）可直接观察和驱动本模块。
local _M = {}

local AgentChat = require("mods.agent.AgentChat")
local TodoManager = require("mods.agent.TodoManager")
local SubagentRunner = require("mods.agent.SubagentRunner")
local S = res.string

-- 编辑器刷新依赖 EditorUtil 全局；自行 import，不依赖 ChatUI 的副作用
import "mods.utils.EditorUtil"

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

local function getMessages() return hooks.getMessages() end

local function isCurrent(generation) return generation == state.generation end

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

function _M.activeStream() return state.activeStream end

function _M.rerenderStream()
  local stream = state.activeStream
  if stream and stream.generation == state.generation and stream.render then
    stream.render()
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
  AgentChat.cancelPendingRequest()
  if AgentChat.cancelPendingTools then AgentChat.cancelPendingTools() end
  local stopTool = state.activeToolStop
  state.activeToolStop = nil
  if stopTool then pcall(stopTool) end
  _M.hideLoading()
end

-- 彻底作废当前回合：切工程、清空会话、新建会话时调用。
function _M.invalidate()
  state.stopRequested = true
  pcall(SubagentRunner.cancel)
  if hooks.cancelToolConfirm then hooks.cancelToolConfirm() end
  state.generation = state.generation + 1
  state.stopRequested = false
  state.activeStream = nil
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

local function finishStopped(toolCalls, index, args)
  local messages = getMessages()
  -- Responses API 要求每个 function_call 都有配对的 function_call_output，
  -- 即使中途停止也要为剩余调用补上结果。
  for remaining = index, #toolCalls do
    local call = toolCalls[remaining]
    local callArgs = args
    if remaining ~= index then
      callArgs = {}
      pcall(function() callArgs = json.decode(call.arguments) end)
      if type(callArgs) ~= "table" then callArgs = {} end
    end
    if hooks.addToolBubble then
      hooks.addToolBubble(call.name, callArgs, S.ai_stopped)
    end
    messages[#messages + 1] = {
      role = "tool",
      tool_call_id = call.id,
      content = S.ai_stopped,
    }
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
end

-- 并行批次执行：整批只读工具并发调度，结果全部回调后按调用顺序落盘，
-- 产生的历史与串行路径完全一致（配对顺序确定）。只读批次无确认间隙，
-- 无需 activeToolStop；用户停止时所有真实结果照常记录并标记 stopped。
local function executeToolCallsParallel(calls, toolCalls, results, onAllDone, generation)
  local total = #calls
  local pending = total
  local collected = {}
  _M.setLoadingStatus(S.ai_tool_pending .. " · " .. S.ai_parallel_batch:format(total))
  for i = 1, total do
    local call = calls[i]
    local tc = toolCalls[i]
    tc.name = call.name
    local argsEncoded, encodedArgs = pcall(json.encode, call.args)
    local toolCallKey = call.name .. "\n"
      .. (argsEncoded and tostring(encodedArgs) or tostring(tc.arguments or ""))
    AgentChat.executeToolAsync(call.name, call.args, function(resultStr, toolOk)
      if generation and not isCurrent(generation) then return end
      collected[i] = { id = call.id, result = resultStr, ok = toolOk, key = toolCallKey }
      pending = pending - 1
      if pending > 0 then return end
      -- 全部回调已到：按调用顺序落盘
      local messages = getMessages()
      for j = 1, total do
        local entry = collected[j]
        local content = tostring(entry.result)
        messages[#messages + 1] = {
          role = "tool",
          tool_call_id = entry.id,
          content = content,
        }
        results[#results + 1] = { tool_call_id = entry.id, content = content }
        if entry.ok == false then
          state.failedToolCalls[entry.key] = content:sub(1, 1000)
        else
          state.failedToolCalls[entry.key] = nil
        end
      end
      if state.stopRequested then
        local stateMessage = messages[#messages]
        if stateMessage and stateMessage.role == "tool" then
          stateMessage.continuation_state = "stopped"
        end
      end
      hooks.saveHistory()
      hooks.refreshMessageList()
      pcall(function()
        if MainActivity and MainActivity.RecyclerView then MainActivity.RecyclerView.update() end
      end)
      if state.stopRequested then return end
      onAllDone(results)
    end)
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
      executeToolCallsParallel(calls, toolCalls, results, onAllDone, generation)
      return
    end
  end
  if index > #toolCalls then
    -- 文件操作后刷新编辑器
    pcall(function()
      if MainActivity and MainActivity.RecyclerView then
        MainActivity.RecyclerView.update()
      end
      -- 如果修改了当前打开的文件，刷新编辑器；rename_file 命中旧路径时改载新路径
      local messages = getMessages()
      local function resolveToolPath(p)
        p = tostring(p or "")
        if p == "" then return nil end
        if p:sub(1, 1) ~= "/" then
          local base = Bean and Bean.Path and Bean.Path.this_dir or activity.getLuaDir()
          p = base .. "/" .. p
        end
        return p:gsub("/+$", "")
      end
      for _, r in ipairs(results) do
        if r.tool_call_id then
          for _, tc in ipairs(toolCalls) do
            if tc.id == r.tool_call_id and (tc.name == "create_file" or tc.name == "apply_patch"
                or tc.name == "append_file" or tc.name == "replace_in_file" or tc.name == "rename_file") then
              local args = {}
              pcall(function() args = json.decode(tc.arguments) end)
              if args.path then
                local thisFile = Bean and Bean.Path and Bean.Path.this_file
                if thisFile then
                  thisFile = tostring(thisFile):gsub("/+$", "")
                  local resolvedPath = resolveToolPath(args.path)
                  if tc.name == "rename_file" then
                    local renamedTo = resolveToolPath(args.new_path)
                    if thisFile == resolvedPath and renamedTo then
                      EditorUtil.load(renamedTo)
                    end
                  elseif thisFile == resolvedPath then
                    EditorUtil.load(resolvedPath)
                  end
                end
              end
            end
          end
        end
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
  local stopHandle
  local function finish()
    if not stopped then
      stopped = true
      finishStopped(toolCalls, index, args)
    end
  end

  local function proceedWithResult(resultStr, stopAfterResult, toolOk)
    -- 仅清属于自己的停止句柄：过期回调不得抹掉当前回合的句柄
    if state.activeToolStop == stopHandle then state.activeToolStop = nil end
    if generation and not isCurrent(generation) then return end
    results[#results + 1] = {
      tool_call_id = tc.id,
      content = resultStr,
    }
    -- Persist each completed tool before proceeding. A later stop must not
    -- lose evidence of already-executed operations from the conversation.
    local messages = getMessages()
    messages[#messages + 1] = {
      role = "tool",
      tool_call_id = tc.id,
      content = resultStr,
    }
    -- 任务计划状态在主线程提交：update 在工具线程只做规范化，
    -- 此处与下方 saveHistory 合并为一次落盘（携带 tool 结果与新计划）
    if tc.name == "update_todos" then pcall(TodoManager.commitPending) end
    -- 执行器的结构化标志优先（true=成功，false=失败）；旧式工具（nil）回退到文本嗅探
    local failed = toolOk == false
    if toolOk == nil then failed = hooks.isToolError(tc.name, resultStr) end
    if failed then
      state.failedToolCalls[toolCallKey] = tostring(resultStr):sub(1, 1000)
    else
      state.failedToolCalls[toolCallKey] = nil
    end
    hooks.saveHistory()
    hooks.refreshMessageList()
    if stopAfterResult then
      _M.hideLoading()
      state.activeStream = nil
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
        finishStopped(toolCalls, index + 1, args)
      end
      return
    end
    executeToolCalls(toolCalls, index + 1, results, onAllDone, generation)
  end

  local function executeCurrentTool()
    stopHandle = finish
    state.activeToolStop = stopHandle
    AgentChat.executeToolAsync(tc.name, args, function(resultStr, toolOk)
      proceedWithResult(resultStr, nil, toolOk)
    end)
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
  local streamState = { generation = generation, text = "" }
  state.activeStream = streamState
  if hooks.makeStreamRender then
    streamState.render = hooks.makeStreamRender(streamState)
  end
  streamState.render()

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
      streamState.render()
    end,
    -- 自动重试前清空已流出的内容，避免失败段落重复拼接
    onRetry = function()
      if not isCurrentRequest() then return end
      fullResponse = ""
      streamState.text = ""
      _M.setLoadingStatus(S.ai_retrying)
      streamState.render()
    end,
    onToolCalls = function(toolCalls, text, reasoningContent, responseOutput, responseOrigin)
      if not isCurrentRequest() or state.stopRequested then return end
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
      state.activeStream = nil
      hooks.refreshMessageList()

      -- 执行工具调用
      executeToolCalls(toolCalls, 1, {}, function(results)
        if not isCurrentRequest() or state.stopRequested then return end
        _M.send(true)
      end, generation)
    end,
    onEmptyAfterTools = function()
      if not isCurrentRequest() then return end
      _M.hideLoading()
      state.activeStream = nil
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
      state.activeStream = nil
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
      if not isCurrentRequest() then return end
      _M.hideLoading()
      state.activeStream = nil
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
  -- 与旧 sendMessage/继续按钮的显式清位一致：上一回合的停止标记不能拦截新请求
  state.stopRequested = false
  _M.showLoading()
  -- 摘要请求本身也是一次模型调用，先保活再压缩，避免息屏时被 Doze 挂起
  keepAliveAcquire()
  local messages = getMessages()
  local requestHistory = messages
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
        hooks.setMessages(compressedHistory)
        hooks.resetTurnHistory()
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
    hooks.setMessages(compacted)
    hooks.resetTurnHistory()
    hooks.saveHistory()
    hooks.refreshMessageList()
    print(S.ai_compress_done:format(#hooks.getMessages()))
    if onDone then pcall(onDone) end
  end, true)
  return true
end

-- ─── 配置 ──
-- getMessages/setMessages：会话数组归 ChatUI 所有，Turn 通过存取器访问。
-- resetTurnHistory：压缩替换历史后清除撤销/重做栈。
-- 其余为渲染与确认钩子。

function _M.configure(options)
  hooks = options or {}
end

return _M
