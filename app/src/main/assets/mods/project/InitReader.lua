--- init.lua 工程配置读取：两种方式共享。
--- readField：字符串直读（不执行文件），适合列表等高频渲染场景；
--- load：LuaFileUtil.loadLua 独立环境完整解析，正确性优先，适合菜单等低频场景；
--- field：对 load 结果做规范化字段读取（空串/"nil" 回退默认值）。
local _M = {}

--- 从 init.lua 源码字符串直读字段（仅支持字面量字符串赋值）
function _M.readField(path, key)
  local ok, content = pcall(function() return file.readall(path .. "/init.lua") end)
  if not ok or type(content) ~= "string" then return nil end
  return content:match(key .. '%s*=%s*"([^"]*)"') or content:match(key .. "%s*=%s*'([^']+)'")
end

--- 完整解析 init.lua（独立 Lua 环境）；失败返回 nil
function _M.load(path)
  local ok, t = pcall(function() return LuaFileUtil.loadLua(path .. "/init.lua") end)
  if ok and type(t) == "table" then return t end
  return nil
end

--- 对 load 结果的规范化字段读取
function _M.field(init, key, fallback)
  if not init then return fallback end
  local ok, v = pcall(function() return init[key] end)
  if ok and v ~= nil then
    local s = tostring(v)
    if s ~= "" and s ~= "nil" then return s end
  end
  return fallback
end

return _M
