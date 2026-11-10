local assets=ASSETS or 'app/src/main/assets/'
package.path=assets..'?.lua;'..package.path
local Service=require('mods.files.FileMutationService')
local Registry=require('mods.agent.ToolRegistry')
local function check(name,value) assert(value,name); print('PASS '..name) end
local queue,lock,epoch,writes,finished,callbacks={},nil,1,0,0,0
local observed={path='/p/a',kind='file',version='v1',text='hello'}
local resultStore={}
local capturedRequest
local service
local backend={
  tryAcquire=function(id) if lock then return '' end; lock=id; return id end,
  release=function(token) assert(lock==token); lock=nil end,
  observe=function(path) local o={}; for k,v in pairs(observed) do o[k]=v end; o.path=path; return o end,
  recover=function() return {recovered=true,results={}} end,
  execute=function(token,dir,request)
    assert(token==lock and dir=='/store/p')
    capturedRequest=request; writes=writes+1
    local r={transactionId=request.transactionId,scopeId=request.scopeId,outcome='committed',changes={},history={recorded=true,persisted=true}}
    resultStore[r.transactionId]=r
    return r
  end,
  peek=function() return {id='head',scopeId='/p',operation={kind='rename',path='/p/a',target='/p/b'}} end,
  history=function(token,dir,scope,direction,id)
    assert(token==lock and dir=='/store/p' and scope=='/p' and id=='head')
    return {transactionId='history',outcome='committed',changes={}}
  end,
  getResult=function(_,id) return resultStore[id] end,
}
service=Service.new({
  backend=backend,json={encode=function(x) return x end},
  context={snapshot=function() return {scopePath='/p',directory='/p',projectGeneration=epoch} end},
  storage=function() return '/store/p' end,
  scheduler=function(work,done) queue[#queue+1]={work=work,done=done} end,
  prepare=function(_,_,token) assert(token==lock); return {document='doc'} end,
  finish=function(_,_,_,result) assert(not lock); finished=finished+1; return true end,
})
local _,ok,r=service.execute('create_file',{path='a',content='x'})
check('new operations blocked until recovery',not ok and r.error.code=='recovery_required' and lock==nil)
check('recover',service.recover().recovered)
for _,name in ipairs({'create_file','create_folder','delete_file','delete_folder','apply_patch','replace_in_file','append_file','rename_file'}) do
  check('registry classification '..name,Registry.get(name).fileMutation~=nil)
end
local h=service.submit('append_file',{path='a',content='!'},function(_,success,result)
  callbacks=callbacks+1; assert(success and result.outcome=='committed')
end)
_,ok,r=service.execute('create_file',{path='a',content='bad'})
check('sync cannot bypass async lock',not ok and r.error.code=='busy')
queue[1].work()
check('worker releases before UI callback',lock==nil and callbacks==0)
check('candidate built from observed text and version',capturedRequest.operation.content=='hello!' and capturedRequest.expected[1].version=='v1')
check('result query before callback',service.getResult(h.id).outcome=='committed')
service.drainNotifications(); queue[1].done(); queue[1].done()
check('callback once after drain and late callbacks',callbacks==1)
local before=writes
local c=service.submit('create_file',{path='a',content='cancel'})
service.cancel(c); queue[2].work(); queue[2].done()
check('cancel before publication',writes==before and c.result.error.code=='cancelled')
local stale=service.submit('create_file',{path='a',content='stale'})
epoch=epoch+2 -- A -> B -> A still has a new project epoch.
queue[3].work(); queue[3].done()
check('scope ABA rejected',writes==before and stale.result.error.code=='scope_stale')
local late=service.submit('create_file',{path='a',content='late'})
queue[4].work(); service.cancel(late); queue[4].done()
check('cancel after publication preserves commit',late.result.outcome=='committed' and writes==before+1)
_,ok,r=service.undo()
check('history goes through service',ok and r.transactionId=='history' and lock==nil)
_,ok,r=service.execute('delete_folder',{path='/p'})
check('root deletion rejected',not ok and lock==nil)
_,ok,r=service.execute('read_file',{path='a'})
check('nonmutation rejected',not ok)
local old=backend.execute
backend.execute=function() error('lost native response') end
_,ok,r=service.execute('create_file',{path='a',content='x'})
check('unknown publication requires recovery',not ok and r.commitState=='unknown' and lock==nil)
backend.execute=old
_,ok,r=service.execute('create_file',{path='a',content='x'})
check('unknown state blocks later writes',not ok and r.error.code=='recovery_required')
service.reconcilePending()
check('resume schedules instead of doing recovery inline',#queue==5)
queue[5].work(); queue[5].done()
_,ok=service.execute('create_file',{path='a',content='x'})
check('recovery allows new transactions',ok)
local singleton=require('mods.files.FileMutationService')
local originalExecute,originalSubmit=singleton.execute,singleton.submit
local routed=0
singleton.execute=function(name,args) routed=routed+1; return 'routed',false,{outcome='rejected'} end
singleton.submit=function(name,args,callback) routed=routed+1; callback('routed',false,{outcome='rejected'}); return {result={}} end
local executor=require('mods.agent.ToolExecutor')
executor.configure({platformExecute=function() error('legacy file handler must never execute') end,
  scheduleTimeout=function() return function() end end})
local text,flag,effects=executor.executeTool('write_file',{path='a'})
check('sync aliases route through sole mutation service with third result',text=='routed' and flag==false and effects.outcome=='rejected')
executor.executeToolAsync('append',{path='a'},function(t,success,result)
  check('async third result preserves false',t=='routed' and success==false and result.outcome=='rejected')
end)
check('both executor paths use service',routed==2)
singleton.execute,singleton.submit=originalExecute,originalSubmit
local warnService
local failSync=true
local warningCallback=0
local common={backend=backend,json={encode=function(x) return x end},
  context={snapshot=function() return {scopePath='/p',directory='/p',projectGeneration=epoch} end},
  storage=function() return '/store/p' end,
  prepare=function(_,_,token) assert(token==lock); return {} end,
  finish=function(_,_,_,result)
    if failSync then return false,'widget absent' end
    result.warnings[#result.warnings+1]='draft preserved'
    return true
  end,
  scheduler=function(work,done) queue[#queue+1]={work=work,done=done} end,
}
warnService=Service.new(common); warnService.recover()
local warningJob=warnService.submit('create_file',{path='a',content='x'},function(_,success,result)
  warningCallback=warningCallback+1
  assert(success and result.warnings[1]:find('widget absent',1,true))
  error('listener failure must not change commit')
end)
queue[6].work(); queue[6].done()
check('failed sync and listener preserve commit',warningJob.result.outcome=='committed' and warningCallback==1 and not lock)
failSync=false; warnService.drainNotifications()
check('pending sync retries without duplicate callback and retains warning',warningCallback==1 and warnService.getResult(warningJob.id).warnings[2]=='draft preserved')
common.prepare=function() error('unsaved draft cannot persist') end
local rejected=Service.new(common); rejected.recover()
_,ok,r=rejected.execute('create_file',{path='a',content='x'})
check('prepare failure releases native token',not ok and r.error.code=='prepare_failed' and not lock)
common.prepare=function() return {} end
common.scheduler=function() error('scheduler unavailable') end
local launch=Service.new(common); launch.recover()
local launchJob=launch.submit('create_file',{path='a',content='x'})
check('launch failure releases native token',launchJob.result.error.code=='launch_failed' and not lock)
local replayQueue,acknowledged={},{}
local mainThread=true
local recoveryCaptures,recoveryFinishes,prepares=0,0,0
local captureAvailable=false
local persisted={transactionId='restart-tx',scopeId='/p',outcome='committed',commitState='COMMITTED',changes={{path='/p/a'}},warnings={'durability warning'}}
local replayConfig={backend=backend,json={encode=function(x) return x end},
  context={snapshot=function() return {scopePath='/p',directory='/p',projectGeneration=epoch} end},
  storage=function() return '/store/p' end,
  isMainThread=function() return mainThread end,
  loadResults=function() assert(not mainThread); return {persisted} end,
  isAcknowledged=function(_,id) assert(not mainThread); return acknowledged[id] end,
  acknowledge=function(_,id) assert(not mainThread); acknowledged[id]=true; return true end,
  prepare=function() prepares=prepares+1; return {} end,
  prepareRecovery=function(result)
    assert(mainThread and result.transactionId=='restart-tx')
    recoveryCaptures=recoveryCaptures+1
    if not captureAvailable then return nil,'activity not ready' end
    return {fresh=true}
  end,
  finish=function(snapshot,_,_,result)
    assert(mainThread and snapshot.fresh and result==persisted)
    recoveryFinishes=recoveryFinishes+1
    return true
  end,
  scheduler=function(work,done) replayQueue[#replayQueue+1]={work=work,done=done} end,
}
local function replayRun(index)
  mainThread=false; local value=replayQueue[index].work(); mainThread=true; replayQueue[index].done(value)
end
local restored=Service.new(replayConfig)
restored.reconcilePending()
check('resume does not touch UI or backend synchronously',recoveryCaptures==0 and #replayQueue==1)
replayRun(1)
check('restart replay waits for Activity capture without saving buffer',recoveryCaptures==1 and recoveryFinishes==0 and prepares==0 and not acknowledged['restart-tx'])
captureAvailable=true; restored.drainNotifications()
check('pending restart replay finishes on main with fresh snapshot',recoveryFinishes==1 and prepares==0)
replayRun(2)
restored.reconcilePending(); replayRun(3)
check('acknowledged replay is idempotent within process',recoveryFinishes==1)
local restartedAgain=Service.new(replayConfig)
restartedAgain.reconcilePending(); replayRun(4)
check('persistent ack makes restart replay idempotent',recoveryFinishes==1)
mainThread=false
local threadText,threadOk,threadResult=restored.execute('create_file',{path='a'})
check('background sync execute rejects before preparation',not threadOk and threadResult.error.code=='main_thread_required' and prepares==0)
mainThread=true
local detail=restored.formatResult({transactionId='t-detail',outcome='partial',error={code='IO_ERROR',message='disk failed'},warnings={'retry after recovery'}})
check('formatted result includes transaction, code, warnings',detail:find('t-detail',1,true) and detail:find('IO_ERROR',1,true) and detail:find('retry after recovery',1,true))
local legacy=require('mods.agent.ChangeSet')
local legacyReport=legacy.inspectLegacy('invalid','changesets.json','/p',{decode=function() error('bad JSON') end})
check('legacy corrupt history remains explicitly read-only and unimported',legacyReport.readOnly and not legacyReport.imported and not legacyReport.valid and legacyReport.validationError)
legacyReport=legacy.inspectLegacy('empty','changesets.json','/p',{decode=function() return {undo={},redo={}} end})
check('legacy valid structure has explicit nonmigration reason',legacyReport.valid and legacyReport.count==0 and legacyReport.reason and not legacyReport.imported)
local legacyFixture={id='legacy',name='create_file',scope='/p',args={path='/p/a'},
  before={{path='/p/a',kind='missing',fingerprint='missing'}},
  after={{path='/p/a',kind='file',content='a',fingerprint='1:97'}}}
local legacyCodec={decode=function() return {undo={legacyFixture},redo={}} end}
legacyReport=legacy.inspectLegacy('fixture','changesets.json','/p',legacyCodec)
check('legacy file fingerprint validated without importing',legacyReport.valid and legacyReport.entries[1].scopeMatches and not legacyReport.imported)
legacyFixture.after[1].content='tampered'
legacyReport=legacy.inspectLegacy('fixture','changesets.json','/p',legacyCodec)
check('legacy corrupt snapshot surfaced, not discarded or executable',not legacyReport.valid and #legacyReport.entries==1 and not legacyReport.entries[1].valid)
-- The production scheduler must not enqueue into an Activity-owned xTask scope.
local oldJava, oldTask = luajava, xTask
local processQueue = {}
xTask = function() error('Activity task must not own file transaction') end
luajava = {bindClass=function(name)
  assert(name=='com.nekolaska.io.FileMutationDispatcher')
  return {submit=function(work,done) processQueue[#processQueue+1]={work=work,done=done} end}
end}
local processService=Service.new({backend=backend,json={encode=function(x) return x end},
  context={snapshot=function() return {scopePath='/p',directory='/p',projectGeneration=epoch} end},
  storage=function() return '/store/p' end})
processService.recover()
local queued=processService.submit('replace_in_file',{path='a',old=' hello ',new='hello'})
check('default scheduler retains a process job',#processQueue==1 and lock~=nil)
processQueue[1].work()
check('fuzzy replacement settles and releases without UI callback',queued.result.outcome=='committed' and not lock)
local gone=processService.submit('append_file',{path='a',content='!'})
epoch=epoch+1 -- navigation/destruction before the process worker starts
processQueue[2].work()
check('stale queued process worker still settles and releases',gone.result.error.code=='scope_stale' and not lock)
local cancelledJob=processService.submit('append_file',{path='a',content='!'})
processService.cancel(cancelledJob)
processQueue[3].work()
check('queued cancellation still runs cleanup',cancelledJob.result.error.code=='cancelled' and not lock)
luajava,xTask=oldJava,oldTask
print('ALL-PASS TestFileMutationService')
