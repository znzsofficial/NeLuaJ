--- 会话数据存储：稳定 ID、工程作用域和持久化操作集中在这里。
local _M = {}

local CONVERSATIONS_KEY = "ai_conversations"
local CURRENT_BY_PROJECT_KEY = "ai_current_conv_by_project"
local CURRENT_ID_KEY = "ai_current_conv_id"
local LEGACY_CURRENT_INDEX_KEY = "ai_current_conv"

local config = {}
local conversations
local currentByProject
local sequence = 0

local function cfg()
  return config or {}
end

local function getData(key, defaultValue)
  local getter = cfg().getData
  if not getter then
    -- 未 configure 时的默认回退（与 encode/decode 回退 json 同理）：
    -- 首页等未加载 AgentChat 的环境也能读到共享数据
    if this and this.getSharedData then
      local ok, value = pcall(this.getSharedData, key, defaultValue)
      if ok and value ~= nil then return value end
    end
    return defaultValue
  end
  local ok, value = pcall(getter, key, defaultValue)
  if ok and value ~= nil then return value end
  return defaultValue
end

local function setData(key, value)
  local setter = cfg().setData
  if not setter then
    if this and this.setSharedData then
      local ok, result = pcall(this.setSharedData, key, value)
      return ok and result == true
    end
    return false
  end
  local ok, result = pcall(setter, key, value)
  return ok and result == true
end

local function encode(value)
  local encoder = cfg().encode or (json and json.encode)
  if not encoder then return nil end
  local ok, result = pcall(encoder, value)
  return ok and result or nil
end

local function decode(value)
  local decoder = cfg().decode or (json and json.decode)
  if not decoder then return nil end
  local ok, result = pcall(decoder, value)
  return ok and result or nil
end

local function clone(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local copy = {}
  seen[value] = copy
  for key, item in pairs(value) do
    copy[clone(key, seen)] = clone(item, seen)
  end
  return copy
end

local function trim(value)
  return tostring(value or ""):gsub("^%s*(.-)%s*$", "%1")
end

local function projectPath(value)
  local path = tostring(value or "")
  local normalizer = cfg().normalizeProjectPath
  if normalizer then
    local ok, normalized = pcall(normalizer, path)
    if ok and normalized and normalized ~= "" then path = tostring(normalized) end
  end
  if path == "" and cfg().getProjectPath then
    local ok, current = pcall(cfg().getProjectPath)
    if ok then path = tostring(current or "") end
  end
  return path
end

local function now()
  if cfg().now then
    local ok, value = pcall(cfg().now)
    if ok and value ~= nil then return tostring(value) end
  end
  return os.date("%m-%d %H:%M")
end

local function makeId(used)
  while true do
    sequence = sequence + 1
    local value
    if cfg().newId then
      local ok, generated = pcall(cfg().newId, sequence)
      if ok then value = tostring(generated or "") end
    end
    if not value or value == "" then
      value = "conv_" .. tostring(os.time()) .. "_" .. tostring(sequence)
    end
    if not used[value] then return value end
  end
end

local function normalizeMessages(value)
  if type(value) ~= "table" then return {}, true end
  local result = {}
  local changed = false
  for _, message in ipairs(value) do
    if type(message) == "table" then
      local copy = clone(message)
      if copy.response_output ~= nil and type(copy.response_output) ~= "table" then
        copy.response_output = nil
        copy.response_origin = nil
        changed = true
      end
      result[#result + 1] = copy
    else
      changed = true
    end
  end
  if #result ~= #value then changed = true end
  return result, changed
end

local function normalizeRecord(value, fallbackProject, used)
  if type(value) ~= "table" then return nil, true end
  local record = clone(value)
  local changed = false

  local id = trim(record.id)
  if id == "" or used[id] then
    id = makeId(used)
    changed = true
  end
  if record.id ~= id then changed = true end
  record.id = id
  used[id] = true

  local path = projectPath(record.projectPath or fallbackProject)
  if record.projectPath ~= path then changed = true end
  record.projectPath = path

  local name = tostring(record.name or "")
  if record.name ~= name then changed = true end
  record.name = name

  local createdAt = record.createdAt
  if createdAt == nil or tostring(createdAt) == "" then
    record.createdAt = now()
    changed = true
  else
    record.createdAt = tostring(createdAt)
    if record.createdAt ~= createdAt then changed = true end
  end

  if record.updatedAt ~= nil then
    local updatedAt = tostring(record.updatedAt)
    if record.updatedAt ~= updatedAt then changed = true end
    record.updatedAt = updatedAt
  end

  local messages, messagesChanged = normalizeMessages(record.messages)
  record.messages = messages
  if messagesChanged then changed = true end
  return record, changed
end

local function persistConversations(value)
  local encoded = encode(value)
  if not encoded or not setData(CONVERSATIONS_KEY, encoded) then return false end
  conversations = value
  return true
end

local function persistCurrentMap(value)
  local encoded = encode(value)
  if not encoded or not setData(CURRENT_BY_PROJECT_KEY, encoded) then return false end
  currentByProject = value
  return true
end

local function recordById(id, path, list)
  if not id or id == "" then return nil, 0 end
  list = list or _M.load()
  local expectedPath = path and projectPath(path) or nil
  id = tostring(id)
  for index, record in ipairs(list) do
    if record.id == id and (not expectedPath or record.projectPath == expectedPath) then
      return record, index
    end
  end
  return nil, 0
end

local function loadCurrentMap()
  local raw = getData(CURRENT_BY_PROJECT_KEY, "")
  local decoded = raw ~= "" and decode(raw) or nil
  if type(decoded) ~= "table" then return {} end

  local result = {}
  for path, id in pairs(decoded) do
    if type(path) == "string" and id ~= nil and tostring(id) ~= "" then
      local normalized = projectPath(path)
      if normalized ~= "" then result[normalized] = tostring(id) end
    end
  end
  return result
end

local function migrateLegacySelection(list, map)
  local changed = false
  local function remember(id)
    local record = recordById(id, nil, list)
    if record and record.projectPath ~= "" and map[record.projectPath] ~= record.id then
      map[record.projectPath] = record.id
      changed = true
    end
  end

  local storedId = getData(CURRENT_ID_KEY, "")
  if storedId and storedId ~= "" then remember(storedId) end

  local storedIndex = tonumber(getData(LEGACY_CURRENT_INDEX_KEY, "0")) or 0
  if storedIndex >= 1 and storedIndex <= #list then
    local record = list[storedIndex]
    if record and record.projectPath ~= "" and map[record.projectPath] == nil then
      map[record.projectPath] = record.id
      changed = true
    end
  end
  return changed
end

function _M.configure(options)
  config = options or {}
  conversations = nil
  currentByProject = nil
end

function _M.invalidate()
  conversations = nil
  currentByProject = nil
end

function _M.load(force)
  if conversations and not force then return clone(conversations) end

  local raw = getData(CONVERSATIONS_KEY, "")
  local decoded = raw ~= "" and decode(raw) or nil
  if type(decoded) ~= "table" then decoded = {} end

  local source = decoded
  if decoded.id then source = { decoded } end
  local fallbackProject = projectPath(nil)
  local used = {}
  local normalized = {}
  local migrated = false
  for _, value in ipairs(source) do
    local record, changed = normalizeRecord(value, fallbackProject, used)
    if record then
      normalized[#normalized + 1] = record
      if changed then migrated = true end
    else
      migrated = true
    end
  end

  conversations = normalized
  currentByProject = loadCurrentMap()
  if migrateLegacySelection(conversations, currentByProject) then
    persistCurrentMap(currentByProject)
  end
  if migrated and raw ~= "" then persistConversations(normalized) end
  return clone(conversations)
end

--- 轻量索引：仅提取记录的标量元数据，不深拷贝 messages。
--- 会话列表渲染（首页会话 tab）只需要元信息，全量 load 的深克隆
--- 在会话较多时是列表卡顿的主因。
function _M.loadIndex(force)
  if not conversations or force then _M.load(force) end
  local result = {}
  for _, record in ipairs(conversations) do
    local usage = type(record.usage) == "table" and clone(record.usage) or nil
    result[#result + 1] = {
      id = record.id,
      name = record.name,
      projectPath = record.projectPath,
      createdAt = record.createdAt,
      updatedAt = record.updatedAt,
      usage = usage,
      messageCount = type(record.messages) == "table" and #record.messages or 0,
    }
  end
  return result
end

function _M.list(path, force)
  local expectedPath = projectPath(path)
  local result = {}
  for index, record in ipairs(_M.load(force)) do
    if record.projectPath == expectedPath then
      result[#result + 1] = {
        conversation = clone(record),
        index = index,
        id = record.id,
      }
    end
  end
  return result
end

function _M.get(id, path)
  local record = recordById(id, path)
  return record and clone(record) or nil
end

function _M.current(path)
  local expectedPath = projectPath(path)
  local list = _M.list(expectedPath)
  if #list == 0 then return nil, 0 end

  local map = currentByProject or loadCurrentMap()
  local selectedId = map[expectedPath]
  local selected, selectedIndex = recordById(selectedId, expectedPath)
  if not selected then
    selected = list[#list].conversation
    selectedIndex = list[#list].index
    map = clone(map)
    map[expectedPath] = selected.id
    currentByProject = map
    persistCurrentMap(map)
  end
  setData(CURRENT_ID_KEY, selected.id)
  setData(LEGACY_CURRENT_INDEX_KEY, tostring(selectedIndex))
  return clone(selected), selectedIndex
end

function _M.setCurrent(id, path)
  local expectedPath = projectPath(path)
  local record, index = recordById(id, expectedPath)
  if not record then return nil, 0 end
  local map = clone(currentByProject or loadCurrentMap())
  map[expectedPath] = record.id
  if not persistCurrentMap(map) then return nil, 0 end
  setData(CURRENT_ID_KEY, record.id)
  setData(LEGACY_CURRENT_INDEX_KEY, tostring(index))
  return clone(record), index
end

function _M.create(name, path)
  local expectedPath = projectPath(path)
  local current = _M.load()
  local candidate = clone(current)
  local used = {}
  for _, record in ipairs(candidate) do used[record.id] = true end

  local record = {
    id = makeId(used),
    name = tostring(name or ""),
    projectPath = expectedPath,
    messages = {},
    createdAt = now(),
    updatedAt = now(),
  }
  candidate[#candidate + 1] = record
  if not persistConversations(candidate) then return nil, 0 end

  local _, index = recordById(record.id, expectedPath, candidate)
  _M.setCurrent(record.id, expectedPath)
  return clone(record), index
end

function _M.save(id, messages, path, updates)
  local expectedPath = path and projectPath(path) or nil
  local current = _M.load()
  local record, index = recordById(id, expectedPath, current)
  if not record then return false end

  local candidate = clone(current)
  local target = candidate[index]
  local nextMessages = type(messages) == "table" and messages or {}
  local allowEmpty = type(updates) == "table" and updates.__allow_empty == true
  -- A stale lifecycle callback can reach the store with the module's initial
  -- empty table. Never let that erase a previously persisted conversation.
  if #nextMessages == 0 and type(target.messages) == "table"
      and #target.messages > 0 and not allowEmpty then
    return false
  end
  target.messages = clone(nextMessages)
  if type(updates) == "table" then
    for key, value in pairs(updates) do
      if key ~= "id" and key ~= "projectPath" and key ~= "messages" and key ~= "__allow_empty" then
        target[key] = clone(value)
      end
    end
  end
  target.updatedAt = now()

  if target.name == "" or target.name == "新对话" then
    for _, message in ipairs(target.messages) do
      if message.role == "user" and message.content and tostring(message.content) ~= "" then
        target.name = tostring(message.content):gsub("\n", " "):sub(1, 30)
        break
      end
    end
  end
  return persistConversations(candidate)
end

function _M.clear(id, path)
  return _M.save(id, {}, path, { __allow_empty = true, todos = {} })
end

function _M.rename(id, name, path)
  local cleanName = trim(name)
  if cleanName == "" then return false end
  local current = _M.load()
  local record, index = recordById(id, path, current)
  if not record then return false end
  local candidate = clone(current)
  candidate[index].name = cleanName
  candidate[index].updatedAt = now()
  return persistConversations(candidate)
end

function _M.delete(id, path)
  local expectedPath = projectPath(path)
  local current = _M.load()
  local record, index = recordById(id, expectedPath, current)
  if not record then return false end

  local selected = _M.current(expectedPath)
  local selectedId = selected and selected.id or nil
  local candidate = clone(current)
  table.remove(candidate, index)
  if not persistConversations(candidate) then return false end

  if selectedId == record.id then
    local replacement
    for itemIndex = #candidate, 1, -1 do
      if candidate[itemIndex].projectPath == expectedPath then
        replacement = candidate[itemIndex]
        break
      end
    end
    local map = clone(currentByProject or loadCurrentMap())
    if replacement then map[expectedPath] = replacement.id else map[expectedPath] = nil end
    currentByProject = map
    persistCurrentMap(map)
    if replacement then
      local _, replacementIndex = recordById(replacement.id, expectedPath, candidate)
      setData(CURRENT_ID_KEY, replacement.id)
      setData(LEGACY_CURRENT_INDEX_KEY, tostring(replacementIndex))
    else
      local currId = getData(CURRENT_ID_KEY, "")
      if currId == record.id then
        setData(CURRENT_ID_KEY, "")
        setData(LEGACY_CURRENT_INDEX_KEY, "0")
      end
    end
  end
  return true
end

function _M.getCurrentId(path)
  local record = _M.current(path)
  return record and record.id or nil
end

return _M
