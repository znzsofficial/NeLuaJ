-- One transaction boundary for tools, history and editor reconciliation.
-- Dependencies are lazy so the protocol can be tested without Android.
local Registry = require('mods.agent.ToolRegistry')
local Patch = require('mods.agent.PatchEngine')
local function new(options)
  local cfg = options or {}
  local api, pending, results, ready = {}, {}, {}, {}
  local sequence = 0
  local replayed, legacyReports = {}, {}
  local function schedule(work,done)
    if cfg.scheduler then return cfg.scheduler(work,done) end
    if cfg.fixedScope then local value=work(); return done(value) end
    return luajava.bindClass('com.nekolaska.io.FileMutationDispatcher').submit(work,done)
  end
  local function onMain()
    if not cfg.isMainThread then return true end
    local ok,value=pcall(cfg.isMainThread)
    return ok and value==true
  end
  local function backend() return cfg.backend or luajava.kotlinObject('com.nekolaska.io.FileMutationEngine') end
  local function decode(value)
    if type(value) == 'table' then return value end
    if value == nil or tostring(value) == 'null' then return nil end
    return (cfg.json or json).decode(tostring(value))
  end
  local function call(method, ...) return decode(backend()[method](...)) end
  local function context()
    if cfg.fixedScope then return cfg.fixedScope end
    return (cfg.context or require('mods.project.ProjectContext')).snapshot()
  end
  local function storage(scope)
    if cfg.fixedScope then return assert(cfg.storageDir, 'fixed scope requires storageDir') end
    return cfg.storage and cfg.storage(scope) or require('mods.agent.AgentStorage').capture(scope.scopePath, scope.agentRoot).storageDir
  end
  local function failure(h, code, message)
    return {transactionId=h.id, scopeId=h.scope.scopePath, outcome='rejected', commitState=cfg.fixedScope and 'REJECTED' or 'not_committed', changes={},
      history={recorded=false,persisted=false}, warnings={}, error={code=code,message=tostring(message)}}
  end
  local function formatted(r)
    local ok = r.outcome == 'committed' or r.outcome == 'unchanged'
    local text = ok and ('文件操作' .. (r.outcome == 'committed' and '已提交' or '无变化')) or
      ('文件操作失败: ' .. tostring(r.error and r.error.message or r.outcome))
    if r.transactionId then text=text..'\n事务: '..tostring(r.transactionId) end
    if r.error and r.error.code then text=text..'\n错误代码: '..tostring(r.error.code) end
    for _,warning in ipairs(r.warnings or {}) do text=text..'\n警告: '..tostring(warning) end
    return text, ok, r
  end
  local function current(h)
    if cfg.fixedScope then return cfg.authorized and cfg.authorized(h.scope)==true end
    local c = context()
    return c.scopePath == h.scope.scopePath and c.projectGeneration == h.scope.projectGeneration
  end
  local function notificationCurrent(h)
    -- Request cancellation stops publication, not synchronization of an
    -- already committed result. Actual scope revocation still defers replay.
    if cfg.fixedScope and cfg.notificationAuthorized then return cfg.notificationAuthorized(h.scope)==true end
    return current(h)
  end
  local function notify(h)
    if not h.result then return end
    if not onMain() then return end
    local function deliver()
      if not h.notified then
        h.notified=true
        if h.callback then pcall(h.callback,formatted(h.result)) end
      end
    end
    if h.suppressNotification then
      -- A deduplicated external retry must drive the original pending sync,
      -- after releasing its own token, without publishing the file twice.
      if h.replayPending then
        notify(h.replayPending)
        h.result=h.replayPending.result
        results[h.id]={result=h.result,storageDir=h.storageDir}
      end
      deliver(); return
    end
    local changed=h.result.outcome=='committed' or h.result.outcome=='partial'
    -- A headless external host must not acknowledge effects it never showed.
    if cfg.fixedScope and changed and (not cfg.finish or not notificationCurrent(h)) then deliver(); return end
    if changed and not notificationCurrent(h) then
      local now=context()
      if now.scopePath~=h.scope.scopePath then deliver(); return end
      h.scope=now; h.snapshot=nil; h.recovery=true
    end
    if changed and not h.snapshot and (cfg.prepare or cfg.fixedScope) then h.recovery=true end
    if h.recovery and not h.snapshot then
      if not notificationCurrent(h) then deliver(); return end
      if not cfg.prepareRecovery then deliver(); return end
      local ok,snapshot,err=pcall(cfg.prepareRecovery,h.result)
      if not ok or not snapshot then
        h.result.warnings=h.result.warnings or {}
        if not h.captureWarning then h.result.warnings[#h.result.warnings+1]='恢复同步等待编辑器: '..tostring(ok and err or snapshot); h.captureWarning=true end
        deliver(); return
      end
      h.snapshot=snapshot
    end
    if not h.synced then
      local finish = cfg.finish
      local ok, synced, err = true, true, nil
      if changed and finish and h.snapshot then ok, synced, err = pcall(finish, h.snapshot, h.editorName or h.name, h.args, h.result) end
      h.synced = ok and synced ~= false
      if h.result.commitState=='unknown' or h.result.outcome=='partial' then h.synced=false end
      if cfg.fixedScope and not h.synced then
        -- Opaque editor snapshots are consumed by finish, even if its caller
        -- times out. Never retry a possibly consumed snapshot identifier.
        h.snapshot=nil; h.recovery=true
      end
      if not h.synced and not h.syncWarning then
        h.syncWarning=true
        h.result.warnings=h.result.warnings or {}
        h.result.warnings[#h.result.warnings+1]='编辑器同步待重试: '..tostring(ok and err or synced)
      end
    end
    deliver()
    if h.synced then
      pending[h.id] = nil
      local id=h.result.transactionId
      if id and h.storageDir then replayed[h.storageDir..'\n'..id]=true end
      if id and h.storageDir and cfg.acknowledge and not h.ackScheduled then
        h.ackScheduled=true
        local launched=pcall(schedule,function() return cfg.acknowledge(h.storageDir,id) end,function(ok)
          if ok~=true then h.ackScheduled=false; pending[h.id]=h end
        end)
        if not launched then h.ackScheduled=false; pending[h.id]=h end
      end
    end
  end
  local function release(h)
    if h.token then
      local token = h.token
      h.token = nil
      local ok = pcall(function() backend().release(token) end)
      if not ok then ready[h.storageDir] = nil end
    end
  end
  local function settle(h, r)
    if h.externalReserved then
      local ok,saved=pcall(call,'finishExternal',h.token,h.storageDir,h.args.requestId or h.requestId,(cfg.json or json).encode(r))
      if ok and type(saved)=='table' and saved.outcome then r=saved
      else
        r=failure(h,'recovery_required',saved)
        r.outcome='partial'; r.commitState='unknown'
      end
    end
    h.result = r
    results[h.id] = {result=r,storageDir=h.storageDir}
    if r.transactionId then results[r.transactionId]=results[h.id] end
    if h.storageDir and (r.outcome=='partial' or r.commitState=='unknown'
        or (r.error and r.error.code=='RECOVERY_REQUIRED')) then ready[h.storageDir]=nil end
    release(h) -- Never rely on delivery of a UI callback to release the native lock.
    return r
  end
  function api.configure(o)
    assert(not cfg.fixedScope, 'fixed scope instances cannot be reconfigured')
    cfg = o or {}
  end
  function api.attachEditor(hooks)
    assert(cfg.fixedScope, 'attachEditor is for fixed scope instances')
    hooks=hooks or {}
    cfg.prepare,cfg.prepareRecovery,cfg.finish=hooks.prepare,hooks.prepareRecovery,hooks.finish
  end
  local function capture(name, args, callback)
    sequence = sequence + 1
    local s = context()
    local id = cfg.id and cfg.id() or (tostring(os.time()) .. '-' .. tostring({}):gsub('table: ', '') .. '-' .. sequence)
    local h = {id=id,scope=s,storageDir=storage(s),name=name,args={},callback=callback}
    for k,v in pairs(args or {}) do h.args[k]=v end
    if cfg.fixedScope then
      if type(h.args.requestId)~='string' or h.args.requestId=='' then error('requestId required') end
      for _,v in pairs(h.args) do
        if type(v)~='string' and type(v)~='number' and type(v)~='boolean' then error('external arguments must be scalar') end
      end
      h.externalRequest={name=name,args={}}
      for k,v in pairs(h.args) do h.externalRequest.args[k]=v end
    end
    local function resolve(p)
      if not p or p == '' then error('缺少文件路径') end
      if cfg.fixedScope then
        if type(p)~='string' or p:find('[%z\\:]') or p:sub(1,1)=='/' then error('external path must be relative') end
        for part in p:gmatch('[^/]+') do if part=='.' or part=='..' then error('invalid path component') end end
        local resolved=assert(cfg.resolve(p,s), 'path resolution failed')
        if resolved:sub(1,#s.scopePath+1)~=s.scopePath..'/' then error('path outside fixed scope') end
        return resolved
      end
      if cfg.resolve then return cfg.resolve(p, s) end
      return p:sub(1,1)=='/' and p or s.directory .. '/' .. p
    end
    if name ~= 'undo' and name ~= 'redo' then
      h.args.path = resolve(h.args.path)
      if h.args.new_path then h.args.new_path = resolve(h.args.new_path) end
    end
    h.cancel = function() return api.cancel(h) end
    return h
  end
  local function prepare(h)
    h.token = backend().tryAcquire(h.id)
    if h.token == nil or tostring(h.token)=='' then h.token=nil; return failure(h,'busy','另一个文件操作仍在完成') end
    if not ready[h.storageDir] then return failure(h,'recovery_required','文件历史尚未恢复，请先执行 recover') end
    if cfg.fixedScope and not current(h) then return failure(h,'scope_stale','工程授权已失效') end
    if cfg.fixedScope then
      local reservation=call('beginExternal',h.token,h.storageDir,h.scope.scopePath,h.args.requestId,(cfg.json or json).encode(h.externalRequest))
      if reservation.result then
        pending[h.id]=nil
        h.id=reservation.result.transactionId or reservation.transactionId or h.id
        if pending[h.id] or replayed[h.storageDir..'\n'..h.id] then
          h.suppressNotification=true; h.replayPending=pending[h.id]
        else pending[h.id]=h end
        return reservation.result
      end
      if reservation.error then return failure(h,reservation.error.code,reservation.error.message) end
      if not reservation.transactionId then return failure(h,'recovery_required','Invalid external reservation') end
      pending[h.id]=nil
      h.id=reservation.transactionId
      pending[h.id]=h
      h.requestId=h.args.requestId
      h.externalReserved=true
    end
    if h.name == 'undo' or h.name == 'redo' then
      h.head = call('peek',h.storageDir,h.name)
      if not h.head then return failure(h,'empty_history','没有可用的文件历史') end
      if cfg.fixedScope and h.args.expectedHead~=h.head.id then return failure(h,'history_conflict','expectedHead 与当前历史不一致') end
      local op = h.head.operation
      h.args = {path=op.path,new_path=op.target}
      h.editorName = op.kind == 'rename' and 'rename_file' or 'create_file'
      if h.name == 'undo' and op.kind == 'rename' then h.args.path,h.args.new_path=h.args.new_path,h.args.path end
    end
    if cfg.prepare then
      local snapshot, err = cfg.prepare(h.editorName or h.name,h.args,h.token)
      if snapshot == false or (snapshot == nil and err) then return failure(h,'prepare_failed',err or '编辑器准备失败') end
      h.snapshot=snapshot
    end
  end
  local function candidate(h)
    local a,n = h.args,h.name
    local entry=Registry.get(n)
    if not entry or not entry.fileMutation then error('非文件变更工具: '..tostring(n)) end
    local kind=entry.fileMutation
    local path=a.path
    local root=not cfg.fixedScope and cfg.resolve and cfg.resolve(h.scope.scopePath,h.scope) or h.scope.scopePath
    if (kind=='delete' or kind=='rename') and (path=='/' or path==root
        or root:sub(1,#path+1)==path..'/') then error('禁止删除或移动项目根目录及其上级目录') end
    local before=call('observe',path)
    if not before or not before.version then error('无法获取文件版本') end
    if cfg.fixedScope then
      if n=='create_file' or kind=='mkdir' then
        if before.kind~='missing' then error({code='already_exists',message='创建目标已经存在'}) end
      elseif type(a.expectedVersion)~='string' or a.expectedVersion~=before.version then
        error({code='version_conflict',message='expectedVersion 与当前版本不一致，请重新读取'})
      end
    end
    local op={kind=kind,path=path,target=a.new_path}
    local expected={{path=path,version=before.version}}
    if kind=='write' then
      local original=before.text
      if n=='create_file' then op.content=tostring(a.content or '')
      elseif n=='append_file' then
        if before.kind=='missing' then original='' end
        if type(original)~='string' then error('文件不是可编辑文本') end
        op.content=original..tostring(a.content or '')
      else
        if before.kind~='file' or type(original)~='string' then error('文件不存在或不是可编辑文本') end
        if n=='apply_patch' then
          local content,err=Patch.applyPatch(original,a.patch or '')
          if not content then error(err) end
          op.content=content
        else
          if not a.old or a.old=='' then error('replace_in_file 需要 old 参数') end
          local content,count=Patch.plainReplace(original,a.old,a.new or '',tonumber(a.count) or 0)
          if count==0 then
            local fuzzy,num=Patch.fuzzyLineReplace(original,a.old,a.new or '',tonumber(a.count) or 0)
            if fuzzy then content,count=fuzzy,num end
          end
          if count==0 then error('未找到要替换的文本') end
          op.content=content
        end
      end
      if cfg.validate then local err=cfg.validate(path,op.content); if err then error(err) end end
    elseif kind=='rename' then
      if not a.new_path then error('缺少 new_path 参数') end
      local target=call('observe',a.new_path)
      if cfg.fixedScope and (type(a.expectedTargetVersion)~='string' or a.expectedTargetVersion~=target.version) then
        error({code='target_version_conflict',message='expectedTargetVersion 与目标版本不一致'})
      end
      expected[#expected+1]={path=a.new_path,version=target.version}
      if cfg.validate and before.kind=='file' and a.new_path:lower():sub(-4)=='.lua' then
        if type(before.text)~='string' then error('无法检查目标 Lua 文件语法') end
        local err=cfg.validate(a.new_path,before.text); if err then error(err) end
      end
    elseif kind=='delete' then
      if n=='delete_file' and before.kind=='dir' then error('路径是文件夹，请使用 delete_folder') end
      if n=='delete_folder' and before.kind=='file' then error('路径不是文件夹') end
    end
    return {transactionId=h.id,scopeId=h.scope.scopePath,operation=op,expected=expected}
  end
  local function worker(h)
    local ok,r=pcall(function()
      if h.cancelled then return failure(h,'cancelled','操作已取消，未执行') end
      if not current(h) then return failure(h,'scope_stale','项目已切换，未执行') end
      if h.name=='undo' or h.name=='redo' then
        h.published=true
        if cfg.fixedScope then return call('historyExternal',h.token,h.storageDir,h.scope.scopePath,h.name,h.head.id,h.id) end
        return call('history',h.token,h.storageDir,h.scope.scopePath,h.name,h.head.id)
      end
      local request=candidate(h)
      if h.cancelled then return failure(h,'cancelled','操作已取消，未执行') end
      if not current(h) then return failure(h,'scope_stale','项目已切换，未执行') end
      h.published=true
      return call('execute',h.token,h.storageDir,(cfg.json or json).encode(request))
    end)
    if not ok or type(r)~='table' then
      local detail=r
      r=failure(h,h.published and 'recovery_required' or (type(detail)=='table' and detail.code or 'invalid_request'),type(detail)=='table' and detail.message or detail)
      if h.published then r.outcome='partial'; r.commitState='unknown'; ready[h.storageDir]=nil end
    end
    return settle(h,r)
  end
  local function start(name,args,callback,async)
    if not cfg.fixedScope and not onMain() then
      local h={id='thread-rejected',scope={scopePath=''},name=name,args=args or {}}
      h.result=failure(h,'main_thread_required','文件变更入口必须由主线程发起；后台同步调用已拒绝')
      if callback then pcall(callback,formatted(h.result)) end
      return h
    end
    local captured,h=pcall(capture,name,args,callback)
    if not captured then
      local reason=tostring(h)
      h={id='invalid-'..sequence,scope={scopePath=''},name=name,args=args or {},callback=callback}
      settle(h,failure(h,'invalid_request','路径或存储解析失败: '..reason))
      notify(h)
      return h
    end
    pending[h.id]=h
    local ok,err=pcall(prepare,h)
    if not ok then err=failure(h,'prepare_failed',err) end
    if err then settle(h,err); notify(h); return h end
    if async then
      local launched,launchError=pcall(schedule,function() return worker(h) end,function() notify(h) end)
      if not launched then settle(h,failure(h,'launch_failed',launchError)); notify(h) end
    else worker(h); notify(h) end
    return h
  end
  function api.submit(name,args,callback) return start(name,args,callback,true) end
  function api.execute(name,args) local h=start(name,args,nil,false); return formatted(h.result) end
  function api.undo(callback) if callback then return api.submit('undo',{},callback) end; return api.execute('undo',{}) end
  function api.redo(callback) if callback then return api.submit('redo',{},callback) end; return api.execute('redo',{}) end
  function api.cancel(h)
    if type(h)=='string' then h=pending[h] end
    if not h or h.result then return false end
    h.cancelled=true; return true
  end
  function api.getResult(id,storageDir)
    if cfg.fixedScope then
      assert(not storageDir, 'fixed scope results cannot be redirected')
      if not current({scope=cfg.fixedScope}) then return nil end
    end
    if results[id] then return results[id].result end
    return call('getResult',storageDir or storage(context()),id)
  end
  function api.formatResult(result) return formatted(result) end
  function api.getLegacyHistory(scopePath) return legacyReports[scopePath or context().scopePath] end
  function api.peek(direction) return call('peek',storage(context()),direction) end
  function api.hasUndo() return api.peek('undo')~=nil end
  function api.hasRedo() return api.peek('redo')~=nil end
  function api.drainNotifications()
    local batch={}
    for _,h in pairs(pending) do batch[#batch+1]=h end
    table.sort(batch,function(a,b)
      if (a.replayOrder or math.huge)~=(b.replayOrder or math.huge) then return (a.replayOrder or math.huge)<(b.replayOrder or math.huge) end
      return tostring(a.id)<tostring(b.id)
    end)
    for _,h in ipairs(batch) do notify(h) end
  end
  function api.recover(capturedScope, capturedStorage)
    if cfg.fixedScope then
      assert(not capturedScope and not capturedStorage, 'fixed scope recovery cannot be redirected')
      if not current({scope=cfg.fixedScope}) then return {recovered=false,error={code='scope_stale'}} end
    end
    local s=capturedScope or context(); local dir=capturedStorage or storage(s)
    local token=backend().tryAcquire('recover-'..tostring(os.time()))
    if not token or tostring(token)=='' then return {ok=false,error={code='busy'}} end
    ready[dir]=nil
    local ok,r=pcall(function()
      local migration
      if cfg.migrateLegacy then migration=cfg.migrateLegacy(token,dir,s) end
      local report=call('recover',token,dir,s.scopePath)
      if migration then report.legacyMigration=migration end
      return report
    end)
    pcall(function() backend().release(token) end)
    if not ok or type(r)~='table' then return {ok=false,error={code='recovery_required',message=tostring(r)}} end
    if cfg.loadResults then
      local loaded,all=pcall(cfg.loadResults,dir,s.scopePath)
      if not loaded or type(all)~='table' then
        ready[dir]=nil
        return {recovered=false,error={code='replay_load_failed',message=tostring(all)}}
      end
      r.results=all
    end
    for order,result in ipairs(r.results or {}) do
      local id=result.transactionId
      local old=id and results[id]
      local live=id and pending[id]
      if id and not live then
        for _,handle in pairs(pending) do
          if handle.result and handle.result.transactionId==id then live=handle; break end
        end
      end
      if id and (not old or old.result.outcome=='partial') then
        if old and old.result.warnings then
          result.warnings=result.warnings or {}
          for _,warning in ipairs(old.result.warnings) do result.warnings[#result.warnings+1]=warning end
        end
        results[id]={result=result,storageDir=dir}
        if live then live.result=result; live.synced=false; results[live.id]=results[id] end
      end
      if id and not live and not replayed[dir..'\n'..id]
          and (result.outcome=='committed' or result.outcome=='partial')
          and not (cfg.isAcknowledged and cfg.isAcknowledged(dir,id)) then
        pending[id]={id=id,result=result,storageDir=dir,scope=s,name='recovery',args={},recovery=true,replayOrder=order}
      end
    end
    if cfg.legacyHistory then
      local report=cfg.legacyHistory(s)
      if report then
        legacyReports[s.scopePath]=report
        r.legacyHistory=report
        if r.legacyMigration then
          report.imported=r.legacyMigration.imported==true
          report.migration=r.legacyMigration
          report.reason=report.imported and '已验证导入；旧源保留作为备份' or tostring(r.legacyMigration.error and r.legacyMigration.error.message or '旧历史无法安全导入，已隔离保留')
        end
        if not report.imported then
          r.warnings=r.warnings or {}; r.warnings[#r.warnings+1]='旧历史未导入: '..tostring(report.reason)
        end
      end
    end
    if type(r)=='table' and r.recovered==true and not r.error then ready[dir]=true end
    return r
  end
  function api.reconcile(callback) return api.reconcilePending(callback) end
  function api.reconcilePending(callback)
    local scope=context()
    local dir=storage(scope)
    return schedule(function() if cfg.fixedScope then return api.recover() end; return api.recover(scope,dir) end, function(report)
      api.drainNotifications()
      if callback then pcall(callback,report) end
    end)
  end
  return api
end
local service=new()
service.new=new
return service
