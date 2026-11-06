local ASSETS = ASSETS or "app/src/main/assets/"
local function encode(value)
  if type(value) == "string" then return string.format("%q", value) end
  if type(value) ~= "table" then return tostring(value) end
  local keys, parts = {}, {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, key in ipairs(keys) do parts[#parts + 1] = "[" .. encode(key) .. "]=" .. encode(value[key]) end
  return "{" .. table.concat(parts, ",") .. "}"
end
json = { encode = encode, decode = function(s) return assert(loadstring("return " .. s))() end }
local ChangeSet = assert(loadfile(ASSETS .. "mods/agent/ChangeSet.lua"))()
-- Legacy snapshot format remains covered for the explicit migration path.
-- It is no longer a ToolExecutor transaction adapter.
local files, scope, saved, failSave, failRead, failRestore, action
local binary = string.char(0, 255, 128, 65)
local function toBase64(s)
  if s == binary then return "AP+AQQ==" end
  if s == "new" then return "bmV3" end
  if s == "old" then return "b2xk" end
  error("unexpected fixture bytes")
end
local function fromBase64(s)
  return assert(({ ["AP+AQQ=="] = binary, bmV3 = "new", b2xk = "old" })[s])
end
local function configure()
  ChangeSet.configure({
    scope = function() return scope end,
    resolve = function(p) return p end,
    type = function(p)
      if p == "/denied" then return nil, "access denied" end
      return files[p] and (files[p] == true and "dir" or "file") or nil
    end,
    readBinary = function(p) if failRead then return nil end; return toBase64(files[p]) end,
    writeBinary = function(p, s) if failRestore then return false end; files[p] = fromBase64(s); return true end,
    read = function() error("text reader must never handle snapshots") end,
    write = function() error("text writer must never handle binary snapshots") end,
    listFiles = function(p)
      local list = {}
      for path in pairs(files) do
        if path:sub(1, #p + 1) == p .. "/" and not path:sub(#p + 2):find("/", 1, true) then list[#list + 1] = path end
      end
      return list
    end,
    mkdir = function(p) files[p] = true; return true end,
    remove = function(p)
      if failRestore then return false end
      for path in pairs(files) do if path == p or path:sub(1, #p + 1) == p .. "/" then files[path] = nil end end
      return true
    end,
    isTracked = function() return true end,
    resultSucceeded = function(r) return r == "done" end,
    saveState = function(s) saved = s; return not failSave end,
    loadState = function() return saved end,
  })
end
local function reset()
  files, scope, saved = {}, "/project", nil
  failSave, failRead, failRestore = false, false, false
  configure(); ChangeSet.clear()
end
local function run(name, args, fn)
  local transaction, err = ChangeSet.begin(name,args)
  if err then return tostring(err),false end
  local called,text,ok=pcall(fn,name,transaction and transaction.args or args)
  if not called then text,ok=tostring(text),false end
  local recorded,recordError,effects=ChangeSet.finish(transaction,text,ok)
  if recorded==false then text,ok=tostring(recordError),false
  elseif recorded==true and transaction then ok=true end
  return text,ok,effects
end

reset()
local _, ok = run("create_file", { path = "/new" }, function() files["/new"] = "new"; return "done", true end)
assert(ok and ChangeSet.hasUndo())
assert(ChangeSet.undo() and files["/new"] == nil)
assert(ChangeSet.redo() and files["/new"] == "new")
local peek = ChangeSet.peekUndo(); peek.args.path = "wrong"
assert(ChangeSet.peekUndo().args.path == "/new", "peek must be detached")
local expected = ChangeSet.peekUndo()
assert(ChangeSet.undo(expected))
assert(ChangeSet.redo(ChangeSet.peekRedo()))
assert(ChangeSet.undo({ id = "stale", scope = expected.scope }) == false)
scope = "/other"
assert(ChangeSet.undo(expected) == false and files["/new"] == "new")
scope = "/project"

reset(); files["/a"] = binary
_, ok = run("delete_file", { path = "/a" }, function() files["/a"] = nil; return "done", true end)
assert(ok and saved:find("AP+AQQ==", 1, true), "persisted snapshot is JSON-safe base64")
scope = "/reload"; configure()
scope = "/project"; configure()
assert(ChangeSet.undo() and files["/a"] == binary)
assert(ChangeSet.redo() and files["/a"] == nil)

reset(); files["/a"] = binary
_, ok = run("rename_file", { path = "/a", new_path = "/b" }, function()
  files["/b"], files["/a"] = files["/a"], nil; return "done", true
end)
assert(ok and ChangeSet.undo() and files["/a"] == binary and files["/b"] == nil)
assert(ChangeSet.peekRedo().args.new_path == "/b")
assert(ChangeSet.redo() and files["/a"] == nil and files["/b"] == binary)

reset(); files["/dir"], files["/dir/empty"], files["/dir/a"] = true, true, binary
_, ok = run("delete_folder", { path = "/dir" }, function() files = {}; return "done", true end)
assert(ok and ChangeSet.undo() and files["/dir/a"] == binary and files["/dir/empty"] == true)
assert(ChangeSet.redo() and files["/dir"] == nil)

reset(); files["/a"] = binary
local effects
_, ok, effects = run("create_file", { path = "/a", content = "new" }, function()
  files["/a"] = "new"; scope = "/other"; return "done", true
end)
assert(ok == false and files["/a"] == binary and not ChangeSet.hasUndo(), "scope rollback cannot report success")
assert(effects.status == "rolled_back" and effects.paths[1] == "/a")

reset(); files["/a"] = binary
_, ok = run("create_file", { path = "/a" }, function() files["/a"] = "new"; failRead = true; return "done", true end)
assert(ok == false and files["/a"] == binary, "post-snapshot failure rolls back binary")

reset(); files["/a"] = binary
local text
text, ok, effects = run("create_file", { path = "/a" }, function()
  files["/a"] = "new"; failRead, failRestore = true, true; return "done", true
end)
assert(ok == false and text:find("回滚不完整", 1, true))
assert(effects.status == "rollback_failed")

reset(); failSave = true
_, ok, effects = run("create_file", { path = "/a" }, function() files["/a"] = "new"; return "done", true end)
assert(ok == true and ChangeSet.hasUndo() and files["/a"] == "new", "history failure is only a warning")
assert(effects.status == "committed" and effects.historyPersisted == false)
_, ok = run("create_file", { path = "/a" }, function() files["/a"] = "old"; return "failed", false end)
assert(ok == false and ChangeSet.hasUndo(), "persist error cannot mask failed tool")

reset()
_, ok = run("create_file", { path = "/denied" }, function() error("must not execute") end)
assert(ok == false and not ChangeSet.hasUndo())
_, ok = run("create_file", { path = "/a" }, function() files["/a"] = "new"; error("partial write") end)
assert(ok == false and ChangeSet.hasUndo() and ChangeSet.undo() and files["/a"] == nil)
reset(); files["/a"] = binary
_, ok = run("create_file", { path = "/a" }, function() files["/a"] = "new"; return "done", true end)
assert(ok)
failRestore = true
local undoOk, undoError, undoEffects = ChangeSet.undo(ChangeSet.peekUndo())
assert(undoOk == false and undoError and undoEffects.status == "rollback_failed")
assert(ChangeSet.hasUndo(), "failed undo retains the transaction")
print("PASS retained legacy migration snapshots and history failure cases")
-- Current entry-point guarantees use an injected native protocol instead of
-- reinstating the retired executor ChangeSet/lock hooks.
assert(loadfile("tests/TestFileMutationService.lua"))()
print("ALL-PASS legacy migration and native-service transaction boundary")
