local assets = ASSETS or "app/src/main/assets/"
package.path=assets..'?.lua;'..package.path
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
local configure=executor.configure
executor.configure=function(cfg)
  cfg.scheduleTimeout=cfg.scheduleTimeout or function() return function() end end
  configure(cfg)
end
executor.configure({})
local callback, delivered = nil, 0
local function pendingTask(_, done)
  callback = done
  return { cancel = function() end }
end
xTask = pendingTask
local job = executor.executeToolAsync("get_env_info", {}, function() delivered = delivered + 1 end)
check("underlying background job registered", next(jobs) ~= nil and jobs[job] == nil and job.taskId ~= nil)
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
cfg.scheduler = function() error("executor unavailable") end
executor.executeToolAsync("create_file", {path='/p/a'}, function(text, ok)
  failure, failedOk, calls = text, ok, calls + 1
end)
check("launch failures preserve cause", calls == 2 and failedOk == false
  and failure:find("executor unavailable", 1, true) and next(jobs) == nil)
synced=0
local work, finish, nativeCancelled = nil, nil, 0
local writeJob
cfg.scheduler = function(task, done)
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
local timers, timerCancels, underlyingCancels, results, waits = {},0,0,0,0
local function timedConfig(extra)
  local c={clockMillis=function() return 100 end,scheduleTimeout=function(ms,fn)
    timers[#timers+1]={ms=ms,fire=fn}; return function() timerCancels=timerCancels+1 end
  end}
  for k,v in pairs(extra or {}) do c[k]=v end
  executor.configure(c)
end
local callbacks={}
xTask=function(work,done)
  callbacks[#callbacks+1]=done
  return {cancel=function() underlyingCancels=underlyingCancels+1; done({ok=true,result='reentrant'}) end}
end
timedConfig({cancelFetch=function() error('global cancel forbidden') end})
local a=executor.executeToolAsync('fetch_url',{url='SECRET'},function() results=results+1 end,
  {scope={projectPath='/a',conversationId='one',generation=1},toolCallId='tc'})
local b=executor.executeToolAsync('fetch_url',{},function() results=results+1 end,
  {scope={projectPath='/b',conversationId='two',generation=1}})
assert(executor.cancelScope({projectPath='/a'})==1 and underlyingCancels==1 and timerCancels==1)
assert(executor.getTaskSnapshot(b.taskId).waitState=='waiting')
timers[2].fire(); timers[2].fire(); callbacks[2]({ok=true,result='late'})
assert(results==1 and underlyingCancels==2 and timerCancels==2)
assert(executor.getTaskSnapshot(b.taskId).waitState=='timed_out')
local c=executor.executeToolAsync('get_env_info',{},function() results=results+1 end,
  {onWaitEnd=function(info) waits=waits+1; assert(info.waitState=='timed_out') end})
timers[3].fire(); assert(waits==1 and results==1)
assert(not executor.cancelJob(c))
check('scoped precise cancellation, reentrant callbacks and single timeout cleanup',true)

-- Real file service: waiting ends separately; the committed final result survives.
cfg.backend.execute=function(_,_,request)
  writes=writes+1
  return {transactionId=request.transactionId,outcome='committed',changes={},warnings={}}
end
local finalInfo,waitInfo
local f=executor.executeToolAsync('create_file',{path='/p/a'},function(_,ok,_,info)
  assert(ok); finalInfo=info
end,{scope={projectPath='/p',conversationId='file',generation=2},toolCallId='file-call',
  onWaitEnd=function(info) waitInfo=info end})
result=work() -- Disk has committed, owner notification is still queued.
timers[4].fire()
assert(waitInfo.taskId==f.taskId and waitInfo.transactionId and finalInfo==nil)
finish(result); finish(result)
assert(finalInfo.transactionId==waitInfo.transactionId and finalInfo.taskId==f.taskId
  and finalInfo.scope.conversationId=='file' and finalInfo.toolCallId=='file-call'
  and finalInfo.waitState=='timed_out' and finalInfo.executionState=='settled')
assert(nativeCancelled==0)
local noWaitResults=0
local g=executor.executeToolAsync('create_file',{path='/p/a'},function() noWaitResults=noWaitResults+1 end)
timers[5].fire(); assert(noWaitResults==0)
result=work(); finish(result); assert(noWaitResults==1)
check('file timeout keeps transaction and factual final callback, including legacy callers',true)

local errors=0
local function failed(_,ok,_,info) assert(ok==false and info.executionState=='settled'); errors=errors+1 end
timedConfig({scheduleTimeout=function() error('timer failed') end})
assert(executor.executeToolAsync('get_env_info',{},failed).taskId)
timedConfig({scheduleTimeout=function() return nil end})
executor.executeToolAsync('get_env_info',{},failed)
configure({}) -- Deliberately bypass test default timer.
executor.executeToolAsync('get_env_info',{},failed)
timedConfig({resolvePath=function() error('path failed') end})
executor.executeToolAsync('read_file',{path='bad'},failed)
xTask=function() error('launch failed') end
executor.executeToolAsync('get_env_info',{},failed)
executor.executeToolAsync('mcp::broken',{},failed)
assert(errors==6 and not executor.cancelPending())
check('timer configuration, installation, path, launch and MCP errors settle once',true)

local internal, original={},{task='child'}
timedConfig({platformExecute=function(_,args) internal=args; return 'ok',true end})
xTask=function(worker,done) done(worker()); return {cancel=function() error('completed') end} end
local childHandle=executor.executeToolAsync('run_subtask',original,function() end,{scope={projectPath='/scope',generation=3}})
assert(internal.__task_context.taskId==childHandle.taskId and internal.__task_context.scope.projectPath=='/scope'
  and original.__task_context==nil and timers[#timers].ms==190000)
executor.executeToolAsync('build_project',{},function() end)
assert(timers[#timers].ms==300000)
check('subtask context is internal and tool-specific wait budgets are preserved',true)

local owner,posted=true,{}
timedConfig({isOwnerThread=function() return owner end,postToOwner=function(fn) posted[#posted+1]=fn end})
xTask=function(_,done) callback=done; return {cancel=function() end} end
local marshalled=executor.executeToolAsync('get_env_info',{},function() assert(owner) end)
owner=false; callback({ok=true,result='worker result'})
assert(executor.getTaskSnapshot(marshalled.taskId).waitState=='waiting' and #posted==1)
owner=true; posted[1]()
assert(executor.getTaskSnapshot(marshalled.taskId).executionState=='settled')
check('worker callbacks marshal registry mutation to owner',true)
local subCancels,parent=0,nil
timedConfig({cancelSubtask=function(id)
  subCancels=subCancels+1
  assert(id==parent.taskId and executor.getTaskSnapshot(id).waitState=='timed_out')
  executor.cancelPending() -- Reentrant child cancellation must not cancel parent twice.
end})
parent=executor.executeToolAsync('run_subtask',{},function() end,{onWaitEnd=function() end})
timers[#timers].fire(); timers[#timers].fire(); parent.cancel()
assert(subCancels==1)
check('parent-specific subtask cancellation is marked before reentry and invoked once',true)
local long=string.rep('/long-project',40)
local longScope={projectPath=long,conversationId=long..'/conversation',generation=long..'/generation'}
timedConfig()
local longJob=executor.executeToolAsync('get_env_info',{},function() error('cancelled') end,{scope=longScope})
local sibling=executor.executeToolAsync('get_env_info',{},function() end,{scope={projectPath=long..'/sibling'}})
assert(executor.cancelScope(longScope)==1 and executor.getTaskSnapshot(longJob.taskId).waitState=='cancelled')
assert(executor.getTaskSnapshot(sibling.taskId).waitState=='waiting'); sibling.cancel()
check('long scope identities cancel exactly the matching task',true)

local lateContext,lateEvents,parentResults= nil,0,0
local lateOwner,latePosted=true,{}
timedConfig({historyLimit=1,isOwnerThread=function() return lateOwner end,
  postToOwner=function(fn) latePosted[#latePosted+1]=fn end,
  platformExecute=function(_,args) lateContext=args.__task_context; return 'parent result',true end})
xTask=function(worker,done) worker(); callback=done; return {cancel=function() end} end
local lateParent
lateParent=executor.executeToolAsync('run_subtask',{task='child'},function() parentResults=parentResults+1 end,
  {scope=longScope,toolCallId=long,parentId=long,onWaitEnd=function() end,
    onLateFileResult=function(text,ok,fileResult,childInfo,parentTaskInfo)
      assert(lateOwner and text=='committed body' and ok and fileResult.transactionId=='child-tx'
        and childInfo.taskId=='child-task' and parentTaskInfo.taskId==lateParent.taskId
        and parentTaskInfo.scope.projectPath==long and parentTaskInfo.scope.conversationId==longScope.conversationId
        and parentTaskInfo.toolCallId==long and parentTaskInfo.waitState=='timed_out')
      parentTaskInfo.scope.projectPath='mutated by consumer'
      lateEvents=lateEvents+1
    end})
local event=lateContext.onLateFileResult
assert(lateContext.scope.projectPath==long)
timers[#timers].fire()
local stateBefore=executor.getTaskSnapshot(lateParent.taskId).executionState
event('committed body',true,{transactionId='child-tx'},{taskId='child-task'})
assert(executor.getTaskSnapshot(lateParent.taskId).executionState==stateBefore and parentResults==0)
-- Evict the parent without delivering its suppressed final callback.
xTask=function(_,done) done({ok=true,result='other'}); return {} end
executor.executeToolAsync('get_env_info',{},function() end)
assert(executor.getTaskSnapshot(lateParent.taskId)==nil)
lateOwner=false
event('committed body',true,{transactionId='child-tx'},{taskId='child-task'})
assert(lateEvents==1 and #latePosted==1)
lateOwner=true; latePosted[1]()
assert(lateEvents==2 and parentResults==0 and executor.getTaskSnapshot(lateParent.taskId)==nil)
check('late child file events preserve full parent identity after eviction and marshal independently',true)
print("ALL-PASS")
