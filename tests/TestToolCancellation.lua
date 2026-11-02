local assets = ASSETS or "app/src/main/assets/"
local function check(name, condition)
  assert(condition, name)
  print("PASS " .. name)
end
local jobs = {}
local registry = {
  register = function(job, name) jobs[job] = name end,
  unregister = function(job) jobs[job] = nil end,
  cancelAll = function()
    local batch, names = jobs, {}
    jobs = {}
    for job, name in pairs(batch) do names[#names + 1] = name; job.cancel() end
    return { size = function() return #names end, get = function(i) return names[i + 1] end }
  end,
}
luajava = { bindClass = function(name)
  assert(name == "com.nekolaska.agent.AgentJobRegistry")
  return registry
end }
local executor = assert(loadfile(assets .. "mods/agent/ToolExecutor.lua"))()
executor.configure({})
local callback, delivered = nil, 0
local function pendingTask(_, done)
  callback = done
  return { cancel = function() end }
end
xTask = pendingTask
local job = executor.executeToolAsync("get_env_info", {}, function() delivered = delivered + 1 end)
check("background job registered", jobs[job] ~= nil)
check("cancel reports active batch", executor.cancelPending())
check("cancel without callback clears native and Lua registry", next(jobs) == nil and not executor.cancelPending())
callback({ ok = true, result = "late" })
check("late callback stays suppressed after registry cleanup", delivered == 0)
local child = executor.executeToolAsync("get_env_info", {}, function() delivered = delivered + 1 end)
check("single child cancellation removes tracking", executor.cancelJob(child) and next(jobs) == nil)
callback({ ok = true, result = "late child" })
check("single child cancellation also suppresses late results", delivered == 0 and not executor.cancelPending())

xTask = function(_, done)
  done({ ok = true, result = "sync" })
  return { cancel = function() end }
end
executor.executeToolAsync("get_env_info", {}, function() delivered = delivered + 1 end)
check("synchronous completion never registers a ghost job", delivered == 1 and next(jobs) == nil)

executor.configure({
  findMcpServer = function() return {} end,
  callMcpToolAsync = function(_, _, _, done)
    callback = done
    return { cancel = function() done(false, "cancelled synchronously") end }
  end,
})
executor.executeToolAsync("mcp::server::tool", {}, function() delivered = delivered + 1 end)
executor.cancelPending()
check("reentrant cancel callback is suppressed before native cancellation", delivered == 1)
callback(true, "duplicate")
check("duplicate callback cannot revive a cancelled task", delivered == 1 and next(jobs) == nil)

executor.configure({
  findMcpServer = function() return {} end,
  callMcpToolAsync = function(_, _, _, done)
    done(true, "sync")
    return { cancel = function() end }
  end,
})
executor.executeToolAsync("mcp::server::tool", {}, function() delivered = delivered + 1 end)
check("synchronous MCP completion never registers a ghost job", delivered == 2 and next(jobs) == nil)
print("ALL-PASS")
