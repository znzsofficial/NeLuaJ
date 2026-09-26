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
  if cfg.encode then
    local ok, encoded = pcall(cfg.encode, value)
    if ok and encoded ~= nil then return encoded end
    return nil
  end
  if json and json.encode then return json.encode(value) end
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

--- 原子读：文件缺失/为空返回 nil（LuaJ 的 io.open 对缺失文件会抛错，须 pcall）
function _M.read(path)
  local ok, h = pcall(io.open, path, "rb")
  if not ok or not h then return nil end
  local content = h:read("*a")
  h:close()
  if content == "" then return nil end
  return content
end

--- 原子写：tmp 落盘 → 旧文件让位 .bak → rename 就位；失败尝试回滚。
--- 自动 mkdirs 父目录（luajava 兜底或注入的 ensureDir）。
function _M.writeAtomic(path, content)
  ensureDir(path:match("^(.*)[/\\][^/\\]*$") or ".")
  local tmp = path .. ".tmp"
  local okOpen, h = pcall(io.open, tmp, "wb")
  if not okOpen or not h then return false end
  local ok = h:write(content)
  h:close()
  if not ok then
    pcall(os.remove, tmp)
    return false
  end
  pcall(os.remove, path .. ".bak")
  pcall(os.rename, path, path .. ".bak")
  if os.rename(tmp, path) then
    pcall(os.remove, path .. ".bak")
    return true
  end
  pcall(function()
    os.rename(path .. ".bak", path)
    os.remove(tmp)
  end)
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

--- 删除键及其备份；键不存在视为已删除（返回 true）
function _M.delete(ns, key)
  local path = keyPath(ns, key)
  if not _M.read(path) then return true end
  pcall(os.remove, path)
  pcall(os.remove, path .. ".bak")
  return not _M.read(path)
end

return _M
