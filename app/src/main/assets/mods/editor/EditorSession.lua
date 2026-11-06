--- 编辑器会话：当前文件、最近文件和光标。不碰控件，也不写磁盘。
local _M = {}

local MAX_RECENT = 50
local owner = {}
local state = {
  current = nil,
  recent = {},
  cursors = {},
  bindingEpoch = 0,
  bufferRevision = 0,
}

function _M.current()
  return state.current
end

function _M.setCurrent(path)
  local normalized = path ~= "" and path or nil
  if normalized ~= state.current then
    state.bindingEpoch = state.bindingEpoch + 1
    state.bufferRevision, state.text = 0, nil
  end
  if path == nil or path == "" then
    state.current = nil
  else
    state.current = path
  end
end

function _M.observeText(text)
  if state.text ~= text then
    state.bufferRevision = state.bufferRevision + 1
    state.text = text
  end
  return state.bufferRevision
end

function _M.identity(text)
  if text ~= nil then _M.observeText(text) end
  return { path = state.current, documentId = tostring(owner) .. ":" .. state.bindingEpoch, owner = owner,
    bindingEpoch = state.bindingEpoch, bufferRevision = state.bufferRevision }
end

function _M.isBinding(identity)
  return identity and identity.owner == owner and identity.path == state.current
    and identity.bindingEpoch == state.bindingEpoch
end

function _M.isCurrent(path)
  return state.current ~= nil and state.current == path
end

function _M.cursor(path)
  local value = state.cursors[path]
  if type(value) == "number" then return value end
  return nil
end

function _M.setCursor(path, position)
  if type(path) ~= "string" or path == "" or type(position) ~= "number" then return end
  state.cursors[path] = position
end

function _M.cursors()
  local copy = {}
  for path, position in pairs(state.cursors) do
    if type(path) == "string" and type(position) == "number" then
      copy[path] = position
    end
  end
  return copy
end

function _M.importCursors(saved)
  if type(saved) ~= "table" then return end
  for path, position in pairs(saved) do
    if type(path) == "string" and type(position) == "number" then
      state.cursors[path] = position
    end
  end
end

function _M.recent()
  local copy = {}
  for index, path in ipairs(state.recent) do
    copy[index] = path
  end
  return copy
end

function _M.remember(path)
  if type(path) ~= "string" or path == "" then return end
  local list = { path }
  for _, item in ipairs(state.recent) do
    if item ~= path and #list < MAX_RECENT then
      list[#list + 1] = item
    end
  end
  state.recent = list
end

return _M
