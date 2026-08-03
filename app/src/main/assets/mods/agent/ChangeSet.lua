--- AI 文件变更事务：记录前后快照，并在恢复前校验 fingerprint。
local _M = {}
local config
local undoStack, redoStack = {}, {}
-- A transaction stores both before and after states inside a 4 MiB history.
local MAX_SNAPSHOT_BYTES = 1536 * 1024
local MAX_SNAPSHOT_FILES = 2000
local MAX_HISTORY = 10
local MAX_PERSISTED_BYTES = 4 * 1024 * 1024
local loaded = false
local restoreState

function _M.configure(options)
  config = options or {}
  local scope = config.scope and config.scope()
  if scope ~= _M._scope then
    loaded = false
    undoStack, redoStack = {}, {}
    _M._scope = scope
  end
end

local function cfg()
  if not config then error("ChangeSet 未配置") end
  return config
end

local function persist()
  local fs = cfg()
  if not fs.saveState then return true end
  while #undoStack > MAX_HISTORY do table.remove(undoStack, 1) end
  while #redoStack > MAX_HISTORY do table.remove(redoStack, 1) end
  local encoded
  while true do
    local ok, value = pcall(json.encode, { undo = undoStack, redo = redoStack })
    if not ok then return false, "撤销历史编码失败" end
    encoded = value
    if #encoded <= MAX_PERSISTED_BYTES then break end
    if #undoStack > 1 then
      table.remove(undoStack, 1)
    elseif #redoStack > 1 then
      table.remove(redoStack, 1)
    else
      return false, "撤销历史超过持久化上限"
    end
  end
  local ok, saved = pcall(fs.saveState, encoded)
  if not ok or saved ~= true then return false, "撤销历史写入失败" end
  return true
end

local function loadState()
  if loaded then return end
  loaded = true
  local fs = cfg()
  if not fs.loadState then return end
  local raw = fs.loadState()
  if not raw or raw == "" then return end
  local ok, state = pcall(json.decode, raw)
  if not ok or type(state) ~= "table" then return end
  if type(state.undo) == "table" then undoStack = state.undo end
  if type(state.redo) == "table" then redoStack = state.redo end
  local scope = cfg().scope and cfg().scope()
  if scope then
    local function keep(item) return type(item) == "table" and item.scope == scope end
    local filteredUndo, filteredRedo = {}, {}
    for _, item in ipairs(undoStack) do if keep(item) then filteredUndo[#filteredUndo + 1] = item end end
    for _, item in ipairs(redoStack) do if keep(item) then filteredRedo[#filteredRedo + 1] = item end end
    undoStack, redoStack = filteredUndo, filteredRedo
  end
  while #undoStack > MAX_HISTORY do table.remove(undoStack, 1) end
  while #redoStack > MAX_HISTORY do table.remove(redoStack, 1) end
end

local function fingerprint(content)
  if content == nil then return "missing" end
  local hash = 0
  for i = 1, #content do hash = (hash * 31 + content:byte(i)) % 2147483647 end
  return tostring(#content) .. ":" .. tostring(hash)
end

local function snapshot(path, stats)
  local fs = cfg()
  stats = stats or { bytes = 0, files = 0 }
  if not path or path == "" then return { path = path, kind = "missing", fingerprint = "missing" } end
  local kind, typeErr = fs.type(path)
  if typeErr then return nil, "无法识别文件类型: " .. tostring(path) end
  if kind == "file" then
    stats.files = stats.files + 1
    if stats.files > MAX_SNAPSHOT_FILES then return nil, "文件数量超过快照上限" end
    local content = fs.read(path)
    if content == nil then return nil, "无法读取文件快照: " .. tostring(path) end
    stats.bytes = stats.bytes + #content
    if stats.bytes > MAX_SNAPSHOT_BYTES then return nil, "快照大小超过上限" end
    return { path = path, kind = "file", content = content, fingerprint = fingerprint(content) }
  elseif kind == "dir" then
    local files = {}
    local dirs = {}
    local children = fs.listFiles(path)
    if type(children) ~= "table" then return nil, "无法读取目录快照: " .. tostring(path) end
    for _, child in ipairs(children) do
      local item, err = snapshot(child, stats)
      if not item then return nil, err end
      if item.kind == "file" then
        files[#files + 1] = item
      elseif item.kind == "dir" then
        dirs[#dirs + 1] = item.path
        for _, nestedDir in ipairs(item.dirs or {}) do dirs[#dirs + 1] = nestedDir end
        for _, nested in ipairs(item.files or {}) do files[#files + 1] = nested end
      end
    end
    table.sort(files, function(a, b) return a.path < b.path end)
    table.sort(dirs)
    return { path = path, kind = "dir", files = files, dirs = dirs,
      fingerprint = fingerprint(json.encode({ files = files, dirs = dirs })) }
  end
  return { path = path, kind = "missing", fingerprint = "missing" }
end

local function sameState(expected, actual)
  return expected.kind == actual.kind and expected.fingerprint == actual.fingerprint
end

local function collectPaths(name, args)
  local fs = cfg()
  local paths = {}
  local function add(path)
    if path and path ~= "" then paths[#paths + 1] = fs.resolve(path) end
  end
  if name == "rename_file" then add(args.path); add(args.new_path) else add(args.path) end
  return paths
end

function _M.begin(name, args)
  loadState()
  if not cfg().isTracked(name) then return nil end
  local stats = { bytes = 0, files = 0 }
  local paths = collectPaths(name, args or {})
  local before = {}
  for _, path in ipairs(paths) do
    local state, err = snapshot(path, stats)
    if not state then return nil, err or "无法创建文件快照" end
    before[#before + 1] = state
  end
  local addedBytes = #(tostring((args or {}).content or ""))
    + #(tostring((args or {}).patch or "")) + #(tostring((args or {}).new or ""))
  if stats.bytes + addedBytes > MAX_SNAPSHOT_BYTES then
    return nil, "变更内容超过可撤销大小上限"
  end
  local resolvedArgs = {}
  for key, value in pairs(args or {}) do resolvedArgs[key] = value end
  if paths[1] then resolvedArgs.path = paths[1] end
  if name == "rename_file" and paths[2] then resolvedArgs.new_path = paths[2] end
  return { name = name, scope = cfg().scope and cfg().scope(), paths = paths,
    before = before, args = resolvedArgs }
end

function _M.finish(transaction, result)
  loadState()
  if not transaction then return true end
  local currentScope = cfg().scope and cfg().scope()
  if transaction.scope ~= currentScope then
    local restored = true
    for index = #transaction.before, 1, -1 do
      if not restoreState(transaction.before[index]) then restored = false end
    end
    return false, restored and "项目已切换，文件操作已回滚" or "项目已切换，文件操作回滚失败"
  end
  local stats = { bytes = 0, files = 0 }
  local after = {}
  for _, path in ipairs(transaction.paths) do
    local state = snapshot(path, stats)
    if not state then
      local restored = true
      for index = #transaction.before, 1, -1 do
        if not restoreState(transaction.before[index]) then restored = false end
      end
      return false, restored and ("变更后快照失败，操作已回滚: " .. tostring(path))
        or ("变更后快照失败且回滚不完整: " .. tostring(path))
    end
    after[#after + 1] = state
  end
  transaction.after = after
  local changed = false
  for index, state in ipairs(after) do
    if not sameState(transaction.before[index], state) then changed = true break end
  end
  if not changed then return true end
  undoStack[#undoStack + 1] = transaction
  redoStack = {}
  local persisted, persistErr = persist()
  if not persisted then return true, persistErr end
  if not cfg().resultSucceeded(result) then
    return false, "操作报告失败，但检测到文件变化，已保留撤销记录"
  end
  return true
end

restoreState = function(state)
  local fs = cfg()
  if state.kind == "missing" then return fs.remove(state.path) end
  if state.kind == "file" then
    if fs.type(state.path) == "dir" and not fs.remove(state.path) then return false end
    if fs.ensureParent then fs.ensureParent(state.path) end
    return fs.write(state.path, state.content)
  end
  if state.kind == "dir" then
    if fs.type(state.path) == "file" and not fs.remove(state.path) then return false end
    if not fs.mkdir(state.path) and fs.type(state.path) ~= "dir" then return false end
    -- fingerprint 已经检查过当前目录，清空后按快照重建，避免嵌套目录残留文件。
    local children = fs.listFiles(state.path)
    if type(children) ~= "table" then return false end
    for _, child in ipairs(children) do
      if not fs.remove(child) then return false end
    end
    for _, dir in ipairs(state.dirs or {}) do
      if not fs.mkdir(dir) and fs.type(dir) ~= "dir" then return false end
    end
    for _, item in ipairs(state.files or {}) do
      if not fs.write(item.path, item.content) then return false end
    end
    return true
  end
  return false
end

local function apply(transaction, expectedKey, restoreKey)
  local current = {}
  for _, path in ipairs(transaction.paths) do
    local state = snapshot(path)
    if not state then return false, "无法创建恢复前快照: " .. tostring(path) end
    current[#current + 1] = state
  end
  local expected = transaction[expectedKey]
  for i, state in ipairs(current) do
    if not expected or not expected[i] or not sameState(expected[i], state) then
      return false, "文件已被外部修改，拒绝覆盖: " .. tostring(state.path)
    end
  end
  for i = #expected, 1, -1 do
    if not restoreState(transaction[restoreKey][i]) then
      -- A multi-path restore must not leave a partially applied transaction.
      local rolledBack = true
      for rollbackIndex = #current, 1, -1 do
        local rollbackOk, rollbackResult = pcall(restoreState, current[rollbackIndex])
        if not rollbackOk or rollbackResult ~= true then rolledBack = false end
      end
      return false, (rolledBack and "恢复文件失败，已回滚: " or "恢复文件失败且回滚不完整: ")
        .. tostring(transaction[restoreKey][i].path)
    end
  end
  return true
end

function _M.undo()
  loadState()
  local transaction = undoStack[#undoStack]
  if not transaction then return false, "没有可撤销的文件变更" end
  local ok, err = apply(transaction, "after", "before")
  if not ok then return false, err end
  undoStack[#undoStack] = nil
  redoStack[#redoStack + 1] = transaction
  local persisted, persistErr = persist()
  if not persisted then return true, "文件已撤销，但" .. tostring(persistErr) end
  return true, nil
end

function _M.redo()
  loadState()
  local transaction = redoStack[#redoStack]
  if not transaction then return false, "没有可恢复的文件变更" end
  local ok, err = apply(transaction, "before", "after")
  if not ok then return false, err end
  redoStack[#redoStack] = nil
  undoStack[#undoStack + 1] = transaction
  local persisted, persistErr = persist()
  if not persisted then return true, "文件已恢复，但" .. tostring(persistErr) end
  return true, nil
end

function _M.clear()
  undoStack, redoStack = {}, {}
  loaded = true
  if cfg().saveState then pcall(cfg().saveState, "") end
end

function _M.hasUndo() loadState(); return #undoStack > 0 end
function _M.hasRedo() loadState(); return #redoStack > 0 end

return _M
