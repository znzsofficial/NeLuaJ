--- 纯 Lua 目录型 KV：每个键一个 JSON 记录文件，tmp + rename 原子写。
--- 崩溃只影响正在写入的那个键，互不牵连；键名白名单编码防路径穿越。
--- 宿主依赖：io/os（标准）+ luajava mkdirs 兜底（可经 ensureDir 注入覆盖）。
--- root/encode/decode 建议显式注入：设备侧默认走 Bean.Path.agent_root_dir，
--- 桌面测试注入临时目录与可往返的测试编解码器。
local _M = {}

local cfg = {}

function _M.configure(options)
  cfg = options or {}
end

function _M.isConfigured()
  return cfg.root ~= nil
end

local function rootDir()
  if cfg.root then
    local ok, p = pcall(cfg.root)
    if ok and p and p ~= "" then return tostring(p) end
  end
  return (Bean and Bean.Path and Bean.Path.agent_root_dir or "/sdcard/LuaJ/agents") .. "/kv"
end

--- 当前根目录（调用方可在其下放置自有元数据文件，如会话索引）
function _M.rootPath()
  return rootDir()
end

local function encodeValue(value)
  local encode = cfg.encode or (json and json.encode)
  if not encode then return nil end
  local ok, encoded = pcall(encode, value)
  if ok and type(encoded) == "string" then return encoded end
  return nil
end

local function decodeValue(text)
  if cfg.decode then
    local ok, decoded = pcall(cfg.decode, text)
    if ok then return decoded end
    return nil
  end
  if json and json.decode then return json.decode(text) end
  return nil
end

local function sanitizeKey(key)
  return tostring(key):gsub("[^%w%-_]", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
end

--- 命名空间目录：<root>/<ns>
function _M.nsPath(ns)
  return rootDir() .. "/" .. sanitizeKey(ns)
end

local function keyPath(ns, key)
  return _M.nsPath(ns) .. "/" .. sanitizeKey(key) .. ".json"
end

local function ensureDir(dir)
  if cfg.ensureDir then
    local ok, result = pcall(cfg.ensureDir, dir)
    if ok and result ~= false then return true end
  end
  if luajava and luajava.bindClass then
    local ok = pcall(function()
      luajava.bindClass("java.io.File")(dir).mkdirs()
    end)
    if ok then return true end
  end
  return false
end

--- 外置存储上 close() 会抛 EIO。io.open / read / write 也会抛。这些才需要 pcall。
--- os.remove 和 os.rename 失败时返回 nil 加错误信息，不会抛错；再用 pcall 会把失败看成成功。
local function closeQuietly(handle)
  if not handle then return end
  pcall(function() handle:close() end)
end

local function renamed(from, to)
  return os.rename(from, to) == true
end

local function removed(path)
  return os.remove(path) == true
end

local function readOnce(path)
  local ok, h = pcall(io.open, path, "rb")
  if not ok or not h then return nil end
  local okRead, content = pcall(function() return h:read("*a") end)
  closeQuietly(h)
  if not okRead or content == nil or content == "" then return nil end
  return content
end

--- 原子读：文件缺失、为空或读失败返回 nil。
--- 正式文件不在、但 .bak 还在时，说明上次替换被打断，读备份并尽量放回原位。
function _M.read(path)
  local content = readOnce(path)
  if content then return content end
  local backup = readOnce(path .. ".bak")
  if not backup then return nil end
  renamed(path .. ".bak", path)
  return backup
end

--- 设备上走 LuaFileUtil.replaceText：临时文件 fsync 后原子替换，不先挪走旧文件。
--- 桌面测试没有这个类时，才退回 .bak 换名。
local function replaceSynced(path, content)
  if not (luajava and luajava.kotlinObject) then return nil end
  local okUtil, util = pcall(luajava.kotlinObject, "com.nekolaska.io.LuaFileUtil")
  if not okUtil or util == nil or util.replaceText == nil then return nil end
  local ok, result = pcall(function() return util.replaceText(path, content) end)
  if ok and result == true then return true end
  return false
end

--- 原子写。设备上由 replaceText 完成；否则 tmp 落盘 → 旧文件让位 .bak → rename 就位。
function _M.writeAtomic(path, content)
  if type(content) ~= "string" then return false end
  local synced = replaceSynced(path, content)
  if synced ~= nil then return synced end
  ensureDir(path:match("^(.*)[/\\][^/\\]*$") or ".")
  local tmp = path .. ".tmp"
  local okOpen, h = pcall(io.open, tmp, "wb")
  if not okOpen or not h then return false end
  local okWrite, wrote = pcall(function() return h:write(content) end)
  local flushed = okWrite and wrote and pcall(function() h:flush() end)
  closeQuietly(h)
  if not flushed then
    removed(tmp)
    return false
  end
  removed(path .. ".bak")
  if readOnce(path) and not renamed(path, path .. ".bak") then
    removed(tmp)
    return false
  end
  if renamed(tmp, path) then
    removed(path .. ".bak")
    return true
  end
  renamed(path .. ".bak", path)
  removed(tmp)
  return false
end

--- 写入键：值经 encode 包装为 {"v": value} 后原子落盘
function _M.set(ns, key, value)
  local encoded = encodeValue({ v = value })
  if encoded == nil then return false end
  return _M.writeAtomic(keyPath(ns, key), encoded)
end

--- 读取键：缺失/损坏返回 fallback
function _M.get(ns, key, fallback)
  local content = _M.read(keyPath(ns, key))
  if not content then return fallback end
  local ok, decoded = pcall(decodeValue, content)
  if not ok or type(decoded) ~= "table" then return fallback end
  return decoded.v
end

function _M.exists(ns, key)
  return _M.read(keyPath(ns, key)) ~= nil
end

--- 删除键、备份和未完成的临时文件。键不存在视为已删除。
--- 不先读内容：读失败不能被当成已经删掉。
function _M.delete(ns, key)
  local path = keyPath(ns, key)
  removed(path)
  removed(path .. ".bak")
  removed(path .. ".tmp")
  return _M.read(path) == nil
end

return _M
