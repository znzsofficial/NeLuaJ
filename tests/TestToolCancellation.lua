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
local service = require('mods.files.FileMutationService')
local token, writes, synced = nil, 0, 0
local cfg = {
  context = { snapshot = function() return {scopePath='/p',directory='/p',projectGeneration=1} end },
  storage = function() return '/store' end,
  json = {encode=function(value) return value end},
  resolve = function() error('EACCES resolving path') end,
  prepare = function(_,_,owner) assert(owner==token); return 'editor snapshot' end,
  finish = function(snapshot) assert(snapshot=='editor snapshot' and token==nil); synced=synced+1; return true end,
  backend = {
    tryAcquire=function(id) if token then return '' end; token=id; return id end,
    release=function(id) assert(token==id); token=nil end,
    recover=function() return {recovered=true,results={}} end,
    observe=function(path) return {path=path,kind='file',text='old',version='v1'} end,
  },
}
service.configure(cfg); service.recover()
executor.configure({platformExecute=function() error('legacy writer must never execute') end})
local failure, failedOk, calls = nil, nil, 0
executor.executeToolAsync("create_file", { path = "blocked.txt" }, function(text, ok)
  failure, failedOk, calls = text, ok, calls + 1
end)
check("path resolution failures reach callback once", calls == 1 and failedOk == false
  and failure:find("EACCES", 1, true) and next(jobs) == nil)
cfg.resolve=function(path) return path end
xTask = function() error("executor unavailable") end
executor.executeToolAsync("create_file", {path='/p/a'}, function(text, ok)
  failure, failedOk, calls = text, ok, calls + 1
end)
check("launch failures preserve cause", calls == 2 and failedOk == false
  and failure:find("executor unavailable", 1, true) and next(jobs) == nil)
synced=0
local work, finish, nativeCancelled = nil, nil, 0
local writeJob
xTask = function(task, done)
  work, finish = task, done
  return { cancel = function() nativeCancelled = nativeCancelled + 1 end }
end
local blockedDuringPublish
cfg.backend.execute = function(_,_,request)
    writes = writes + 1
    executor.cancelJob(writeJob) -- Cancellation during synchronous disk execution.
    local _,ok,result=executor.executeTool('append_file',{path='/p/a',content='later'})
    blockedDuringPublish=ok==false and result.error.code=='busy'
    return {transactionId=request.transactionId,outcome='committed',changes={},warnings={}}
end
local deliveredWrites = 0
writeJob = executor.executeToolAsync("create_file", {path='/p/a'}, function(_,ok,result)
  assert(ok and result.outcome=='committed'); deliveredWrites = deliveredWrites + 1
end)
local result = work()
executor.cancelJob(writeJob)
assert(writes == 1 and nativeCancelled == 0 and next(jobs) == nil and blockedDuringPublish)
assert(token==nil,'terminal worker releases even without UI delivery')
finish(result)
finish(result)
assert(synced == 1 and deliveredWrites == 1,'committed cancellation publishes one factual result')
writeJob = executor.executeToolAsync("create_file", {path='/p/a'}, function(_,ok,result)
  assert(ok==false and result.error.code=='cancelled'); deliveredWrites = deliveredWrites + 1
end)
executor.cancelPending()
result = work()
finish(result)
assert(writes == 1 and synced == 1 and deliveredWrites == 2 and nativeCancelled == 0,
  'cancelled unpublished operation must not refresh editor')
assert(token==nil and executor.acquireFileWrite==nil)
print("PASS native-owned writes synchronize once; queued cancellation skips disk; worker owns release")
print("ALL-PASS")
