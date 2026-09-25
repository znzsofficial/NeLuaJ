--- 通用文本工具（纯 Lua，无环境依赖，可在独立 LuaJ 运行时测试）。
local _M = {}

--- 字节上限截断，回退尾部被切开的 UTF-8 序列（先去续字节，再去孤立的起始字节）。
--- 不追加任何省略号后缀，由调用方按需拼接。
function _M.utf8Cap(text, limit)
  text = tostring(text or "")
  if #text <= limit then return text end
  text = text:sub(1, limit)
  while #text > 0 do
    local b = text:byte(#text)
    if b >= 0x80 and b <= 0xBF then
      text = text:sub(1, -2)
    elseif b >= 0xC0 then
      text = text:sub(1, -2)
      break
    else
      break
    end
  end
  return text
end

return _M
