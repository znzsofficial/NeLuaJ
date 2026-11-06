-- Host-independent entry point for a serialized, dedicated Lua Globals instance.
-- The host owns authorization, canonical/symlink-safe resolution, JSON, storage
-- discovery and UI dispatch. No Activity, Bean, AgentStorage or xTask is loaded.
local Service = require('mods.files.FileMutationService')
local M = {}

function M.new(options)
  local o=assert(options, 'options required')
  assert(type(o.scope)=='table' and type(o.scope.scopePath)=='string', 'scope.scopePath required')
  assert(type(o.storageDir)=='string' and o.storageDir~='', 'storageDir required')
  assert(o.backend and o.json and o.json.encode and o.json.decode, 'backend and json required')
  assert(type(o.resolve)=='function', 'boundary-checking resolve(relativePath,scope) required')
  assert(type(o.authorized)=='function', 'authorized(scope) required')
  assert(type(o.validate)=='function', 'Lua syntax validate(path,content) required')
  local scope={}
  for k,v in pairs(o.scope) do scope[k]=v end
  assert(scope.scopePath:sub(1,1)=='/' and scope.scopePath~='/' and scope.scopePath:sub(-1)~='/', 'absolute non-root scope required')
  scope.directory=scope.scopePath
  local cfg={}
  for k,v in pairs(o) do cfg[k]=v end
  cfg.fixedScope=scope
  cfg.loadResults=o.loadResults or function(dir,scopeId)
    local value=o.backend.listResults(dir,scopeId)
    return type(value)=='table' and value or o.json.decode(tostring(value))
  end
  -- UI hooks must marshal synchronously to the main thread themselves. The
  -- default host is headless; pending native results are never acknowledged.
  cfg.isMainThread=nil
  local service=Service.new(cfg)
  local api={}
  function api.recover() return service.recover() end
  function api.execute(name,args)
    local _,_,result=service.execute(name,args)
    return result
  end
  function api.executeJson(name,argsJson)
    return o.json.encode(api.execute(name,o.json.decode(argsJson)))
  end
  function api.getResult(id) return service.getResult(id) end
  function api.peek(direction)
    assert(o.authorized(scope)==true, 'scope authorization revoked')
    assert(direction=='undo' or direction=='redo', 'invalid history direction')
    return service.peek(direction)
  end
  function api.attachEditor(hooks) service.attachEditor(hooks) end
  function api.reconcile()
    local report=service.recover()
    service.drainNotifications()
    return report
  end
  return api
end
return M
