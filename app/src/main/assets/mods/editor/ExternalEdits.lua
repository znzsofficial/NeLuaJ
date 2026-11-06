-- Main-thread bridge shared by main turns, subagents, and file undo/redo.
local M = {}

function M.prepare(name, args, token)
  local editor = package.loaded["mods.utils.EditorUtil"]
  if not editor or not editor.prepareFileOperation then return nil end
  return editor.prepareFileOperation(name, args, token)
end

function M.finish(snapshot, name, args, effects)
  if not snapshot then return true end
  local editor = package.loaded["mods.utils.EditorUtil"]
  if not editor or not editor.finishFileOperation then return false, "editor_unavailable" end
  local ok, warning = editor.finishFileOperation(snapshot, effects)
  if warning and effects then
    effects.warnings = effects.warnings or {}
    effects.warnings[#effects.warnings + 1] = warning
  end
  return ok, warning
end

function M.captureRecovery(result)
  local editor = package.loaded["mods.utils.EditorUtil"]
  if not editor or not editor.captureRecovery then return nil, "editor_unavailable" end
  return editor.captureRecovery(result)
end

-- Call from onResume after editor widgets have been restored. The service owns
-- pending terminal results and releases its lock before invoking this bridge.
function M.reconcile()
  local service = package.loaded["mods.files.FileMutationService"]
  if service then return service.reconcile() end
  return true
end

return M
