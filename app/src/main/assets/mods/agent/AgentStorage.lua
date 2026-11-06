--- Agent 外部存储：/sdcard/LuaJ/agents/projects/<project-hash>/。
local _M = {}
local Environment = luajava.bindClass("android.os.Environment")
local File = luajava.bindClass("java.io.File")
local FileOutputStream = luajava.bindClass("java.io.FileOutputStream")
local MessageDigest = luajava.bindClass("java.security.MessageDigest")
local ReentrantLock = luajava.bindClass("java.util.concurrent.locks.ReentrantLock")
local UUID = luajava.bindClass("java.util.UUID")
local KV = require("mods.utils.LuaKV")

local root = ""
local projectDir = ""
local legacyProjectDir = ""
local storageLock = ReentrantLock()

local function legacyHash(text)
  local value = 0
  text = tostring(text or "")
  for i = 1, #text do value = (value * 31 + text:byte(i)) % 2147483647 end
  return tostring(value)
end

local function hash(text)
  local javaText = luajava.newInstance("java.lang.String", tostring(text or ""))
  local digest = MessageDigest.getInstance("SHA-256").digest(javaText.getBytes("UTF-8"))
  local out = {}
  for index = 0, 11 do
    local value = tonumber(digest[index]) or 0
    if value < 0 then value = value + 256 end
    out[#out + 1] = string.format("%02x", value)
  end
  return table.concat(out)
end

local function ensureDirectory(path)
  local dir = File(path)
  if dir.exists() then return dir.isDirectory() end
  return dir.mkdirs()
end

local function safeName(name)
  name = tostring(name or "data"):gsub("[^%w%._%-]", "_")
  if name == "" then name = "data" end
  return name
end

local function resolveProject(path, storageRoot)
  local key = storageRoot .. "\n" .. tostring(path or "")
  local alias = KV.get("agent_project_aliases", key)
  if alias ~= nil then
    if type(alias) ~= "table" or type(alias.projectDir) ~= "string"
        or type(alias.legacyProjectDir) ~= "string"
        or alias.projectDir:sub(1, #storageRoot + 10) ~= storageRoot .. "/projects/"
        or alias.legacyProjectDir:sub(1, #storageRoot + 10) ~= storageRoot .. "/projects/" then
      error("agent_storage_alias_corrupt")
    end
    return alias.projectDir, alias.legacyProjectDir
  end
  if KV.exists("agent_project_aliases", key) then error("agent_storage_alias_corrupt") end
  return storageRoot .. "/projects/" .. hash(path), storageRoot .. "/projects/" .. legacyHash(path)
end

function _M.configure(path, agentRoot)
  storageLock.lock()
  local ok = pcall(function()
    root = tostring(agentRoot or (tostring(Environment.getExternalStorageDirectory()) .. "/LuaJ/agents"))
    local projectRoot = tostring(path or "")
    projectDir, legacyProjectDir = resolveProject(projectRoot, root)
  end)
  storageLock.unlock()
  return ok
end

function _M.configureCurrent(path, agentRoot)
  storageLock.lock()
  local ok = pcall(function()
    local nextRoot = tostring(agentRoot or (tostring(Environment.getExternalStorageDirectory()) .. "/LuaJ/agents"))
    local projectRoot = tostring(path or "")
    local nextProject, nextLegacy = resolveProject(projectRoot, nextRoot)
    if nextRoot ~= root or nextProject ~= projectDir then
      root = nextRoot
      projectDir = nextProject
      legacyProjectDir = nextLegacy
    end
  end)
  storageLock.unlock()
  return ok
end

function _M.getRoot() return root end
function _M.getProjectDir() return projectDir end

-- Detached storage identity; workers must never consult mutable projectDir.
function _M.capture(scopePath, agentRoot)
  local storageRoot = tostring(agentRoot or (tostring(Environment.getExternalStorageDirectory()) .. "/LuaJ/agents"))
  if storageRoot == "" then storageRoot = tostring(Environment.getExternalStorageDirectory()) .. "/LuaJ/agents" end
  storageLock.lock()
  local ok, dir, legacy = pcall(resolveProject, scopePath, storageRoot)
  storageLock.unlock()
  if not ok then error(dir) end
  return { storageDir = dir, legacyStorageDir = legacy, scopeId = scopePath }
end

-- Fixed-directory replay acknowledgements. No mutable project selection, and
-- failed writes leave the result eligible for replay on the next resume.
function _M.isMutationAcknowledged(storageDir, id)
  return File(storageDir .. "/ui-ack", safeName(id)).isFile()
end

function _M.acknowledgeMutation(storageDir, id)
  local directory=storageDir .. "/ui-ack"
  if not ensureDirectory(directory) then return false end
  local target=File(directory,safeName(id))
  if target.isFile() then return true end
  local temp=File(directory,"." .. safeName(id) .. "." .. tostring(UUID.randomUUID()))
  local ok=pcall(function()
    local stream=FileOutputStream(temp,false)
    local wrote,err=pcall(function()
      stream.write(1); stream.flush(); stream.getFD().sync()
    end)
    pcall(function() stream.close() end)
    if not wrote then error(err) end
    if not temp.renameTo(target) and not target.isFile() then error('ack_publish_failed') end
  end)
  if temp.exists() then temp.delete() end
  return ok
end

--- Reassociate the new path with the existing hashed storage, without moving or
--- deleting any directory. Both paths keep access; conflicts are never merged.
function _M.reassociateProject(oldPath, newPath, agentRoot)
  storageLock.lock()
  local called, result, err = pcall(function()
    local storageRoot = tostring(agentRoot or (tostring(Environment.getExternalStorageDirectory()) .. "/LuaJ/agents"))
    local source, legacy = resolveProject(oldPath, storageRoot)
    local target, targetLegacy = resolveProject(newPath, storageRoot)
    if source == target and legacy == targetLegacy then return true end
    local function nonempty(path)
      local dir = File(path)
      if not dir.exists() then return false end
      local children = dir.list()
      return not dir.isDirectory() or children == nil or #children > 0
    end
    if nonempty(target) or nonempty(targetLegacy) then return false, "agent_storage_conflict" end
    if not KV.set("agent_project_aliases", storageRoot .. "\n" .. tostring(newPath), {
      projectDir = source, legacyProjectDir = legacy,
    }) then return false, "agent_storage_alias_write_failed" end
    return true
  end)
  storageLock.unlock()
  if not called then return false, tostring(result) end
  return result, err
end

function _M.read(name)
  storageLock.lock()
  local okRead, result = pcall(function()
  if projectDir == "" then return nil end
  if not ensureDirectory(projectDir) then return nil end
  local target = File(projectDir, safeName(name))
  local backup = File(projectDir, "." .. safeName(name) .. ".bak")
  if not target.exists() and not backup.exists() and legacyProjectDir ~= projectDir then
    local legacy = File(legacyProjectDir, safeName(name))
    if legacy.exists() and legacy.isFile() then
      local ok, saved = pcall(function()
        return file.save(target.getAbsolutePath(), file.readall(legacy.getAbsolutePath()))
      end)
      if not ok or saved ~= true then return nil end
    end
  end
  local hadTarget = target.exists()
  local restored = false
  if not hadTarget and backup.exists() then restored = backup.renameTo(target) end
  -- Keep the backup when recovery failed so a later read can retry it.
  if hadTarget and target.exists() and backup.exists() then backup.delete() end
  if restored and backup.exists() then backup.delete() end
  if not target.exists() or not target.isFile() then return nil end
  local ok, content = pcall(function() return file.readall(target.getAbsolutePath()) end)
  return ok and content or nil
  end)
  storageLock.unlock()
  return okRead and result or nil
end

function _M.write(name, content)
  storageLock.lock()
  local okWrite, result = pcall(function()
  if projectDir == "" or not ensureDirectory(projectDir) then return false end
  local target = File(projectDir, safeName(name))
  local temp = File(projectDir, "." .. safeName(name) .. "." .. tostring(UUID.randomUUID()) .. ".tmp")
  local backup = File(projectDir, "." .. safeName(name) .. ".bak")
  local tempPath = temp.getAbsolutePath()
  local ok = pcall(function()
    local stream = FileOutputStream(tempPath, false)
    local wrote, writeErr = pcall(function()
      local javaContent = luajava.newInstance("java.lang.String", tostring(content or ""))
      stream.write(javaContent.getBytes("UTF-8"))
      stream.flush()
    end)
    pcall(function() stream.close() end)
    if not wrote then error(writeErr) end
    if backup.exists() and not backup.delete() then error("无法清理旧备份") end
    if target.exists() and not target.renameTo(backup) then error("无法保留旧存储文件") end
    if not temp.renameTo(target) then
      if backup.exists() then backup.renameTo(target) end
      error("无法提交存储文件")
    end
    backup.delete()
  end)
  if not ok then pcall(function() temp.delete() end) end
  return ok
  end)
  storageLock.unlock()
  return okWrite and result == true
end

function _M.delete(name)
  storageLock.lock()
  local okDelete, result = pcall(function()
  if projectDir == "" then return false end
  local target = File(projectDir, safeName(name))
  return not target.exists() or target.delete()
  end)
  storageLock.unlock()
  return okDelete and result == true
end

return _M
