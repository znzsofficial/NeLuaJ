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

-- 会话按记录存储（LuaKV）：每会话一个记录文件 + 元数据索引，
-- 一次工具轮保存只写当前会话，不再整包重写
local KV = require("mods.utils.LuaKV")
local TextUtil = require("mods.utils.TextUtil")
local CONV_KV_NS = "conversations"
local maxSeq = 0
local kvReady = false
local loadError

local function ensureKV()
  if kvReady then return true end
  if not KV.isConfigured() then
    KV.configure({
      root = function()
        return (Bean and Bean.Path and Bean.Path.agent_root_dir or "/sdcard/LuaJ/agents") .. "/kv"
      end,
    })
  end
  kvReady = KV.isConfigured()
  return kvReady
end

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
    if not used[value] and value ~= "_index" and value ~= "_legacy_migration" then return value end
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
  if id == "" or used[id] or id == "_index" or id == "_legacy_migration" then
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

--- 磁盘索引是成员名单。别的界面已经删掉的 id 不能再写回去；
--- 磁盘上有、这份内存里没有的会话要留在索引里，避免整表覆盖把它们抹掉。
local function readDiskIndex()
  if not ensureKV() then return nil, "storage_unavailable" end
  local raw, readError = KV.read(KV.nsPath(CONV_KV_NS) .. "/_index.json")
  if raw == nil then
    return nil, (readError and readError ~= "missing") and "index_read_failed" or "index_missing"
  end
  if type(raw) ~= "string" or raw == "" then return nil, "index_corrupt" end
  local decoded = decode(raw)
  if type(decoded) ~= "table" then return nil, "index_corrupt" end
  local ids = {}
  local entries = {}
  local count = 0
  for key in pairs(decoded) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return nil, "index_corrupt" end
    count = count + 1
  end
  if count ~= #decoded then return nil, "index_corrupt" end
  for _, entry in ipairs(decoded) do
    if type(entry) == "table" and entry.id ~= nil and tostring(entry.id) ~= "" and entry.messages == nil then
      local id = tostring(entry.id)
      if not ids[id] then
        ids[id] = true
        entries[#entries + 1] = entry
      else return nil, "index_corrupt" end
    else return nil, "index_corrupt" end
  end
  return { ids = ids, entries = entries }
end

local function idSet(list)
  local set = {}
  for _, id in ipairs(list or {}) do
    set[tostring(id)] = true
  end
  return set
end

--- 按记录持久化：每个会话一个 KV 记录 + 重写元数据索引。
--- removedIds 会删记录文件；createdIds 是这次新出现、磁盘索引里还没有的 id。
local function persistConversations(value, removedIds, createdIds, migrating, reassociating)
  if loadError and not migrating then return false, loadError end
  if not ensureKV() then return false end
  local root = KV.nsPath(CONV_KV_NS)
  local removedSet = idSet(removedIds)
  local createdSet = idSet(createdIds)
  local disk, diskError = readDiskIndex()
  if not disk and diskError ~= "index_missing" then return false, diskError end
  local diskPaths = {}
  for _, entry in ipairs(disk and disk.entries or {}) do diskPaths[tostring(entry.id)] = entry.projectPath end
  local kept = {}
  local seen = {}
  for _, record in ipairs(value) do
    local id = tostring(record.id)
    if not removedSet[id] and not seen[id] then
      -- 索引还留着、记录文件已经没了：这是一次没写完的删除，不要从内存恢复。
      local fileGone = disk and disk.ids[id] and not createdSet[id] and not KV.exists(CONV_KV_NS, id)
      if not fileGone and (not disk or disk.ids[id] or createdSet[id]) then
        -- A stale editor may still hold the pre-rename path. Only the explicit
        -- reassociation service may change ownership of an existing record.
        if not migrating and not reassociating and diskPaths[id] ~= nil then
          record.projectPath = diskPaths[id]
        end
        seen[id] = true
        kept[#kept + 1] = record
      end
    end
  end

  local ok = true
  local writeError
  local written = {}
  local indexEntries = {}
  local preserved = {}
  for _, record in ipairs(kept) do
    if record.seq == nil then
      maxSeq = maxSeq + 1
      record.seq = maxSeq
    end
    if record.seq > maxSeq then maxSeq = record.seq end
    local id = tostring(record.id)
    if KV.set(CONV_KV_NS, id, record) then
      written[id] = true
      indexEntries[#indexEntries + 1] = {
        id = id,
        name = record.name,
        projectPath = record.projectPath,
        createdAt = record.createdAt,
        updatedAt = record.updatedAt,
        messageCount = type(record.messages) == "table" and #record.messages or 0,
        usage = record.usage,
        seq = record.seq,
      }
    else
      ok = false
      writeError = writeError or ("record_write_failed:" .. id)
    end
  end
  if disk then
    for _, entry in ipairs(disk.entries) do
      local id = tostring(entry.id)
      -- 内存没写上的，沿用磁盘索引。已删除的不再列入。
      if not written[id] and not removedSet[id] and KV.exists(CONV_KV_NS, id) then
        indexEntries[#indexEntries + 1] = entry
        local record = KV.get(CONV_KV_NS, id)
        if type(record) == "table" then
          preserved[#preserved + 1] = record
        end
      end
    end
  end
  -- 记录文件还在时不能先改索引，否则列表里没了、json 还留在目录里。
  for _, id in ipairs(removedIds or {}) do
    if not KV.delete(CONV_KV_NS, tostring(id)) then
      return false, "record_delete_failed:" .. tostring(id)
    end
  end
  local encodedIndex = encode(indexEntries)
  if not ok then return false, writeError end
  if not encodedIndex then return false, "index_encode_failed" end
  if not KV.writeAtomic(root .. "/_index.json", encodedIndex) then return false, "index_write_failed" end
  local cached = {}
  for _, record in ipairs(kept) do
    if written[tostring(record.id)] then
      cached[#cached + 1] = record
    end
  end
  for _, record in ipairs(preserved) do
    cached[#cached + 1] = record
  end
  conversations = cached
  return ok
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
  loadError = nil
end

--- 是否已被宿主配置过（首页等只读方避免重复 configure 清缓存）
function _M.isConfigured()
  return cfg().getData ~= nil
end

function _M.invalidate()
  conversations = nil
  currentByProject = nil
  loadError = nil
end

function _M.load(force)
  if conversations and not force and not loadError then return clone(conversations) end

  local source = {}
  local fromLegacy = false
  loadError = nil
  local disk, diskError = readDiskIndex()
  local legacyRaw = getData(CONVERSATIONS_KEY, "")
  -- Until the source has been cleared, ALWAYS retry the entire legacy batch.
  -- An index from a previous interrupted attempt is not a completion marker.
  if type(legacyRaw) == "string" and legacyRaw ~= "" then
    local decoded = decode(legacyRaw)
    if type(decoded) ~= "table" then loadError = "legacy_corrupt"; return {}, loadError end
    source = decoded.id and { decoded } or decoded
    local count = 0
    for key, value in pairs(source) do
      if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or type(value) ~= "table" then
        loadError = "legacy_corrupt"; return {}, loadError
      end
      count = count + 1
    end
    if count ~= #source then loadError = "legacy_corrupt"; return {}, loadError end
    fromLegacy = true
  elseif not disk and diskError ~= "index_missing" then
    loadError = diskError
    return {}, loadError
  elseif disk then
    for _, entry in ipairs(disk.entries) do
      local record = KV.get(CONV_KV_NS, tostring(entry.id))
      if type(record) == "table" then source[#source + 1] = record
      elseif KV.exists(CONV_KV_NS, tostring(entry.id)) then
        loadError = "record_corrupt:" .. tostring(entry.id)
        return {}, loadError
      end -- Missing records are interrupted deletions, never resurrect them.
    end
  end

  local fallbackProject = projectPath(nil)
  local used = {}
  local normalized = {}
  local migrated = fromLegacy
  for _, value in ipairs(source) do
    local record, changed = normalizeRecord(value, fallbackProject, used)
    if record then
      normalized[#normalized + 1] = record
      if changed then migrated = true end
    else
      migrated = true
    end
  end

  -- 稳定顺序：seq 缺失按位置补齐后排序，保持旧数组语义
  for index, record in ipairs(normalized) do
    if record.seq == nil then record.seq = index end
  end
  table.sort(normalized, function(a, b) return (a.seq or 0) < (b.seq or 0) end)
  maxSeq = 0
  for _, record in ipairs(normalized) do
    if (record.seq or 0) > maxSeq then maxSeq = record.seq end
  end

  if fromLegacy then
    -- Persist normalized IDs before any record writes, so retries/restarts cannot
    -- generate different IDs for legacy rows which did not have one.
    local journal = KV.get(CONV_KV_NS, "_legacy_migration")
    if (journal == nil and KV.exists(CONV_KV_NS, "_legacy_migration"))
        or (journal and (type(journal) ~= "table" or type(journal.records) ~= "table")) then
      loadError = "legacy_journal_corrupt"
    elseif journal and journal.source == legacyRaw then
      local ids, count, valid = {}, 0, #journal.records == #source
      for key, record in pairs(journal.records) do
        count = count + 1
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or type(record) ~= "table"
            or type(record.id) ~= "string" or record.id == "" or ids[record.id]
            or type(record.messages) ~= "table" or type(record.projectPath) ~= "string" then
          valid = false
        elseif record then ids[record.id] = true end
      end
      if count ~= #source then valid = false end
      if valid then normalized = journal.records else loadError = "legacy_journal_corrupt" end
    elseif not KV.set(CONV_KV_NS, "_legacy_migration", { source = legacyRaw, records = normalized }) then
      loadError = "legacy_journal_write_failed"
    end
  end

  conversations = normalized
  currentByProject = loadCurrentMap()
  if migrateLegacySelection(conversations, currentByProject) then
    persistCurrentMap(currentByProject)
  end
  if (migrated or fromLegacy) and not loadError then
    -- 规范化时新分配的 id 还不在磁盘索引里，要明确标成新建，避免被当成“别的界面已删除”。
    local created = nil
    local diskNow = readDiskIndex()
    if fromLegacy then
      -- Every source row must be written, even if an interrupted/older migration
      -- left an index entry without its record. This is not a stale editor save.
      created = {}
      for _, record in ipairs(normalized) do created[#created + 1] = record.id end
    elseif diskNow then
      created = {}
      for _, record in ipairs(normalized) do
        if not diskNow.ids[tostring(record.id)] then
          created[#created + 1] = record.id
        end
      end
    end
    local saved, saveError = persistConversations(normalized, nil, created, true)
    if not saved then loadError = saveError or (fromLegacy and "legacy_persist_failed" or "normalization_persist_failed") end
  end
  if fromLegacy and not loadError then
    -- 记录已落 KV，清除 SharedData 旧整包（迁移完成标记）
    if not setData(CONVERSATIONS_KEY, nil) then
      loadError = "legacy_cleanup_failed"
    else
      -- A leftover journal is harmless: it is used only with the matching source.
      KV.delete(CONV_KV_NS, "_legacy_migration")
    end
  end
  return clone(conversations), loadError
end

--- 轻量索引：仅提取记录的标量元数据，不深拷贝 messages。
--- 会话列表渲染（首页会话 tab）只需要元信息，全量 load 的深克隆
--- 在会话较多时是列表卡顿的主因。
function _M.loadIndex(force)
  local legacyRaw = getData(CONVERSATIONS_KEY, "")
  if type(legacyRaw) == "string" and legacyRaw ~= "" then
    local _, migrationError = _M.load(true)
    if migrationError then return {}, migrationError end
  end
  -- Do not call load() on the ordinary path, including force=true: the index
  -- already contains all list metadata, and message bodies need not be opened.
  local disk, diskError = readDiskIndex()
  if not disk then
    if diskError == "index_missing" then return {} end
    return {}, diskError
  end
  local result = {}
  local ordered = {}
  for i, entry in ipairs(disk.entries) do ordered[i] = entry end
  table.sort(ordered, function(a, b) return (tonumber(a.seq) or 0) < (tonumber(b.seq) or 0) end)
  for _, record in ipairs(ordered) do
    local usage = type(record.usage) == "table" and clone(record.usage) or nil
    result[#result + 1] = {
      id = record.id,
      name = record.name,
      projectPath = record.projectPath,
      createdAt = record.createdAt,
      updatedAt = record.updatedAt,
      usage = usage,
      messageCount = tonumber(record.messageCount) or 0,
    }
  end
  return result
end

--- Idempotent path reassociation, not an all-files transaction. Message bodies
--- and IDs are unchanged. On failure old source data must be kept by the caller.
function _M.reassociateProject(oldPath, newPath)
  oldPath, newPath = projectPath(oldPath), projectPath(newPath)
  if oldPath == "" or newPath == "" then return false, "invalid_project_path" end
  if oldPath == newPath then return true end
  local function moved(path)
    path = tostring(path or "")
    if path == oldPath or path:sub(1, #oldPath + 1) == oldPath .. "/" then
      return newPath .. path:sub(#oldPath + 1)
    end
    return path
  end
  local records, err = _M.load(true)
  if err then return false, err end
  local rawMap = getData(CURRENT_BY_PROJECT_KEY, "")
  if rawMap ~= "" and type(decode(rawMap)) ~= "table" then return false, "current_map_corrupt" end
  local map = loadCurrentMap()
  local updated = clone(map)
  for path, id in pairs(map) do
    local target = moved(path)
    if target ~= path then
      if updated[target] and updated[target] ~= id then return false, "current_project_conflict" end
      updated[target], updated[path] = id, nil
    end
  end
  local backupKey = oldPath .. "\n" .. newPath
  local backup = KV.get("conversation_project_backups", backupKey)
  if backup ~= nil then
    if type(backup) ~= "table" or type(backup.records) ~= "table" or type(backup.current) ~= "table" then
      return false, "conversation_backup_corrupt"
    end
  elseif KV.exists("conversation_project_backups", backupKey) then
    return false, "conversation_backup_corrupt"
  elseif not KV.set("conversation_project_backups", backupKey, { records = records, current = map }) then
    return false, "conversation_backup_write_failed"
  end
  local changed = false
  for _, record in ipairs(records) do
    local path = moved(record.projectPath)
    if path ~= record.projectPath then record.projectPath = path; changed = true end
  end
  -- Also repair an index left behind after record writes in an earlier attempt.
  if changed or #records > 0 then
    local saved, saveError = persistConversations(records, nil, nil, false, true)
    if not saved then return false, saveError or "conversation_reassociate_failed" end
  end
  if not persistCurrentMap(updated) then return false, "current_map_write_failed" end
  return true
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
  if not persistConversations(candidate, nil, { record.id }) then return nil, 0 end

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
        target.name = TextUtil.utf8Cap(tostring(message.content):gsub("\n", " "), 30)
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
  if not persistConversations(candidate, { record.id }) then return false end

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
