--- Actual open history, shared by home/editor Lua states. No directory mtime inference.
local KV = require "mods.utils.LuaKV"
local M = {}
local NS, KEY = "home", "recent-projects"
local function normalize(path)
  return tostring(path or ""):gsub("\\", "/"):gsub("/+", "/"):gsub("/$", "")
end
local function now()
  local ok, value = pcall(function() return luajava.bindClass("java.lang.System").currentTimeMillis() end)
  return ok and tonumber(value) or os.time() * 1000
end
function M.list()
  local raw, readError = KV.read(KV.nsPath(NS) .. "/" .. KEY .. ".json")
  if raw == nil and readError and readError ~= "missing" then return {}, readError end
  local saved = KV.get(NS, KEY)
  if type(saved) ~= "table" and (saved ~= nil or raw ~= nil or KV.exists(NS, KEY)) then
    return {}, "recent_corrupt"
  end
  local out = {}
  for index, row in ipairs(type(saved) == "table" and saved or {}) do
    if type(row) ~= "table" then return {}, "recent_corrupt" end
    local path = normalize(row.path)
    if path ~= "" then out[#out + 1] = { path = path, openedAt = tonumber(row.openedAt) or 0, order = index } end
  end
  table.sort(out, function(a, b)
    if a.openedAt == b.openedAt then return a.order < b.order end
    return a.openedAt > b.openedAt
  end)
  for _, row in ipairs(out) do row.order = nil end
  return out
end
function M.record(path, openedAt)
  path = normalize(path)
  if path == "" then return false end
  local out = { { path = path, openedAt = tonumber(openedAt) or now() } }
  local rows, readError = M.list()
  if readError then return false, readError end
  for _, row in ipairs(rows) do
    if row.path ~= path and #out < 30 then out[#out + 1] = row end
  end
  if KV.set(NS, KEY, out) == true then return true end
  return false, "recent_write_failed"
end
--- Idempotent migration: preserve latest timestamp, merge an existing destination.
function M.rename(oldPath, newPath)
  oldPath, newPath = normalize(oldPath), normalize(newPath)
  if oldPath == "" or newPath == "" then return false end
  if oldPath == newPath then return true end
  local rows, readError = M.list()
  if readError then return false, readError end
  local merged, changed = {}, false
  for _, row in ipairs(rows) do
    local path = row.path
    if path == oldPath then path, changed = newPath, true end
    merged[path] = math.max(merged[path] or 0, row.openedAt)
  end
  if not changed then return true end
  local out = {}
  for path, time in pairs(merged) do out[#out + 1] = { path = path, openedAt = time } end
  table.sort(out, function(a, b) return a.openedAt > b.openedAt end)
  if KV.set(NS, KEY, out) == true then return true end
  return false, "recent_write_failed"
end
return M
