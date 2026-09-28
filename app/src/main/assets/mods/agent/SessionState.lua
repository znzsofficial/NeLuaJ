--- 当前会话的工作集：消息、用量、身份和回合撤销。
--- 不持有视图，也不直接读写存储；持久化仍由 ChatUI 调用 AgentChat。
local _M = {}

local state = {
  messages = {},
  undo = {},
  redo = {},
  id = nil,
  projectPath = nil,
  loaded = false,
  hadMessages = false,
  usage = { requests = 0, tokens = 0 },
}

local function freshUsage(saved)
  return {
    requests = tonumber(saved and saved.requests) or 0,
    tokens = tonumber(saved and saved.tokens) or 0,
  }
end

function _M.messages() return state.messages end

function _M.setMessages(list)
  state.messages = type(list) == "table" and list or {}
  return state.messages
end

function _M.usage() return state.usage end

function _M.usageRecord()
  return { requests = state.usage.requests, tokens = state.usage.tokens }
end

function _M.addUsage(tokens)
  state.usage.requests = state.usage.requests + 1
  state.usage.tokens = state.usage.tokens + math.max(0, tonumber(tokens) or 0)
end

function _M.id() return state.id end
function _M.projectPath() return state.projectPath end
function _M.loaded() return state.loaded end
function _M.hadMessages() return state.hadMessages end

function _M.syncHadMessages()
  state.hadMessages = #state.messages > 0
end

function _M.canPersist(projectPath, updates)
  if not state.loaded or not state.id or state.id == "" then return false end
  if state.projectPath ~= projectPath then return false end
  local allowEmpty = type(updates) == "table" and updates.__allow_empty == true
  if #state.messages == 0 and state.hadMessages and not allowEmpty then return false end
  return true
end

--- 用存储记录替换工作集。调用方仍可随后原地追加消息。
function _M.activate(conv, projectPath)
  state.id = conv and conv.id or nil
  state.projectPath = conv and projectPath or nil
  state.loaded = conv ~= nil
  state.messages = conv and type(conv.messages) == "table" and conv.messages or {}
  local saved = type(conv and conv.usage) == "table" and conv.usage or nil
  state.usage = freshUsage(saved)
  state.hadMessages = #state.messages > 0
  return state.messages
end

function _M.resetTurns()
  state.undo = {}
  state.redo = {}
end

function _M.clearRedo()
  state.redo = {}
end

function _M.canRedo()
  return #state.redo > 0
end

function _M.undoTurn()
  local messages = state.messages
  local start
  for index = #messages, 1, -1 do
    if messages[index].role == "user" then start = index break end
  end
  if not start then return nil end
  local removed = {}
  for index = start, #messages do removed[#removed + 1] = messages[index] end
  for index = #messages, start, -1 do table.remove(messages, index) end
  state.undo[#state.undo + 1] = removed
  table.insert(state.redo, 1, removed)
  return removed
end

function _M.redoTurn()
  if #state.redo == 0 then return nil end
  local restored = table.remove(state.redo, 1)
  for _, message in ipairs(restored) do state.messages[#state.messages + 1] = message end
  state.undo[#state.undo + 1] = restored
  return restored
end

--- 切换前先清空工作消息，避免旧列表在 loadHistory 前被保存。
function _M.beginSwitch(id, projectPath)
  state.id = id
  state.projectPath = projectPath
  state.loaded = true
  state.hadMessages = false
  state.messages = {}
  return state.messages
end

function _M.beginCreated(conv, projectPath)
  state.id = conv and conv.id or nil
  state.projectPath = conv and projectPath or nil
  state.loaded = conv ~= nil
  state.hadMessages = false
  state.messages = conv and type(conv.messages) == "table" and conv.messages or {}
  state.usage = freshUsage(nil)
  return state.messages
end

function _M.select(id, projectPath)
  state.id = id
  state.projectPath = projectPath
  state.loaded = true
  state.hadMessages = false
end

function _M.clearMessages()
  state.messages = {}
  state.hadMessages = false
  return state.messages
end

--- 工程切换前只解除身份，消息表留到下一次 activate 替换。
function _M.suspend()
  state.loaded = false
  state.id = nil
  state.projectPath = nil
  state.hadMessages = false
end

function _M.reset()
  state.messages = {}
  state.undo = {}
  state.redo = {}
  state.id = nil
  state.projectPath = nil
  state.loaded = false
  state.hadMessages = false
  state.usage = freshUsage(nil)
  return state.messages
end

return _M
