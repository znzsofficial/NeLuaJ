package.path=(ASSETS or 'app/src/main/assets/')..'?.lua;'..package.path
local Facade=require('mods.files.ExternalFileFacade')
local function check(n,v) assert(v,n); print('PASS '..n) end
local lock,seq,writes,valid,acks=nil,0,0,true,0
local disk={['/p/a']={kind='file',version='v1',text='hello'}}
local reservations,results={},{}
local last
local function fingerprint(v)
  if type(v)~='table' then return type(v)..':'..tostring(v) end
  local keys,out={},{}
  for k in pairs(v) do keys[#keys+1]=k end
  table.sort(keys)
  for _,k in ipairs(keys) do out[#out+1]=k..'='..fingerprint(v[k]) end
  return table.concat(out,'|')
end
local backend={
  tryAcquire=function() if lock then return '' end; lock='token'; return lock end,
  release=function(t) assert(t==lock); lock=nil end,
  observe=function(p) return disk[p] or {kind='missing',version='missing'} end,
  recover=function() local all={}; for _,r in pairs(results) do all[#all+1]=r end; return {recovered=true,results=all} end,
  listResults=function() local all={}; for _,r in pairs(results) do all[#all+1]=r end; return all end,
  beginExternal=function(t,dir,scope,id,request)
    assert(t==lock and dir=='/storage' and scope=='/p')
    local old=reservations[id]
    if old then
      if old.digest~=fingerprint(request) then return {error={code='REQUEST_ID_REUSED',message='reused'}} end
      return {transactionId=old.tx,result=results[old.tx]}
    end
    seq=seq+1; local tx='ext-'..seq
    reservations[id]={tx=tx,digest=fingerprint(request)}
    return {transactionId=tx}
  end,
  finishExternal=function(t,_,id,r)
    assert(t==lock and r.scopeId=='/p' and reservations[id].tx==r.transactionId)
    if not results[r.transactionId] then assert(r.outcome=='rejected' and r.commitState=='REJECTED') end
    results[r.transactionId]=results[r.transactionId] or r
    return results[r.transactionId]
  end,
  execute=function(t,_,r)
    assert(t==lock); writes=writes+1; last=r
    local result={transactionId=r.transactionId,scopeId=r.scopeId,outcome='committed',commitState='COMMITTED',changes={{path=r.operation.path}}}
    results[r.transactionId]=result
    return result
  end,
  getResult=function(_,id) return results[id] end,
  peek=function() return {id='head',operation={kind='write',path='/p/a'},scopeId='/p'} end,
  historyExternal=function(t,_,scope,direction,head,tx)
    assert(t==lock and scope=='/p' and head=='head' and direction=='undo')
    writes=writes+1
    local r={transactionId=tx,scopeId=scope,outcome='committed',commitState='COMMITTED',changes={}}
    results[tx]=r; return r
  end,
}
local options={scope={scopePath='/p'},storageDir='/storage',backend=backend,
  json={encode=function(v) return v end,decode=function(v) return v end},
  resolve=function(p) if p=='link' then error('symlink outside root') end; return '/p/'..p end,
  authorized=function() return valid end,
  validate=function(p,c) if c=='broken' then return 'syntax error' end end,
  acknowledge=function() acks=acks+1; return true end,
}
local f=Facade.new(options)
check('recover fixed storage',f.recover().recovered)
options.scope.scopePath='/other'
local r=f.execute('append_file',{requestId='a',path='a',content='!',expectedVersion='v1'})
check('fixed scope and native token',r.outcome=='committed' and last.operation.content=='hello!' and last.scopeId=='/p' and not lock)
check('headless does not acknowledge',acks==0)
local same=f.execute('append_file',{requestId='a',path='a',content='!',expectedVersion='v1'})
check('in-process retry reuses pending notification',same.transactionId==r.transactionId and writes==1)
options.scope.scopePath='/p'; local retry=Facade.new(options); retry.recover()
local again=retry.execute('append_file',{requestId='a',path='a',content='!',expectedVersion='v1'})
check('persistent retry does not append twice',again.transactionId==r.transactionId and writes==1)
local bad=retry.execute('append_file',{requestId='a',path='a',content='?',expectedVersion='v1'})
check('request content mismatch rejected',bad.error.code=='REQUEST_ID_REUSED' and writes==1)
bad=f.execute('append_file',{requestId='stale',path='a',content='!',expectedVersion='old'})
check('client version enforced',bad.error.code=='version_conflict' and writes==1)
bad=f.execute('create_file',{requestId='exists',path='a',content='replacement'})
check('create never overwrites',bad.error.code=='already_exists' and writes==1)
bad=f.execute('rename_file',{requestId='rename',path='a',new_path='b',expectedVersion='v1',expectedTargetVersion='wrong'})
check('rename target version enforced',bad.error.code=='target_version_conflict')
bad=f.execute('undo',{requestId='history-stale',expectedHead='old'})
check('history head enforced',bad.error.code=='history_conflict')
local undo=f.execute('undo',{requestId='history',expectedHead='head'})
check('history uses reserved transaction',undo.outcome=='committed' and writes==2)
for _,path in ipairs({'../a','/p/a','a/../b','a\\b','link'}) do
  bad=f.execute('create_file',{requestId=path,path=path,content='x'})
  check('reject unsafe path '..path,bad.outcome=='rejected' and writes==2)
end
bad=f.execute('create_file',{requestId='syntax',path='b.lua',content='broken'})
check('injected syntax guard enforced',bad.outcome=='rejected' and writes==2)
valid=false
bad=f.execute('create_file',{requestId='revoked',path='b',content='x'})
check('revoked authorization rejected',bad.error.code=='scope_stale' and not f.recover().recovered and writes==2)
valid=true
local finished=0
local previousAcks=acks
f.attachEditor({prepareRecovery=function() return {} end,finish=function() finished=finished+1; return true end})
f.reconcile()
check('headless effects reconcile after attaching editor',finished==2 and acks==previousAcks+2)
local cancelled=false
local cancelConfig={}
for k,v in pairs(options) do cancelConfig[k]=v end
cancelConfig.authorized=function() return valid and not cancelled end
cancelConfig.notificationAuthorized=function() return valid end
local cancelFinishes=0
cancelConfig.prepare=function(_,_,token) assert(token==lock); return {} end
cancelConfig.finish=function() assert(not lock); cancelFinishes=cancelFinishes+1; return true end
local cancelling=Facade.new(cancelConfig)
cancelling.recover()
local executeNative=backend.execute
backend.execute=function(...)
  local result=executeNative(...)
  cancelled=true -- Request cancelled while publication was already in progress.
  return result
end
local committed=cancelling.execute('append_file',{requestId='cancel-during-commit',path='a',content='!',expectedVersion='v1'})
check('cancel during commit still finishes editor sync',committed.outcome=='committed' and cancelFinishes==1)
backend.execute=executeNative
cancelled=false
local beforeHistory=writes
cancelling.attachEditor({prepare=function() cancelled=true; return {} end,finish=cancelConfig.finish})
local cancelledHistory=cancelling.execute('undo',{requestId='cancel-before-history',expectedHead='head'})
check('cancel before history publication prevents execution',cancelledHistory.outcome=='rejected' and cancelledHistory.error.code=='scope_stale' and writes==beforeHistory and not lock)
cancelled=false
cancelling.attachEditor({prepare=function() error('prepare interrupted') end,finish=cancelConfig.finish})
local failedHistory=cancelling.execute('undo',{requestId='failed-history-prepare',expectedHead='head'})
check('history preparation error prevents execution',failedHistory.error.code=='prepare_failed' and writes==beforeHistory and not lock)
check('no chat modules loaded',not package.loaded['mods.project.ProjectContext'] and not package.loaded['mods.agent.AgentStorage'])
print('ALL-PASS TestExternalFileFacade')
