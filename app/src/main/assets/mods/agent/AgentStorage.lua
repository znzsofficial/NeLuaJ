--- Agent 外部存储：/sdcard/LuaJ/agents/projects/<project-hash>/。
local _M = {}
local Environment = luajava.bindClass("android.os.Environment")
local File = luajava.bindClass("java.io.File")
local FileOutputStream = luajava.bindClass("java.io.FileOutputStream")
local MessageDigest = luajava.bindClass("java.security.MessageDigest")
local ReentrantLock = luajava.bindClass("java.util.concurrent.locks.ReentrantLock")
local UUID = luajava.bindClass("java.util.UUID")

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

function _M.configure(path, agentRoot)
  storageLock.lock()
  local ok = pcall(function()
    root = tostring(agentRoot or (tostring(Environment.getExternalStorageDirectory()) .. "/LuaJ/agents"))
    local projectRoot = tostring(path or "")
    projectDir = root .. "/projects/" .. hash(projectRoot)
    legacyProjectDir = root .. "/projects/" .. legacyHash(projectRoot)
  end)
  storageLock.unlock()
  return ok
end

function _M.configureCurrent(path, agentRoot)
  storageLock.lock()
  local ok = pcall(function()
    local nextRoot = tostring(agentRoot or (tostring(Environment.getExternalStorageDirectory()) .. "/LuaJ/agents"))
    local projectRoot = tostring(path or "")
    local nextProject = nextRoot .. "/projects/" .. hash(projectRoot)
    if nextRoot ~= root or nextProject ~= projectDir then
      root = nextRoot
      projectDir = nextProject
      legacyProjectDir = root .. "/projects/" .. legacyHash(projectRoot)
    end
  end)
  storageLock.unlock()
  return ok
end

function _M.getRoot() return root end
function _M.getProjectDir() return projectDir end

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
