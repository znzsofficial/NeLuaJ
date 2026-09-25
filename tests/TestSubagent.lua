local ASSETS = ASSETS or "app/src/main/assets/"

-- SubagentRunner 行为测试：脚本化假模型与假工具执行器，同步驱动整个循环
package.preload["mods.utils.TextUtil"] = assert(loadfile(ASSETS .. "mods/utils/TextUtil.lua"))
local SR = assert(loadfile(ASSETS .. "mods/agent/SubagentRunner.lua"))()

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("PASS  " .. name)
  else
    failures = failures + 1
    print("FAIL  " .. name .. (detail ~= nil and ("  [" .. tostring(detail) .. "]") or ""))
  end
end

local script, fake, captured, executed, seenMessages, progressLog

local function reset(script_)
  script = script_
  fake = { auto = {}, confirm = {}, destructive = {}, onTool = nil, onConfirm = nil }
  captured = { overrides = {}, tools = {}, usage = {}, status = {} }
  executed = {}
  progressLog = {}
  SR.configure({
    getBuiltinTools = function()
      return {
        { type = "function", ["function"] = { name = "read_file" } },
        { type = "function", ["function"] = { name = "update_todos" } },
        { type = "function", ["function"] = { name = "run_subtask" } },
      }
    end,
    getSystemPrompt = function() return "BASE-PROMPT" end,
    getAuxModelConfig = function() return { model = "aux-m", url = "https://aux/v1", key = "aux-k", responses = false } end,
    sendStream = function(messages, callbacks)
      captured.overrides[#captured.overrides + 1] = callbacks.modelOverride
      captured.tools[#captured.tools + 1] = callbacks.builtinTools
      if callbacks.onPrepared then callbacks.onPrepared({ used = 100 }) end
      local stepDef = table.remove(script, 1)
      if not stepDef then error("脚本耗尽：未预期的第 " .. (#captured.overrides + 1) .. " 次请求") end
      stepDef(messages, callbacks)
    end,
    normalizeToolName = function(name) return name end,
    executeToolAsync = function(name, args, onResult)
      executed[#executed + 1] = { name = name, args = args }
      return fake.onTool(name, args, onResult)
    end,
    shouldAutoApprove = function(name) return fake.auto[name] == true end,
    requiresConfirmation = function(name) return fake.confirm[name] == true end,
    isDestructiveTool = function(name) return fake.destructive[name] == true end,
    showToolConfirm = function(name, args, onAllow, onDeny)
      return fake.onConfirm(name, args, onAllow, onDeny)
    end,
    setStatus = function(text) captured.status[#captured.status + 1] = text end,
    reportUsage = function(used) captured.usage[#captured.usage + 1] = used end,
    onProgress = function(info)
      progressLog[#progressLog + 1] = {
        rounds = info.rounds,
        tool = info.tool,
        done = info.done,
        hasTask = type(info.task) == "string" and #info.task > 0,
      }
    end,
    postToMain = function(fn) fn() end,
    sleepMs = function() end,
  })
end

local function stepTool(id, name)
  return function(messages, cb)
    cb.onToolCalls({ { id = id, name = name, arguments = "{}" } }, "")
  end
end

local function stepDone(text)
  return function(messages, cb)
    seenMessages = messages
    cb.onDone(text)
  end
end

-- 1. 直接完成
reset({ stepDone("简单结论") })
local r, ok = SR.run("做点什么", false)
check("direct done", ok == true and r == "简单结论", r)
check("not running after done", SR.isRunning() == false)
check("usage reported", #captured.usage == 1 and captured.usage[1] == 100)
check("status line shown", captured.status[1] and captured.status[1]:find("子任务", 1, true) ~= nil)

-- 2. 工具循环（自动批准）
reset({
  stepTool("t1", "read_file"),
  stepDone("调研结论"),
})
seenMessages = nil
fake.auto.read_file = true
fake.onTool = function(name, args, onResult) onResult("文件内容") end
r, ok = SR.run("查找文件", false)
check("tool loop completes", ok == true and r == "调研结论", r)
check("tool executed once", #executed == 1 and executed[1].name == "read_file")
check("portable tool history", seenMessages and #seenMessages == 4
  and seenMessages[3].role == "assistant" and seenMessages[3].tool_calls[1]["function"].name == "read_file"
  and seenMessages[4].role == "tool" and seenMessages[4].content == "文件内容"
  and seenMessages[4].tool_call_id == "t1")

-- 3. 确认后执行（需要确认的工具）
reset({
  stepTool("t2", "apply_patch"),
  stepDone("已修复"),
})
seenMessages = nil
fake.confirm.apply_patch = true
fake.onTool = function(name, args, onResult) onResult("已应用") end
fake.onConfirm = function(name, args, onAllow, onDeny) onAllow() end
r, ok = SR.run("修复代码", false)
check("confirm allow executes", ok == true and #executed == 1 and seenMessages[4].content == "已应用", r)

-- 4. 用户拒绝确认
reset({
  stepTool("t3", "apply_patch"),
  stepDone("改为说明"),
})
seenMessages = nil
fake.confirm.apply_patch = true
fake.onTool = function(name, args, onResult) onResult("不应执行") end
fake.onConfirm = function(name, args, onAllow, onDeny) onDeny() end
r, ok = SR.run("修复代码", false)
check("confirm deny recorded", ok == true and #executed == 0
  and seenMessages[4].content == "用户拒绝执行此操作", r)

-- 5. 工具执行期间取消
reset({
  stepTool("t4", "read_file"),
  function() error("不应继续第二轮") end,
})
fake.auto.read_file = true
fake.onTool = function(name, args, onResult)
  SR.cancel()
  onResult("部分结果")
end
r, ok = SR.run("会被停止的任务", false)
check("cancel mid-tool stops", ok == false and r == "子任务已被用户停止", r)
check("cancelled not running", SR.isRunning() == false)

-- 6. 模型请求被取消
reset({ function(messages, cb) cb.onError("cancelled") end })
r, ok = SR.run("任务", false)
check("request cancelled", ok == false and r == "子任务已被用户停止", r)

-- 7. 模型请求失败
reset({ function(messages, cb) cb.onError("HTTP 500: bad gateway") end })
r, ok = SR.run("任务", false)
check("request failure", ok == false and r:find("子任务请求失败", 1, true) ~= nil, r)

-- 8. 工具后空回复
reset({
  stepTool("t5", "read_file"),
  stepDone(""),
})
fake.auto.read_file = true
fake.onTool = function(name, args, onResult) onResult("ok") end
r, ok = SR.run("任务", false)
check("empty after tools noted", ok == true and r:find("未返回总结文本", 1, true) ~= nil, r)

-- 9. 工具集排除
reset({ stepDone("done") })
SR.run("任务", false)
local names = {}
for _, tool in ipairs(captured.tools[1]) do
  names[#names + 1] = tool["function"].name
end
check("subtools exclude delegation", #names == 1 and names[1] == "read_file", table.concat(names, ","))

-- 10. 系统提示 = 基础 + 子代理模式
reset({ function(messages, cb) seenMessages = messages; cb.onDone("x") end })
SR.run("任务", false)
check("prompt has base + subagent mode",
  seenMessages[1].content:find("BASE-PROMPT", 1, true) ~= nil
    and seenMessages[1].content:find("子代理模式", 1, true) ~= nil)

-- 11. lightweight 路由
reset({ stepDone("ok") })
SR.run("任务", true)
check("lightweight uses aux", captured.overrides[1] ~= nil and captured.overrides[1].model == "aux-m")
reset({ stepDone("ok") })
SR.run("任务", false)
check("default uses main model", captured.overrides[1] == nil)

-- 12. 结果截断
reset({ stepDone(string.rep("好", 3000)) })
r, ok = SR.run("任务", false)
check("result capped", ok == true and #r <= 4020 and r:find("已截断", 1, true) ~= nil, #r)

-- 13. 空任务
reset({})
r, ok = SR.run("", false)
check("empty task rejected", ok == false and r:find("描述为空", 1, true) ~= nil and #captured.overrides == 0, r)

-- 14. 进度上报：启动/轮次/工具/完成各节点
reset({
  stepTool("t9", "read_file"),
  stepDone("结论"),
})
fake.auto.read_file = true
fake.onTool = function(name, args, onResult) onResult("文件内容") end
r, ok = SR.run("调查任务", false)
local startInfo, roundInfo, toolInfo, doneInfo = progressLog[1], progressLog[2], progressLog[3], progressLog[#progressLog]
check("progress start reported", startInfo ~= nil and startInfo.hasTask and startInfo.rounds == 0
  and startInfo.done == false, startInfo and startInfo.rounds)
check("progress round reported", roundInfo ~= nil and roundInfo.rounds == 1, roundInfo and roundInfo.rounds)
check("progress tool reported", toolInfo ~= nil and toolInfo.tool == "read_file", toolInfo and toolInfo.tool)
check("progress done reported", doneInfo ~= nil and doneInfo.done == true and doneInfo.tool == nil)
check("progress snapshot cleared", SR.progressInfo() == nil)

if failures == 0 then print("ALL-PASS") else print("FAILURES: " .. failures) end
