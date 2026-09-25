--- 子代理运行器：以隔离上下文执行主代理委派的单个任务并回传精简结果。
--- 能力（模型请求/工具执行/确认钩子/主线程投递）全部经 configure 注入，
--- 本模块不 require 其他 agent 模块，无循环依赖，可在独立 LuaJ 运行时测试。
--- 线程模型：run() 在工具执行线程同步等待（同 run_project 的阻塞模式），
--- 内部步骤经 postToMain 在主线程异步推进，与 UI/确认对话框同线程。
local _M = {}

local config = nil
local current = nil
local subSerial = 0

local function c()
  if not config then error("SubagentRunner 未配置") end
  return config
end

--- 合并式配置：ChatUI 可在 AgentChat 配置后再补 UI 钩子（状态条/用量上报）
function _M.configure(options)
  config = config or {}
  for key, value in pairs(options or {}) do config[key] = value end
end

function _M.isRunning()
  return current ~= nil
end

--- 用户停止/回合作废时由 AgentTurn 调用：当前子代理在完成手头请求后中止
function _M.cancel()
  if current then current.cancelled = true end
end

local function postToMain(fn)
  local post = config and config.postToMain
  if post then return post(fn) end
  if activity then
    pcall(function() activity.runOnUiThread(fn) end)
  else
    fn()
  end
end

local function sleepMs(ms)
  local sleep = config and config.sleepMs
  if sleep then return sleep(ms) end
  pcall(function()
    luajava.bindClass("java.lang.Thread").sleep(ms)
  end)
end

--- 子代理可用工具：完整内置工具，但排除委派与任务计划（防递归、计划归主代理）
local function subTools()
  local source = c().getBuiltinTools and c().getBuiltinTools() or {}
  local tools = {}
  for _, tool in ipairs(source) do
    local fn = tool["function"]
    local name = fn and fn.name or tool.name
    if name ~= "run_subtask" and name ~= "update_todos" then
      tools[#tools + 1] = tool
    end
  end
  return tools
end

local function buildPrompt()
  local base = c().getSystemPrompt and c().getSystemPrompt() or ""
  return base .. [[

# 子代理模式
你正以子代理身份独立执行一个委派任务，不与用户直接对话：
- 只完成给定任务并把最终结果输出给主代理；结果应自包含：结论、关键文件位置、遇到的阻塞。不相关的过程细节不要写。
- 你的回复不会进入用户界面，主代理只会收到你的最终文本。
- 你没有 run_subtask 与 update_todos；任务计划由主代理维护，不要建议用户修改计划。
- 工具确认策略与主代理完全一致；被拒绝时调整方案或说明阻塞，不要重试相同调用。]]
end

local TextUtil = require("mods.utils.TextUtil")

local function capResult(text, limit)
  local raw = tostring(text or "")
  local capped = TextUtil.utf8Cap(raw, limit)
  if #capped < #raw then capped = capped .. "…（已截断）" end
  return capped
end

--- 执行子任务。在工具执行线程调用，同步阻塞直至完成或被取消。
--- 返回 (resultText, ok)；ok=false 表示被停止/失败。
function _M.run(task, lightweight)
  if current then return "已有一个子代理在运行，请等待其完成后再委派", false end
  task = tostring(task or "")
  if task == "" then return "子任务描述为空，未执行", false end

  subSerial = subSerial + 1
  local state = { cancelled = false, done = false, result = nil, ok = false, rounds = 0 }
  current = state

  local messages = {
    { role = "system", content = buildPrompt() },
    { role = "user", content = task },
  }

  local function finish(result, ok)
    if state.done then return end
    state.done = true
    state.result = result
    state.ok = ok == true
    if current == state then current = nil end
  end

  local function setStatus(text)
    local report = c().setStatus
    if report then pcall(report, text) end
  end

  -- 取消观察点统一终结：任何回调观察到 cancelled 都必须 finish，
  -- 否则工具线程的等待循环会悬空
  local function stopIfCancelled()
    if state.cancelled and not state.done then
      finish("子任务已被用户停止", false)
    end
  end

  local runToolCalls

  local function step()
    stopIfCancelled()
    if state.done then return end
    state.rounds = state.rounds + 1
    local override = lightweight and c().getAuxModelConfig and c().getAuxModelConfig() or nil
    setStatus("子任务 #" .. subSerial .. " · 第 " .. state.rounds .. " 轮")
    c().sendStream(messages, {
      builtinTools = subTools(),
      modelOverride = override,
      onPrepared = function(usage)
        local report = c().reportUsage
        if report and type(usage) == "table" and usage.used then pcall(report, usage.used) end
      end,
      onToolCalls = function(toolCalls, text)
        stopIfCancelled()
        if state.done then return end
        -- 与主回合一致的可移植工具历史格式
        local assistantMsg = { role = "assistant" }
        if text and text ~= "" then assistantMsg.content = text end
        assistantMsg.tool_calls = {}
        for _, tc in ipairs(toolCalls) do
          assistantMsg.tool_calls[#assistantMsg.tool_calls + 1] = {
            id = tc.id,
            item_id = tc.item_id,
            type = "function",
            ["function"] = { name = tc.name, arguments = tc.arguments },
          }
          if tc.legacy_function_call then assistantMsg.legacy_function_call = true end
        end
        messages[#messages + 1] = assistantMsg
        runToolCalls(toolCalls, 1, function()
          postToMain(step)
        end)
      end,
      onDone = function(text)
        text = tostring(text or ""):match("^%s*(.-)%s*$") or ""
        if text == "" then
          finish("子代理已完成工具操作但未返回总结文本；可直接检查相关文件或让其补充说明。", true)
        else
          finish(text, true)
        end
      end,
      onError = function(err)
        if tostring(err):lower():match("cancel") then
          finish("子任务已被用户停止", false)
        else
          finish("子任务请求失败: " .. tostring(err), false)
        end
      end,
    })
  end

  runToolCalls = function(toolCalls, index, onAll)
    stopIfCancelled()
    if state.done then return end
    if index > #toolCalls then onAll() return end
    local tc = toolCalls[index]
    local args = {}
    pcall(function() args = json.decode(tc.arguments) end)
    tc.name = c().normalizeToolName(tc.name, args)
    local function proceedWithResult(resultStr)
      stopIfCancelled()
      if state.done then return end
      messages[#messages + 1] = {
        role = "tool",
        tool_call_id = tc.id,
        content = tostring(resultStr or ""),
      }
      runToolCalls(toolCalls, index + 1, onAll)
    end
    local function execute()
      c().executeToolAsync(tc.name, args, proceedWithResult)
    end
    -- 确认策略与主代理一致：自动批准直通；需确认的走全局确认钩子
    if c().shouldAutoApprove(tc.name, args) then
      execute()
    elseif c().requiresConfirmation(tc.name, args) or c().isDestructiveTool(tc.name) then
      c().showToolConfirm(tc.name, args, execute, function()
        proceedWithResult("用户拒绝执行此操作")
      end)
    else
      execute()
    end
  end

  postToMain(step)

  -- 工具线程同步等待；被取消时等当前请求的回调落定后退出
  while not state.done do
    sleepMs(200)
  end
  if current == state then current = nil end
  return capResult(state.result, 4000), state.ok
end

return _M
