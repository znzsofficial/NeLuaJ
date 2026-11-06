-- UI-owned snapshots never cross into the worker Lua state.
local M = {}
local Host = luajava.bindClass('com.nekolaska.mcp.server.McpMutationHost')
local Context = require('mods.project.ProjectContext')
local Editor = require('mods.utils.EditorUtil')
local Storage = require('mods.agent.AgentStorage')
local snapshots, sequence = {}, 0
local identity = tostring(luajava.bindClass('java.util.UUID').randomUUID())
local recovery = require('mods.files.FileMutationService').new({
  context=Context,
  json=require('json'),
  prepareRecovery=Editor.captureRecovery,
  finish=function(snapshot, name, args, result)
    local synced, err = Editor.finishFileOperation(snapshot, result)
    if MainActivity and MainActivity.RecyclerView then MainActivity.RecyclerView.update() end
    return synced, err
  end,
  loadResults=function(dir, scope)
    return require('json').decode(tostring(luajava.kotlinObject('com.nekolaska.io.FileMutationEngine').listResults(dir,scope)))
  end,
  isAcknowledged=Storage.isMutationAcknowledged,
  acknowledge=Storage.acknowledgeMutation,
})
local function capture(snapshot)
  if not snapshot then return {} end
  sequence = sequence + 1
  local key = identity .. ':' .. tostring(sequence)
  -- Rejected native requests do not have a finish callback. Bound their UI data.
  snapshots[identity .. ':' .. tostring(sequence - 64)] = nil
  snapshots[key] = snapshot
  return {snapshot=key}
end
function M.dispatch(encoded)
  local codec = require('json')
  local ok, response = pcall(function()
    local request = codec.decode(tostring(encoded))
    if request.scopePath ~= Context.snapshot().scopePath then return {synced=false,message='scope_stale'} end
    if request.action == 'prepare' then
      return capture(Editor.prepareFileOperation(request.name, request.args, request.token))
    elseif request.action == 'recovery' then
      return capture(Editor.captureRecovery(request.result))
    elseif request.action == 'finish' then
      local snapshot = snapshots[request.snapshot]
      snapshots[request.snapshot] = nil
      if not snapshot or not Context.isCurrent(snapshot.scope, 'project') then
        return {synced=false,message='editor_binding_stale'}
      end
      local synced, err = Editor.finishFileOperation(snapshot, request.result)
      if MainActivity and MainActivity.RecyclerView then MainActivity.RecyclerView.update() end
      pcall(function() activity.invalidateOptionsMenu() end)
      return {synced=synced == true,message=err}
    end
    return {synced=false,message='unknown_editor_action'}
  end)
  return codec.encode(ok and response or {error=true,synced=false,message=tostring(response)})
end
function M.register()
  Host.registerEditor(activity)
  recovery.reconcilePending()
end
function M.unregister()
  Host.unregisterEditor(activity)
  snapshots = {}
end
return M
