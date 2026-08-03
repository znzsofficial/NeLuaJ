--- Agent 外部存储：/sdcard/LuaJ/agents/projects/<project-hash>/。
local _M = {}
local Environment = luajava.bindClass("android.os.Environment")
local File = luajava.bindClass("java.io.File")
local FileOutputStream = luajava.bindClass("java.io.FileOutputStream")

local root = ""
local projectDir = ""

local function hash(text)
  local value = 0
  text = tostring(text or "")
  for i = 1, #text do value = (value * 31 + text:byte(i)) % 2147483647 end
  return tostring(value)
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
  root = tostring(agentRoot or (tostring(Environment.getExternalStorageDirectory()) .. "/LuaJ/agents"))
  local projectRoot = tostring(path or "")
  projectDir = root .. "/projects/" .. hash(projectRoot)
  return true
end

function _M.configureCurrent(path, agentRoot)
  local nextRoot = tostring(agentRoot or (tostring(Environment.getExternalStorageDirectory()) .. "/LuaJ/agents"))
  local nextProject = nextRoot .. "/projects/" .. hash(tostring(path or ""))
  if nextRoot ~= root or nextProject ~= projectDir then
    return _M.configure(path, agentRoot)
  end
  return true
end

function _M.getRoot() return root end
function _M.getProjectDir() return projectDir end

function _M.read(name)
  if projectDir == "" then return nil end
  if not ensureDirectory(projectDir) then return nil end
  local target = File(projectDir, safeName(name))
  local backup = File(projectDir, "." .. safeName(name) .. ".bak")
  local hadTarget = target.exists()
  local restored = false
  if not hadTarget and backup.exists() then restored = backup.renameTo(target) end
  -- Keep the backup when recovery failed so a later read can retry it.
  if hadTarget and target.exists() and backup.exists() then backup.delete() end
  if restored and backup.exists() then backup.delete() end
  if not target.exists() or not target.isFile() then return nil end
  local ok, content = pcall(function() return file.readall(target.getAbsolutePath()) end)
  return ok and content or nil
end

function _M.write(name, content)
  if projectDir == "" or not ensureDirectory(projectDir) then return false end
  local target = File(projectDir, safeName(name))
  local temp = File(projectDir, "." .. safeName(name) .. ".tmp")
  local backup = File(projectDir, "." .. safeName(name) .. ".bak")
  local tempPath = temp.getAbsolutePath()
  local ok = pcall(function()
    local stream = FileOutputStream(tempPath, false)
    stream.write(tostring(content or ""):getBytes("UTF-8"))
    stream.flush()
    stream.close()
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
end

function _M.delete(name)
  if projectDir == "" then return false end
  local target = File(projectDir, safeName(name))
  return not target.exists() or target.delete()
end

return _M
