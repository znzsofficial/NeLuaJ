local assets = ASSETS or "app/src/main/assets/"
package.path = assets .. "?.lua;" .. package.path
local KV = require "mods.utils.LuaKV"
local function ser(v)
  if type(v) == "table" then
    local out = {}
    for k, item in pairs(v) do out[#out + 1] = "[" .. ser(k) .. "]=" .. ser(item) end
    return "{" .. table.concat(out, ",") .. "}"
  end
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end
local function de(s) return assert(loadstring("return " .. s))() end
local root = (os.getenv("TEMP") or "/tmp"):gsub("\\", "/") .. "/rename_" .. os.time() .. "_" .. math.random(1000000)
local RealFile = luajava.bindClass("java.io.File")
KV.configure({ root = function() return root end, encode = ser, decode = de,
  ensureDir = function(path) return RealFile(path).mkdirs() or RealFile(path).isDirectory() end })
Bean = { Path = { app_root_pro_dir = "/Projects", agent_root_dir = "/agents", this_dir = "/Projects/A" } }
local Context = require "mods.project.ProjectContext"
local shared = {}
local CS = require "mods.agent.ConversationStore"
CS.configure({ encode = ser, decode = de,
  getData = function(k, d) if shared[k] ~= nil then return shared[k] end; return d end,
  setData = function(k, v) shared[k] = v; return true end })
local rec = assert(CS.create("kept", "/Projects/A"))
assert(CS.save(rec.id, { { role = "user", content = "original body" } }, "/Projects/A"))
local stale = assert(loadfile(assets .. "mods/agent/ConversationStore.lua"))()
stale.configure({ encode = ser, decode = de,
  getData = function(k, d) if shared[k] ~= nil then return shared[k] end; return d end,
  setData = function(k, v) shared[k] = v; return true end })
assert(#stale.load() == 1)
local sibling = assert(CS.create("sibling", "/Projects/A2"))
assert(CS.setCurrent(rec.id, "/Projects/A"))
assert(KV.set("workspace", "/Projects/A", { tabs = { "/Projects/A/main.lua" }, active = "/Projects/A/main.lua",
  cursors = { ["/Projects/A/main.lua"] = 17 }, select = 17 }))

-- Actual AgentStorage module with a narrow Java filesystem/hash bridge.
local disk = {}
local separateEditor
local function File(path, child)
  path = child and (path .. "/" .. child) or path
  return { exists = function() return disk[path] ~= nil end, isDirectory = function() return type(disk[path]) == "table" end,
    list = function() return disk[path] end, isFile = function() return type(disk[path]) == "string" end,
    getAbsolutePath = function() return path end, mkdirs = function() disk[path] = {}; return true end }
end
luajava = {
  bindClass = function(name)
    if name == "com.androlua.LuaActivity" then return { getActivity = function() return separateEditor end } end
    if name == "java.io.File" then return File end
    if name == "android.os.Environment" then return { getExternalStorageDirectory = function() return "/sdcard" end } end
    if name == "java.util.concurrent.locks.ReentrantLock" then return function() return { lock = function() end, unlock = function() end } end end
    if name == "java.security.MessageDigest" then return { getInstance = function() return { digest = function(text)
      local n = 0; for i = 1, #text do n = (n * 31 + text:byte(i)) % 251 end
      local bytes = {}; for i = 0, 11 do bytes[i] = (n + i) % 256 end; return bytes
    end } end } end
    return {}
  end,
  newInstance = function(_, text) return { getBytes = function() return text end } end,
}
local Storage = assert(loadfile(assets .. "mods/agent/AgentStorage.lua"))()
assert(Storage.configure("/Projects/A", "/agents"))
local originalDir = Storage.getProjectDir()
disk[originalDir] = { "todos.json" }
disk[originalDir .. "/todos.json"] = "kept agent state"
file = { readall = function(path) return disk[path] end }
local Service = require "mods.project.ProjectPersistence"
local exists = { ["/Projects/A"] = true }
local failRecent = true
local options = {
  exists = function(path) return exists[path] == true end,
  move = function(old, new) exists[old], exists[new] = nil, true; return "ok" end,
  conversations = CS, agentStorage = Storage,
  recent = { rename = function() if failRecent then return false, "injected_recent_failure" end; return true end },
}

-- A failed alias write must reject before the project directory is moved.
local realSet = KV.set
KV.set = function(ns, key, value) if ns == "agent_project_aliases" then return false end; return realSet(ns, key, value) end
local ok, detail = Service.rename("/Projects/A", "/Projects/B", options)
assert(not ok and detail.stage == "agent_storage" and detail.error == "agent_storage_alias_write_failed")
assert(exists["/Projects/A"] and not exists["/Projects/B"])
assert(KV.get("workspace", "/Projects/A").active == "/Projects/A/main.lua")
assert(CS.get(rec.id).projectPath == "/Projects/A")
print("PASS alias write failure rejects directory rename and preserves sources")
KV.set = realSet

-- A later metadata failure is partial but leaves the live directory in place.
ok, detail = Service.resumePending(options)
assert(not ok and detail.stage == "recent" and detail.path == "/Projects/A" and detail.retryable and not detail.completed)
assert(exists["/Projects/A"] and not exists["/Projects/B"])
assert(KV.get("project_migrations", "pending_rename").oldPath == "/Projects/A")
assert(KV.get("workspace", "/Projects/A").active == "/Projects/A/main.lua")
local ws = KV.get("workspace", "/Projects/B")
assert(ws.active == "/Projects/B/main.lua" and ws.tabs[1] == "/Projects/B/main.lua" and ws.cursors["/Projects/B/main.lua"] == 17)
assert(CS.get(rec.id).projectPath == "/Projects/B" and CS.get(sibling.id).projectPath == "/Projects/A2")
assert(CS.get(rec.id).messages[1].content == "original body")
assert(CS.current("/Projects/B").id == rec.id)
assert(KV.get("conversation_project_backups", "/Projects/A\n/Projects/B").records[1].projectPath == "/Projects/A")
assert(Storage.configure("/Projects/B", "/agents") and Storage.getProjectDir() == originalDir)
assert(Storage.read("todos.json") == "kept agent state")
print("PASS late failure reports partial result with preserved originals and pending journal")

-- Restart the service (no memory journal) and finish without duplicating data.
failRecent = false
Service = assert(loadfile(assets .. "mods/project/ProjectPersistence.lua"))()
ok, detail = Service.resumePending(options)
assert(ok and detail.stage == "complete" and not KV.exists("project_migrations", "pending_rename"))
assert(detail.completed and not exists["/Projects/A"] and exists["/Projects/B"])
assert(#CS.loadIndex(true) == 2)
assert(stale.save(rec.id, { { role = "user", content = "late save" } }, "/Projects/A"))
assert(CS.loadIndex(true)[1].projectPath == "/Projects/B")
assert(Storage.configure("/Projects/A", "/agents") and Storage.getProjectDir() == originalDir)
print("PASS restart resumes journal idempotently; old and new Agent paths retain original data")

-- Existing target storage is not overwritten or merged.
assert(Storage.configure("/Projects/C", "/agents"))
disk[Storage.getProjectDir()] = { "existing.json" }
local aliasOK, aliasError = Storage.reassociateProject("/Projects/A", "/Projects/C", "/agents")
assert(not aliasOK and aliasError == "agent_storage_conflict")
print("PASS existing target Agent storage is preserved as a conflict")

-- Conversation index failure after record writes is repaired by a retry.
local third = assert(CS.create("third", "/Projects/D"))
local realWrite = KV.writeAtomic
KV.writeAtomic = function(path, value)
  if path == root .. "/conversations/_index.json" then return false end
  return realWrite(path, value)
end
local movedOK, moveError = CS.reassociateProject("/Projects/D", "/Projects/E")
assert(not movedOK and moveError == "index_write_failed")
assert(KV.get("conversation_project_backups", "/Projects/D\n/Projects/E"))
KV.writeAtomic = realWrite
assert(CS.reassociateProject("/Projects/D", "/Projects/E"))
local found
for _, entry in ipairs(CS.loadIndex(true)) do if entry.id == third.id then found = entry.projectPath end end
assert(found == "/Projects/E")
print("PASS record/index split failure keeps backup and repairs index on retry")

local realDelete = KV.delete
exists["/Projects/G"] = true
KV.delete = function(ns, key)
  if ns == "project_migrations" and key == "pending_rename" then return false end
  return realDelete(ns, key)
end
ok, detail = Service.rename("/Projects/G", "/Projects/H", options)
assert(not ok and detail.stage == "journal_cleanup" and detail.completed and detail.path == "/Projects/H")
assert(exists["/Projects/H"] and not exists["/Projects/G"] and KV.exists("project_migrations", "pending_rename"))
KV.delete = realDelete
assert(Service.resumePending(options))
print("PASS final journal cleanup failure reports completed data migration but not false success")

-- Actual UI adapter rejects every editor reference before touching persistence.
local Menu = assert(loadfile(assets .. "mods/project/ProjectMenu.lua"))()
local saved = 0
package.loaded["mods.utils.EditorUtil"] = {
  currentFile = function() return "/Projects/B/main.lua" end,
  save = function() saved = saved + 1; return false end,
}
package.loaded["mods.utils.TabUtil"] = { Table = {} }
mLuaEditor = {}
Bean.Path.this_dir, Bean.Path.this_file = "/Projects", ""
local uiOK, uiDetail = Menu.renameProject("/Projects/B", "/Projects/F")
assert(not uiOK and uiDetail.error == "project_in_use" and uiDetail.stage == "editor")
assert(saved == 0 and not KV.exists("project_migrations", "pending_rename"))
package.loaded["mods.utils.EditorUtil"].currentFile = function() return "/Projects/Other/main.lua" end
package.loaded["mods.utils.TabUtil"].Table["/Projects/B/inactive.lua"] = {}
uiOK, uiDetail = Menu.renameProject("/Projects/B", "/Projects/F")
assert(not uiOK and uiDetail.error == "project_in_use" and saved == 0)
mLuaEditor = nil
Bean.Path.this_file = "/Projects/B/main.lua"
uiOK, uiDetail = Menu.renameProject("/Projects/B", "/Projects/F")
assert(not uiOK and uiDetail.error == "project_in_use" and not KV.exists("project_migrations", "pending_rename"))
Bean.Path.this_file = ""
separateEditor = { isFinishing = function() return false end, isDestroyed = function() return false end,
  equals = function() return false end }
uiOK, uiDetail = Menu.checkRenameAllowed("/Projects/B")
assert(not uiOK and uiDetail.error == "project_in_use")
assert(realSet("project_migrations", "pending_rename", { oldPath = "/Projects/B", newPath = "/Projects/F" }))
local journalPath = root .. "/project_migrations/pending_rename.json"
local realRename = os.rename
assert(realRename(journalPath, journalPath .. ".bak"))
os.rename = function() error("read-only pending must not restore its backup") end
local pending = assert(Service.pendingRename())
assert(pending.oldPath == "/Projects/B" and pending.newPath == "/Projects/F")
pending.oldPath = "/tampered"
assert(Service.pendingRename().oldPath == "/Projects/B")
uiOK, uiDetail = Menu.resumePendingRename()
assert(not uiOK and uiDetail.error == "project_in_use")
os.rename = realRename
assert(not RealFile(journalPath).exists() and RealFile(journalPath .. ".bak").exists())
assert(realRename(journalPath .. ".bak", journalPath))
assert(realDelete("project_migrations", "pending_rename"))
separateEditor.isFinishing = function() return true end
assert(Menu.checkRenameAllowed("/Projects/B"))
separateEditor.isFinishing = function() return false end
separateEditor.isDestroyed = function() return true end
assert(Menu.checkRenameAllowed("/Projects/B"))
separateEditor = nil
print("PASS active or inactive editor tabs reject rename before any save or directory operation")
print("PASS a live separate editor conservatively blocks rename; finishing or destroyed editors do not")
print("PASS pending introspection is detached/read-only including backups, and UI Retry is ownership-guarded")
print("ALL-PASS")
