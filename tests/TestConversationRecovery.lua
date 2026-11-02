local assets = ASSETS or "app/src/main/assets/"
package.path = assets .. "?.lua;" .. package.path
local KV = require "mods.utils.LuaKV"
local function ser(value)
  if type(value) == "table" then
    local out = {}
    for k, v in pairs(value) do out[#out + 1] = "[" .. ser(k) .. "]=" .. ser(v) end
    return "{" .. table.concat(out, ",") .. "}"
  end
  if type(value) == "string" then return string.format("%q", value) end
  return tostring(value)
end
local function de(text) return assert(loadstring("return " .. text))() end
local base = (os.getenv("TEMP") or "/tmp"):gsub("\\", "/") .. "/conv_recovery_" .. os.time() .. "_" .. math.random(1000000)
local realSet, realWrite, realGet = KV.set, KV.writeAtomic, KV.get
local root, shared, options
local function fresh(name, legacy)
  root = base .. "_" .. name
  KV.configure({ root = function() return root end, encode = ser, decode = de })
  shared = { ai_conversations = legacy and ser(legacy) }
  options = { getData = function(k, d) if shared[k] ~= nil then return shared[k] end; return d end,
    setData = function(k, v) shared[k] = v; return true end, encode = ser, decode = de,
    getProjectPath = function() return "/Projects/A" end }
  local store = assert(loadfile(assets .. "mods/agent/ConversationStore.lua"))()
  store.configure(options)
  return store
end
local function restart()
  local store = assert(loadfile(assets .. "mods/agent/ConversationStore.lua"))()
  store.configure(options)
  return store
end
local function legacy()
  return { { name = "first", projectPath = "/Projects/A", messages = { { role = "user", content = "kept" } } },
    { id = "second", name = "second", projectPath = "/Projects/A", messages = {} } }
end

for _, failure in ipairs({ "record", "index" }) do
  local cs = fresh(failure, legacy())
  KV.set = function(ns, key, value)
    if failure == "record" and ns == "conversations" and key == "second" then return false end
    return realSet(ns, key, value)
  end
  KV.writeAtomic = function(path, value)
    if failure == "index" and path == root .. "/conversations/_index.json" then return false end
    return realWrite(path, value)
  end
  local rows, err = cs.load(true)
  local expected = failure == "record" and "record_write_failed:second" or "index_write_failed"
  assert(#rows == 2 and err == expected, failure .. ": " .. tostring(err) .. " rows=" .. #rows)
  local firstId = rows[1].id
  assert(shared.ai_conversations ~= nil)
  local again, forceError = cs.load(true)
  assert(forceError and again[1].id == firstId and #again == 2)
  local restarted, restartError = restart().load(true)
  assert(restartError and #restarted == 2 and restarted[1].id == firstId)
  KV.set, KV.writeAtomic = realSet, realWrite
  local recovered = restart()
  local all, successError = recovered.load(true)
  assert(not successError and #all == 2 and all[1].id == firstId)
  assert(shared.ai_conversations == nil and #recovered.loadIndex(true) == 2)
  print("PASS legacy " .. failure .. " failure preserves source and stable IDs across force/restart")
end

-- Simulate a pre-existing partial index (also covers older broken migrations).
local cs = fresh("partial_index", legacy())
assert(realSet("conversations", "second", legacy()[2]))
assert(realWrite(root .. "/conversations/_index.json", ser({ { id = "second", name = "second" } })))
local all, err = cs.load(true)
assert(not err and #all == 2 and shared.ai_conversations == nil)
print("PASS partial index never hides the remaining legacy records")

cs = fresh("indexed_missing_record", legacy())
assert(realWrite(root .. "/conversations/_index.json", ser({ { id = "second", name = "second" } })))
local restored, restoreError = cs.load(true)
assert(not restoreError and #restored == 2 and KV.exists("conversations", "second") and not shared.ai_conversations)
print("PASS legacy migration writes indexed-but-missing records instead of dropping source rows")

-- Lightweight forced reads must not touch record bodies, even with no cache.
cs = restart()
local bodyReads = 0
KV.get = function(ns, key, fallback)
  if ns == "conversations" then bodyReads = bodyReads + 1; error("message body loaded") end
  return realGet(ns, key, fallback)
end
local index, indexError = cs.loadIndex(true)
assert(not indexError and #index == 2 and bodyReads == 0 and index[1].messages == nil)
index[1].name = "changed"
assert(cs.loadIndex(true)[1].name ~= "changed")
KV.get = realGet
print("PASS forced lightweight index reads open zero message records and isolate metadata")

assert(realWrite(root .. "/conversations/_index.json", "broken"))
local broken, brokenError = cs.loadIndex(true)
assert(#broken == 0 and brokenError == "index_corrupt")
assert(cs.create("must not overwrite", "/Projects/A") == nil)
print("PASS corrupt index reports failure and blocks destructive replacement")

local realRead = KV.read
KV.read = function(path)
  if path == root .. "/conversations/_index.json" then return nil, "read_failed" end
  return realRead(path)
end
local unreadable, readError = cs.loadIndex(true)
assert(#unreadable == 0 and readError == "index_read_failed")
KV.read = realRead
print("PASS index I/O failure is not reported as an empty success")

cs = fresh("journal_failure", legacy())
KV.set = function(ns, key, value)
  if ns == "conversations" and key == "_legacy_migration" then return false end
  return realSet(ns, key, value)
end
local pending, journalError = cs.load(true)
assert(#pending == 2 and journalError == "legacy_journal_write_failed" and shared.ai_conversations)
assert(not KV.exists("conversations", "second"))
KV.set = realSet
assert(#restart().load(true) == 2 and not shared.ai_conversations)
print("PASS journal failure prevents record writes and retains the full source")

cs = fresh("invalid_legacy")
shared.ai_conversations = "not valid data"
local invalid, invalidError = cs.load(true)
assert(#invalid == 0 and invalidError == "legacy_corrupt" and shared.ai_conversations == "not valid data")
assert(cs.create("must not replace source", "/Projects/A") == nil)
print("PASS invalid legacy data remains intact and returns an explicit error")

cs = fresh("cleanup_failure", legacy())
local normalSetter = options.setData
options.setData = function(k, v) if k == "ai_conversations" then return false end; return normalSetter(k, v) end
local kept, cleanupError = cs.load(true)
assert(#kept == 2 and cleanupError == "legacy_cleanup_failed" and shared.ai_conversations)
options.setData = normalSetter
assert(#restart().load(true) == 2 and shared.ai_conversations == nil)
print("PASS source cleanup failure is retryable after records and index commit")

-- Existing stale-view deletion protection remains in effect.
cs = fresh("multi_view")
local one = assert(cs.create("one", "/Projects/A"))
assert(cs.save(one.id, { { role = "user", content = "one" } }, "/Projects/A"))
local other = restart()
assert(#other.load() == 1)
local two = assert(cs.create("two", "/Projects/A"))
assert(other.rename(one.id, "renamed", "/Projects/A"))
assert(#cs.loadIndex(true) == 2)
assert(cs.delete(one.id, "/Projects/A"))
assert(other.save(one.id, { { role = "user", content = "stale" } }, "/Projects/A"))
local final = cs.loadIndex(true)
assert(#final == 1 and final[1].id == two.id and not KV.exists("conversations", one.id))
print("PASS stale view preserves foreign creates and cannot resurrect deletion")
print("ALL-PASS")
