--- Recoverable, incremental project rename. No multi-file transaction is claimed.
--- Original workspace and Agent storage remain intact; conversation originals
--- are snapshotted before reassociation. A pending journal survives process death.
local Context = require "mods.project.ProjectContext"
local KV = require "mods.utils.LuaKV"
local M = {}

local function moved(path, oldPath, newPath)
  if type(path) ~= "string" then return path end
  if Context.contains(path, oldPath) then return newPath .. Context.normalize(path):sub(#oldPath + 1) end
  return path
end

local function workspace(oldPath, newPath)
  local source = KV.get("workspace", oldPath)
  if source == nil then
    if KV.exists("workspace", oldPath) then return false, "workspace_corrupt" end
    return true
  end
  if type(source) ~= "table" then return false, "workspace_corrupt" end
  if (source.tabs ~= nil and type(source.tabs) ~= "table")
      or (source.cursors ~= nil and type(source.cursors) ~= "table") then return false, "workspace_corrupt" end
  local target = KV.get("workspace", newPath)
  if target ~= nil or KV.exists("workspace", newPath) then return false, "workspace_conflict" end
  local result = {}
  for k, v in pairs(source) do result[k] = v end
  result.tabs, result.cursors = {}, {}
  for _, path in ipairs(source.tabs or {}) do result.tabs[#result.tabs + 1] = moved(path, oldPath, newPath) end
  for path, pos in pairs(source.cursors or {}) do result.cursors[moved(path, oldPath, newPath)] = pos end
  result.active = moved(source.active, oldPath, newPath)
  -- Marker makes this stage idempotent without overwriting unrelated target data.
  result.renamedFrom = oldPath
  if not KV.set("workspace", newPath, result) then return false, "workspace_write_failed" end
  return true
end

local function defaults(options)
  local o = options or {}
  if not o.exists then
    local File = luajava.bindClass("java.io.File")
    o.exists = function(path) return File(path).exists() end
  end
  o.move = o.move or function(oldPath, newPath)
    return tostring(LuaFileUtil.renameWithin(oldPath, newPath:match("([^/]+)$")) or "failed")
  end
  o.conversations = o.conversations or require("mods.agent.ConversationStore")
  o.agentStorage = o.agentStorage or require("mods.agent.AgentStorage")
  o.recent = o.recent or require("mods.project.RecentProjects")
  return o
end

local function save(journal)
  return KV.set("project_migrations", "pending_rename", journal)
end

function M.rename(oldPath, newPath, options)
  oldPath, newPath = Context.normalize(oldPath), Context.normalize(newPath)
  if not Context.projectKeyOf(oldPath) or Context.projectKeyOf(oldPath) ~= oldPath
      or Context.projectKeyOf(newPath) ~= newPath then return false, { error = "invalid_project_path", stage = "validate" } end
  if oldPath == newPath then return true, { path = newPath, stage = "same", completed = true } end
  local o = defaults(options)
  local journal = KV.get("project_migrations", "pending_rename")
  if journal and (type(journal) ~= "table" or journal.oldPath ~= oldPath or journal.newPath ~= newPath) then
    return false, { error = "rename_pending_conflict", stage = "journal", retryable = true }
  end
  if not journal and KV.exists("project_migrations", "pending_rename") then
    return false, { error = "rename_journal_corrupt", stage = "journal" }
  end
  local function failure(stage, err)
    return false, { stage = stage, error = err, path = o.exists(oldPath) and oldPath or newPath,
      oldPath = oldPath, newPath = newPath, retryable = true,
      completed = stage == "journal_cleanup" and not o.exists(oldPath) and o.exists(newPath) }
  end
  if not journal then
    if not o.exists(oldPath) then return failure("validate", "source_missing") end
    if o.exists(newPath) then return failure("validate", "exists") end
    journal = { oldPath = oldPath, newPath = newPath }
    if not save(journal) then return failure("journal", "rename_journal_write_failed") end
  end
  if not journal.workspace then
    local target = KV.get("workspace", newPath)
    local ok, err
    if type(target) == "table" and target.renamedFrom == oldPath then ok = true
    else ok, err = workspace(oldPath, newPath) end
    if not ok then return failure("workspace", err) end
    journal.workspace = true
    if not save(journal) then return failure("journal", "rename_journal_write_failed") end
  end
  local agentRoot = Context.snapshot().agentRoot
  local called, ok, err = pcall(o.agentStorage.reassociateProject, oldPath, newPath, agentRoot ~= "" and agentRoot or nil)
  if not called then return failure("agent_storage", tostring(ok)) end
  if not ok then return failure("agent_storage", err) end
  called, ok, err = pcall(o.conversations.reassociateProject, oldPath, newPath)
  if not called then return failure("conversations", tostring(ok)) end
  if not ok then return failure("conversations", err) end
  called, ok, err = pcall(o.recent.rename, oldPath, newPath)
  if not called then return failure("recent", tostring(ok)) end
  if not ok then return failure("recent", err or "recent_write_failed") end
  -- Move the directory LAST: metadata failures must not strand a live editor
  -- on a vanished filename which its autosave could recreate.
  if o.exists(oldPath) then
    if o.exists(newPath) then return failure("directory", "exists") end
    local movedOK, result = pcall(o.move, oldPath, newPath)
    if not movedOK then return failure("directory", tostring(result)) end
    if result ~= "ok" then return failure("directory", result) end
  elseif not o.exists(newPath) then return failure("directory", "source_and_target_missing") end
  if o.exists(oldPath) or not o.exists(newPath) then return failure("directory", "rename_verification_failed") end
  if not KV.delete("project_migrations", "pending_rename") then return failure("journal_cleanup", "rename_journal_cleanup_failed") end
  return true, { path = newPath, oldPath = oldPath, newPath = newPath, stage = "complete", completed = true }
end

--- Read-only journal introspection. Does not decode/load conversation bodies or
--- mutate journal/workspace/Agent data. Errors are explicit, never empty success.
function M.pendingRename()
  local journal, readError = KV.peek("project_migrations", "pending_rename")
  if journal == nil then
    if readError == "missing" then return nil end
    return nil, { stage = "journal", error = readError == "read_failed" and "rename_journal_read_failed" or "rename_journal_corrupt", completed = false }
  end
  if type(journal) ~= "table" or type(journal.oldPath) ~= "string" or type(journal.newPath) ~= "string" then
    return nil, { stage = "journal", error = "rename_journal_corrupt", completed = false }
  end
  return { oldPath = journal.oldPath, newPath = journal.newPath }
end

--- UI-free backend primitive. Hosts must use a foreground ownership guard;
--- never automatically invoke this from background project scans.
function M.resumePending(options)
  local journal, err = M.pendingRename()
  if err then return false, err end
  if not journal then return true, { stage = "none", completed = false } end
  return M.rename(journal.oldPath, journal.newPath, options)
end

return M
