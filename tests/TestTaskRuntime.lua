local assets=ASSETS or 'app/src/main/assets/'
local queued,removed,logs={}, {}, {}
local owner=true
local main={isCurrentThread=function() return owner end}
local accept=true
local handler={
  postDelayed=function(r,ms) queued[#queued+1]={r=r,ms=ms}; return accept end,
  post=function(r) queued[#queued+1]={r=r}; return accept end,
  removeCallbacks=function(r) removed[#removed+1]=r end,
}
luajava={bindClass=function(name)
  if name=='android.os.Looper' then return {getMainLooper=function() return main end} end
  if name=='android.os.SystemClock' then return {uptimeMillis=function() return 1234 end} end
  if name=='java.util.UUID' then return {randomUUID=function() return 'unique-task' end} end
  if name=='android.util.Log' then return {d=function(_,message) logs[#logs+1]=message end} end
  if name=='android.os.Handler' then return function(l) assert(l==main); return handler end end
  error(name)
end,createProxy=function(name,methods) assert(name=='java.lang.Runnable'); return methods end}
local runtime=assert(loadfile(assets..'mods/agent/TaskRuntime.lua'))()
assert(runtime.clockMillis()==1234 and runtime.idFactory()=='unique-task' and runtime.isOwnerThread())
local called=0
local cancel=runtime.scheduleTimeout(20,function() called=called+1 end)
cancel(); cancel(); queued[1].r.run()
assert(called==0 and #removed==1 and removed[1]==queued[1].r)
runtime.scheduleTimeout(30,function() called=called+1 end)
queued[2].r.run(); queued[2].r.run()
assert(called==1 and queued[2].ms==30)
owner=false
runtime.postToOwner(function() called=called+1 end)
assert(called==1)
queued[3].r.run(); assert(called==2)
owner=true; runtime.postToOwner(function() called=called+1 end); assert(called==3)
runtime.onDiagnostic({taskId='id\n1',name='read_file',waitState='timed_out',args='SECRET',text='SECRET',headers='SECRET',scope='/private/path'})
assert(logs[1]:find('id 1',1,true) and not logs[1]:find('SECRET',1,true) and not logs[1]:find('/private/path',1,true))
accept=false
assert(not pcall(runtime.scheduleTimeout,10,function() end))
owner=false; assert(not pcall(runtime.postToOwner,function() end))
print('ALL-PASS task timer identity, cancellation, owner dispatch and diagnostic redaction')
