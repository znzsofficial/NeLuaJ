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

-- Read-only migration audit. Never loads these records into the native undo
-- stack: the legacy rolling fingerprint is not a SHA-256 disk precondition.
function _M.inspectLegacy(raw, source, expectedScope, codec)
  local report={source=source,readOnly=true,imported=false,entries={},valid=false,
    reason='旧记录使用弱 fingerprint，缺少 native SHA-256 基线与持久 journal；当前无验证导入协议，不能安全成为可执行撤销历史'}
  if type(raw)~='string' or #raw>MAX_PERSISTED_BYTES then report.validationError='旧历史为空或超过 4 MiB 校验上限'; return report end
  local ok,state=pcall((codec or json).decode,raw)
  if not ok or type(state)~='table' or type(state.undo)~='table' or type(state.redo)~='table' then
    report.validationError='旧历史 JSON 或 undo/redo 结构无效'; return report
  end
  local function pathValid(path)
    return type(path)=='string' and path:sub(1,1)=='/' and not path:find('%z')
      and not path:find('/%.%./') and not path:match('/%.%.$')
  end
  local function snapshotValid(snapshot)
    if type(snapshot)~='table' or not pathValid(snapshot.path) or type(snapshot.fingerprint)~='string' then return false end
    if snapshot.kind=='missing' then return snapshot.fingerprint=='missing' end
    if snapshot.kind=='file' then
      if type(snapshot.content)~='string' then return false end
      if snapshot.encoding and snapshot.encoding~='base64' then return false end
      if snapshot.encoding=='base64' and (#snapshot.content%4~=0 or snapshot.content:find('[^%w%+/%=]')) then return false end
      local hash=0
      for i=1,#snapshot.content do hash=(hash*31+snapshot.content:byte(i))%2147483647 end
      return snapshot.fingerprint==tostring(#snapshot.content)..':'..tostring(hash)
    end
    if snapshot.kind~='dir' or type(snapshot.files)~='table' or type(snapshot.dirs)~='table' then return false end
    for _,child in ipairs(snapshot.files) do if not snapshotValid(child) or child.path:sub(1,#snapshot.path+1)~=snapshot.path..'/' then return false end end
    for _,dir in ipairs(snapshot.dirs) do if not pathValid(dir) or dir:sub(1,#snapshot.path+1)~=snapshot.path..'/' then return false end end
    return true -- directory fingerprint depends on the original JSON ordering
  end
  report.valid=true
  for _,direction in ipairs({'undo','redo'}) do
    for index,record in ipairs(state[direction]) do
      local valid=type(record)=='table' and type(record.id)=='string' and type(record.name)=='string'
        and type(record.scope)=='string' and type(record.before)=='table' and type(record.after)=='table'
      if valid then
        for _,snapshots in ipairs({record.before,record.after}) do
          for _,snapshot in ipairs(snapshots) do if not snapshotValid(snapshot) then valid=false end end
        end
      end
      report.entries[#report.entries+1]={direction=direction,index=index,id=type(record)=='table' and record.id or nil,
        name=type(record)=='table' and record.name or nil,scope=type(record)=='table' and record.scope or nil,
        path=type(record)=='table' and type(record.args)=='table' and record.args.path or nil,
        valid=valid==true,scopeMatches=type(record)=='table' and record.scope==expectedScope,
        reason=valid and report.reason or '记录字段、快照路径或内容 fingerprint 校验失败'}
      if not valid then report.valid=false end
    end
  end
  report.count=#report.entries
  return report
end

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
  if typeErr then return nil, "无法识别文件类型: " .. tostring(path) .. "\n原因: " .. tostring(typeErr) end
  if kind == "file" then
    stats.files = stats.files + 1
    if stats.files > MAX_SNAPSHOT_FILES then return nil, "文件数量超过快照上限" end
    local content, readError = (fs.readBinary or fs.read)(path)
    if content == nil then return nil, "无法读取文件快照: " .. tostring(path) .. "\n原因: " .. tostring(readError or "读取失败") end
    local size = #content
    if fs.readBinary then size = #content / 4 * 3 - #(content:match("=+$") or "") end
    stats.bytes = stats.bytes + size
    if stats.bytes > MAX_SNAPSHOT_BYTES then return nil, "快照大小超过上限" end
    return { path = path, kind = "file", content = content,
      encoding = fs.readBinary and "base64" or nil, fingerprint = fingerprint(content) }
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
  if kind ~= nil then return nil, "不支持的文件类型: " .. tostring(path) end
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
  return { name = name, id = tostring({}) .. ":" .. tostring(os.time()), scope = cfg().scope and cfg().scope(), paths = paths,
    before = before, args = resolvedArgs }
end

--- explicitOk 是执行器的结构化结果标志（true/false/nil）。nil 表示旧式工具
--- 未提供状态，此时回退到 resultSucceeded 文本前缀嗅探。
local function rollback(transaction)
  local restored = true
  for index = #transaction.before, 1, -1 do
    local ok, value = pcall(restoreState, transaction.before[index])
    if not ok or value ~= true then restored = false end
  end
  return restored
end

function _M.finish(transaction, result, explicitOk)
  loadState()
  if not transaction then return true end
  local currentScope = cfg().scope and cfg().scope()
  if transaction.scope ~= currentScope then
    local restored = rollback(transaction)
    return false, restored and "项目已切换，文件操作已回滚" or "项目已切换，文件操作回滚失败",
      { status = restored and "rolled_back" or "rollback_failed", paths = transaction.paths }
  end
  local stats = { bytes = 0, files = 0 }
  local after = {}
  for _, path in ipairs(transaction.paths) do
    local snapshotOk, state = pcall(snapshot, path, stats)
    if not snapshotOk or not state then
      local restored = rollback(transaction)
      return false, restored and ("变更后快照失败，操作已回滚: " .. tostring(path))
        or ("变更后快照失败且回滚不完整: " .. tostring(path)),
        { status = restored and "rolled_back" or "rollback_failed", paths = transaction.paths }
    end
    after[#after + 1] = state
  end
  transaction.after = after
  local changed = false
  for index, state in ipairs(after) do
    if not sameState(transaction.before[index], state) then changed = true break end
  end
  local succeeded = explicitOk
  if succeeded == nil then succeeded = cfg().resultSucceeded(result) end
  if not changed then return succeeded == true, nil, { status = "unchanged", paths = transaction.paths } end
  undoStack[#undoStack + 1] = transaction
  redoStack = {}
  local persisted, persistErr = persist()
  if not succeeded then
    return false, "操作报告失败，但检测到文件变化，已保留撤销记录"
      .. (persistErr and ("；" .. persistErr) or ""),
      { status = "operation_failed", historyPersisted = persisted, paths = transaction.paths }
  end
  return true, persistErr, { status = "committed", historyPersisted = persisted, paths = transaction.paths }
end

local function writeSnapshot(state)
  local fs = cfg()
  if state.encoding == "base64" then
    if not fs.writeBinary then return false end
    return fs.writeBinary(state.path, state.content)
  end
  return fs.write(state.path, state.content)
end

restoreState = function(state)
  local fs = cfg()
  if state.kind == "missing" then return fs.remove(state.path) end
  local kind, typeErr = fs.type(state.path)
  if typeErr then return false end
  if state.kind == "file" then
    if kind == "dir" and not fs.remove(state.path) then return false end
    if fs.ensureParent then fs.ensureParent(state.path) end
    return writeSnapshot(state)
  end
  if state.kind == "dir" then
    if kind == "file" and not fs.remove(state.path) then return false end
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
      if not writeSnapshot(item) then return false end
    end
    return true
  end
  return false
end

local function apply(transaction, expectedKey, restoreKey)
  local current = {}
  for _, path in ipairs(transaction.paths) do
    local snapshotOk, state, snapshotError = pcall(snapshot, path)
    if not snapshotOk or not state then
      return false, "无法创建恢复前快照: " .. tostring(path) .. "\n原因: " .. tostring(snapshotOk and snapshotError or state)
    end
    current[#current + 1] = state
  end
  local expected = transaction[expectedKey]
  for i, state in ipairs(current) do
    if not expected or not expected[i] or not sameState(expected[i], state) then
      return false, "文件已被外部修改，拒绝覆盖: " .. tostring(state.path)
    end
  end
  for i = #expected, 1, -1 do
    local restoreOk, restored = pcall(restoreState, transaction[restoreKey][i])
    if not restoreOk or restored ~= true then
      -- A multi-path restore must not leave a partially applied transaction.
      local rolledBack = true
      for rollbackIndex = #current, 1, -1 do
        local rollbackOk, rollbackResult = pcall(restoreState, current[rollbackIndex])
        if not rollbackOk or rollbackResult ~= true then rolledBack = false end
      end
      return false, (rolledBack and "恢复文件失败，已回滚: " or "恢复文件失败且回滚不完整: ")
        .. tostring(transaction[restoreKey][i].path),
        { status = rolledBack and "rolled_back" or "rollback_failed", paths = transaction.paths }
    end
  end
  return true
end

function _M.undo(expected)
  loadState()
  local transaction = undoStack[#undoStack]
  if not transaction then return false, "没有可撤销的文件变更" end
  if transaction.scope ~= (cfg().scope and cfg().scope()) then return false, "项目已切换" end
  if expected and (expected.id ~= transaction.id or expected.scope ~= transaction.scope
      or expected.scope ~= (cfg().scope and cfg().scope())) then return false, "项目或撤销记录已切换" end
  local ok, err, effects = apply(transaction, "after", "before")
  if not ok then return false, err, effects end
  undoStack[#undoStack] = nil
  redoStack[#redoStack + 1] = transaction
  local persisted, persistErr = persist()
  if not persisted then return true, "文件已撤销，但" .. tostring(persistErr) end
  return true, nil
end

function _M.redo(expected)
  loadState()
  local transaction = redoStack[#redoStack]
  if not transaction then return false, "没有可恢复的文件变更" end
  if transaction.scope ~= (cfg().scope and cfg().scope()) then return false, "项目已切换" end
  if expected and (expected.id ~= transaction.id or expected.scope ~= transaction.scope
      or expected.scope ~= (cfg().scope and cfg().scope())) then return false, "项目或恢复记录已切换" end
  local ok, err, effects = apply(transaction, "before", "after")
  if not ok then return false, err, effects end
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

local function peek(stack)
  local transaction = stack[#stack]
  if not transaction then return nil end
  local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
  end
  -- Older persisted history acquires a stable identity on its first peek.
  transaction.id = transaction.id or (tostring({}) .. ":" .. tostring(os.time()))
  return { name = transaction.name, args = copy(transaction.args), scope = transaction.scope, id = transaction.id }
end
function _M.peekUndo() loadState(); return peek(undoStack) end
function _M.peekRedo() loadState(); return peek(redoStack) end

return _M
