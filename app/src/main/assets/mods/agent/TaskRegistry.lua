-- Owner/main-thread only. Workers must return values to the owner, never mutate
-- these records. queued/running describe dispatch, settled means a real result
-- arrived; unknown means cancellation ended waiting without confirming execution.
local M = {}
local sequence = 0
local function copy(value)
  if type(value) ~= 'table' then return value end
  local out = {}; for k,v in pairs(value) do out[k] = copy(v) end; return out
end
local function scalar(v)
  -- Identity values are used for routing/cancellation, not just display. Never
  -- truncate them; a logging sink may shorten its own detached presentation.
  if type(v)=='string' then return v end
  if type(v)=='number' or type(v)=='boolean' then return v end
end
function M.new(options)
  local cfg, records, history, order = options or {}, {}, {}, {}
  local api = {}
  local function now()
    if cfg.clockMillis then local ok,value=pcall(cfg.clockMillis); if ok and type(value)=='number' then return value end end
    return os.time()*1000
  end
  local function limit(value) return math.max(0,math.floor(tonumber(value) or 128)) end
  function api.configure(value) cfg = value or {} end
  function api.snapshot(id)
    local r=records[id]; if not r then return nil end
    local s=copy(r); s.elapsedMs=math.max(0,(r.finishedAt or now())-r.createdAt); return s
  end
  local function diagnostic(r,event)
    if cfg.onDiagnostic then
      local info=api.snapshot(r.taskId); info.event=event
      pcall(cfg.onDiagnostic,info)
    end
  end
  function api.create(name, options, fileMutation)
    options=options or {}; sequence=sequence+1
    local prefix='task'
    if cfg.idFactory then local ok,v=pcall(cfg.idFactory); if ok then prefix=tostring(scalar(v) or prefix) end end
    local id=prefix..'-'..sequence
    local scope={}; for _,k in ipairs({'projectPath','conversationId','generation'}) do scope[k]=scalar((options.scope or {})[k]) end
    records[id]={taskId=id,name=scalar(name),scope=scope,parentId=scalar(options.parentId),toolCallId=scalar(options.toolCallId),
      fileMutation=fileMutation==true,cancelPolicy=fileMutation and 'cooperative' or 'best_effort',
      waitState='waiting',executionState='queued',createdAt=now()}
    order[#order+1]=id; diagnostic(records[id],'created'); return id
  end
  function api.running(id)
    local r=records[id]; if r and r.executionState=='queued' then r.executionState='running'; r.startedAt=now() end
  end
  function api.transaction(id, transactionId)
    local r=records[id]; if r then r.transactionId=scalar(transactionId) end
  end
  function api.endWait(id,state,reason)
    local r=records[id]; if not r or r.waitState~='waiting' then return false end
    r.waitState=state; r.waitEndedAt=now()
    -- Reasons are enum-like diagnostics, never exception text or user payloads.
    local allowed={cancelled=true,user=true,scope=true,timeout=true,superseded=true,shutdown=true}
    r.cancelReason=allowed[reason] and reason or (state=='timed_out' and 'timeout' or 'cancelled')
    if not r.fileMutation then r.executionState='unknown' end
    diagnostic(r,'wait_ended'); return true
  end
  function api.retire(id)
    if not records[id] or history[id] then return end
    history[id]=true
    local count=0; for _ in pairs(history) do count=count+1 end
    local historyLimit=math.max(1,limit(cfg.historyLimit))
    for i=#order,1,-1 do if not records[order[i]] then table.remove(order,i) end end
    while count>historyLimit do
      for i,key in ipairs(order) do
        if history[key] then records[key]=nil; history[key]=nil; table.remove(order,i); count=count-1; break end
      end
    end
  end
  function api.settle(id,ok)
    local r=records[id]; if not r or r.executionState=='settled' then return false end
    r.executionState='settled'; r.finishedAt=now()
    if type(ok)=='boolean' then r.ok=ok else r.ok=nil end
    if r.waitState=='waiting' then r.waitState='completed'; r.waitEndedAt=r.finishedAt end
    diagnostic(r,'settled'); api.retire(id); return true
  end
  function api.diagnostics()
    local out={}; local diagnosticLimit=limit(cfg.diagnosticLimit)
    for i=math.max(1,#order-diagnosticLimit+1),#order do out[#out+1]=api.snapshot(order[i]) end
    return out
  end
  return api
end
return M
