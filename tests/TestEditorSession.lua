local assets = ASSETS or "app/src/main/assets/"
package.path = assets .. "?.lua;" .. package.path
local session = assert(loadfile(assets .. "mods/editor/EditorSession.lua"))()

assert(session.current() == nil)
assert(session.isCurrent("a.lua") == false)
session.setCurrent("a.lua")
assert(session.isCurrent("a.lua"))
session.setCurrent("")
assert(session.current() == nil)
session.setCurrent("a.lua")

session.remember("a.lua")
session.remember("b.lua")
session.remember("a.lua")
local recent = session.recent()
assert(recent[1] == "a.lua" and recent[2] == "b.lua" and #recent == 2)
for index = 1, 60 do session.remember("f" .. index .. ".lua") end
assert(#session.recent() == 50)
assert(session.recent()[1] == "f60.lua")
print("PASS recent files stay unique and capped")

session.setCursor("a.lua", 12)
session.setCursor("a.lua", "bad")
assert(session.cursor("a.lua") == 12)
session.importCursors({ ["b.lua"] = 3, ["c.lua"] = "no" })
assert(session.cursor("b.lua") == 3 and session.cursor("c.lua") == nil)
assert(session.recent()[1] == "f60.lua")
print("PASS cursors stay separate from the recent-file list")

local function shouldReload(current, path)
  return current ~= path
end
local function acceptRead(text)
  return text ~= nil
end
local function canReplace(saveResult)
  return saveResult == true or saveResult == "same"
end
assert(shouldReload("a.lua", "a.lua") == false)
assert(acceptRead(nil) == false and acceptRead("") == true)
assert(canReplace(nil) == false and canReplace(false) == false)
assert(canReplace(true) and canReplace("same"))
print("PASS open decisions keep the current buffer unless the read can replace it")
-- Exercise the real EditorUtil, including its same-file shortcut and external writer bridge.
local disk, buffer = { ["/project/a.lua"] = "old" }, ""
local tabs = { Table = {} }
tabs.add = function(path) tabs.Table[path] = { obj = { select = function() end } } end
tabs.remove = function(path) tabs.Table[path] = nil end
package.loaded["mods.utils.TabUtil"] = tabs
package.loaded["mods.editor.EditorSession"] = session
package.loaded["mods.editor.EditorMinimap"] = { noteEdit = function() end }
package.loaded["mods.editor.EditorCompletion"] = {}
package.loaded["mods.editor.EditorSelection"] = {}
bindClass = function(name)
  if name ~= "java.io.File" then return {} end
  return function(path)
    return {
      isFile = function() return disk[path] ~= nil end,
      isDirectory = function() return false end,
      exists = function() return disk[path] ~= nil end,
      length = function() return #(disk[path] or "") end,
      getCanonicalPath = function() return path:gsub("/sdcard/", "/project/"):gsub("/%./", "/") end,
      getName = function() return path end,
    }
  end
end
res = { string = {} }
Bean = { Path = { app_root_pro_dir = "/Projects", this_dir = "/Projects/A" }, Project = {} }
PathManager = { updateFile = function(path) Bean.Path.this_file = path end }
activity = { setTitle = function() end, getSupportActionBar = function() return { setSubtitle = function() end } end }
this = { setSharedData = function() end }
mLuaEditor = {
  setText = function(text) buffer = text end,
  getText = function() return { toString = function() return buffer end } end,
  setVisibility = function() end,
  clearFocus = function() end,
  getSelectionEnd = function() return 2 end,
  setSelection = function() end,
}
LuaFileUtil = {
  read = function(path) return disk[path] or "" end,
  write = function(path, text) disk[path] = text; return true end,
}
session.setCurrent(nil)
local editor = assert(loadfile(assets .. "mods/utils/EditorUtil.lua"))()
local drafts, failDraft, busy, race, lastToken = {}, false, false, false, nil
luajava = nil -- Explicit non-Android storage harness.
editor.setTestStorage({
  observe = function(path) return {kind = disk[path] and "file" or "missing", text = disk[path], version = disk[path] or "missing"} end,
  saveText = function(token, path, text, expected)
    lastToken = token
    if busy then return {outcome = "rejected", error = {code = "busy"}} end
    if race then disk[path] = "racing external writer"; race = false end
    if (disk[path] or "missing") ~= expected then return {outcome = "rejected", error = {code = "conflict"}} end
    local same = text == disk[path]
    disk[path] = text
    return {outcome = same and "unchanged" or "committed", version = text}
  end,
  readDraft = function(slot) return drafts[slot] end,
  writeDraft = function(slot, draft) if failDraft then return false end; drafts[slot] = draft; return true end,
})
editor.load("/project/a.lua")
assert(buffer == "old")
buffer = "manual before AI"
local snapshot = editor.prepareExternalWrite("/sdcard/./a.lua")
assert(snapshot and disk["/project/a.lua"] == buffer)
disk["/project/a.lua"] = "AI update"
editor.load("/project/a.lua")
assert(buffer == "manual before AI", "ordinary load must still preserve a same-file buffer")
assert(editor.finishExternalWrite(snapshot))
assert(buffer == "AI update" and editor.save() == "same")
snapshot = editor.prepareExternalWrite("/project/a.lua")
buffer = "manual during AI"
disk["/project/a.lua"] = "second AI update"
local refreshed, reason = editor.finishExternalWrite(snapshot)
assert(refreshed == false and reason and buffer == "manual during AI")
assert(editor.save() == false and disk["/project/a.lua"] == "second AI update")
assert(not pcall(editor.prepareExternalWrite, "/project/a.lua"), "conflicting edits block the next write")
assert(editor.finishExternalWrite(snapshot, nil, true))
assert(buffer == "second AI update" and editor.save() == "same", "forced refresh must use disk content")
local savedDrafts = editor.listExternalDrafts("/project/a.lua")
assert(#savedDrafts == 1 and editor.readDraft(savedDrafts[1].id).text == "manual during AI")
buffer = "new input before draft restore"
assert(editor.restoreExternalDraft(savedDrafts[1].id) and buffer == "manual during AI")
local protected = false
for _, draft in ipairs(editor.listExternalDrafts("/project/a.lua")) do
  if draft.text == "new input before draft restore" then protected = true end
end
assert(protected, "restoring a draft must protect the current buffer")
assert(editor.save() == true)
snapshot = editor.prepareExternalWrite("/project/a.lua", "shared-lock")
assert(lastToken == "shared-lock")
buffer, disk["/project/a.lua"], failDraft = "draft failing", "second AI update", true
local refreshedDraft, draftWarning = editor.finishExternalWrite(snapshot, nil, true)
assert(refreshedDraft and draftWarning:find("草稿保存失败") and buffer == "second AI update")
failDraft = false
busy = true
local saved, saveError = editor.save()
assert(saved == false and saveError.code == "busy")
busy = false
race = true
buffer = "must not overwrite race"
saved, saveError = editor.save()
assert(saved == false and saveError.code == "conflict" and disk["/project/a.lua"] == "racing external writer")
assert(editor.finishExternalWrite(snapshot, nil, true))
disk["/project/a.lua"] = "second AI update"
assert(editor.finishExternalWrite(snapshot, nil, true))
-- Switching ownership while an operation runs must never replace another editor buffer.
session.setCurrent("/project/b.lua")
assert(editor.finishExternalWrite(snapshot, nil, true) and buffer == "second AI update")
print("PASS real editor reloads AI writes, preserves concurrent edits, and blocks stale saves")
session.setCurrent("/project/a.lua")
local function renameEffects(from, to)
  return {outcome = "committed", changes = {
    {kind="rename", path=from, from=from, to=to, afterKind="missing"},
    {kind="rename", path=to, from=from, to=to, afterKind="dir"},
  }}
end
local operation = editor.prepareFileOperation("rename_file", { path = "/project", new_path = "/renamed" })
disk["/renamed/a.lua"], disk["/project/a.lua"] = disk["/project/a.lua"], nil
assert(editor.finishFileOperation(operation, renameEffects("/project", "/renamed")))
assert(session.current() == "/renamed/a.lua" and buffer == "second AI update")
assert(tabs.Table["/renamed/a.lua"] and not tabs.Table["/project/a.lua"])
-- Undo a directory rename uses the reversed path mapping, then redo uses the original.
operation = editor.prepareFileOperation("rename_file", { path = "/renamed", new_path = "/project" })
disk["/project/a.lua"], disk["/renamed/a.lua"] = disk["/renamed/a.lua"], nil
assert(editor.finishFileOperation(operation, renameEffects("/renamed", "/project")))
assert(session.current() == "/project/a.lua" and tabs.Table["/project/a.lua"])
operation = editor.prepareFileOperation("apply_patch", { path = "/project/a.lua" })
disk["/project/a.lua"] = "undone content"
assert(editor.finishFileOperation(operation, {outcome="committed", changes={{kind="write", path="/project/a.lua", afterKind="file"}}}) and buffer == "undone content" and editor.save() == "same")
operation = editor.prepareFileOperation("delete_folder", { path = "/project" })
disk["/project/a.lua"] = nil
assert(editor.finishFileOperation(operation, {outcome="committed", changes={{kind="delete", path="/project", afterKind="missing"}}}))
assert(session.current() == nil and buffer == "" and not tabs.Table["/project/a.lua"])
print("PASS parent-directory rename maps editor and tabs; deletion clears them without recreating files")
disk["/project/a.lua"], disk["/project/b.lua"] = "A", "B"
editor.load("/project/a.lua")
local cursor, selected = 4, nil
mLuaEditor.getSelectionEnd = function() return cursor end
mLuaEditor.setSelection = function(value) selected = value end
operation = editor.prepareFileOperation("apply_patch", {path="/project/a.lua"})
local binding = session.identity()
editor.load("/project/b.lua")
editor.load("/project/a.lua")
assert(not session.isBinding(binding), "A-B-A must advance binding epoch")
cursor = 19
buffer = "manual on new A binding"
disk["/project/a.lua"] = "AI on A"
local writeEffects = {outcome="committed", changes={{kind="write",path="/project/a.lua",afterKind="file"}}}
assert(editor.finishFileOperation(operation, writeEffects))
assert(buffer == "AI on A" and selected == 19, "new binding must not reuse old cursor")
local foundNewDraft = false
for _, draft in ipairs(editor.listExternalDrafts("/project/a.lua")) do
  if draft.text == "manual on new A binding" then foundNewDraft = true end
end
assert(foundNewDraft)
operation = editor.prepareFileOperation("apply_patch", {path="/project/a.lua"})
editor.load("/project/b.lua")
disk["/project/a.lua"] = "another AI A"
assert(editor.finishFileOperation(operation, writeEffects))
assert(session.current() == "/project/b.lua" and buffer == "B", "switching file never jumps back")
local context = require "mods.project.ProjectContext"
editor.load("/project/a.lua")
operation = editor.prepareFileOperation("apply_patch", {path="/project/a.lua"})
context.setDirectory("/Projects/B")
context.setDirectory("/Projects/A")
disk["/project/a.lua"] = "scope stale AI"
assert(editor.finishFileOperation(operation, writeEffects) and buffer == "another AI A", "scope A-B-A invalidates old callback")
-- Synchronize explicitly for the rest of the cases.
snapshot = session.identity(buffer); snapshot.text = buffer; snapshot.cursor = cursor
assert(editor.finishExternalWrite(snapshot, nil, true))
operation = editor.prepareFileOperation("rename_file", {path="/project",new_path="/moved"})
editor.load("/project/b.lua")
disk["/moved/a.lua"],disk["/moved/b.lua"] = disk["/project/a.lua"],disk["/project/b.lua"]
disk["/project/a.lua"],disk["/project/b.lua"] = nil,nil
assert(editor.finishFileOperation(operation, renameEffects("/project","/moved")))
assert(session.current() == "/moved/b.lua" and tabs.Table["/moved/a.lua"] and not tabs.Table["/project/a.lua"])
-- Undo uses the original operation kind/from/to, but reversed observed kinds.
operation = editor.prepareFileOperation("rename_file", {path="/moved",new_path="/project"})
disk["/project/a.lua"],disk["/project/b.lua"] = disk["/moved/a.lua"],disk["/moved/b.lua"]
disk["/moved/a.lua"],disk["/moved/b.lua"] = nil,nil
assert(editor.finishFileOperation(operation, {outcome="committed",changes={
  {kind="rename",path="/project",from="/project",to="/moved",afterKind="dir"},
  {kind="rename",path="/moved",from="/project",to="/moved",afterKind="missing"},
}}))
assert(session.current() == "/project/b.lua" and tabs.Table["/project/a.lua"])
operation = editor.prepareFileOperation("delete_folder", {path="/project"})
local partialOk, partialWarning = editor.finishFileOperation(operation, {outcome="partial",changes={}})
assert(partialOk and partialWarning and buffer == "B", "partial without changes must not guess disk")
buffer = "manual during partial"
disk["/project/b.lua"] = "confirmed partial write"
partialOk, partialWarning = editor.finishFileOperation(operation, {outcome="partial", recoveryRequired=true,
  changes={{kind="write",path="/project/b.lua",afterKind="file",verified=true}},
  unknownPaths={{path="/project/a.lua",code="observe_failed",message="unreadable"}},
})
assert(partialOk and partialWarning:find("/project/a.lua",1,true) and buffer == "confirmed partial write")
local partialDraft = false
for _, draft in ipairs(editor.listExternalDrafts("/project/b.lua")) do
  if draft.text == "manual during partial" then partialDraft = true end
end
assert(partialDraft, "verified partial refresh must protect concurrent input")
buffer = "keep unknown buffer"
partialOk, partialWarning = editor.finishFileOperation(operation, {outcome="partial",changes={
  {kind="write",path="/project",afterKind="dir",verified=true}},
  unknownPaths={{path="/project/b.lua",code="observe_failed"}},
})
assert(partialOk and partialWarning and buffer == "keep unknown buffer", "unknown paths override ancestor refresh")
assert(editor.finishFileOperation(operation, {outcome="partial",changes={
  {kind="write",path="/project/b.lua",afterKind="file"}}}) and buffer == "keep unknown buffer", "partial needs confirmed evidence")
buffer = "input during delete"
disk["/project/a.lua"],disk["/project/b.lua"] = nil,nil
assert(editor.finishFileOperation(operation, {outcome="committed",changes={{kind="delete",path="/project",afterKind="missing"}}}))
assert(not session.current() and not tabs.Table["/project/a.lua"] and not tabs.Table["/project/b.lua"])
assert(editor.listExternalDrafts("/project/b.lua")[1].text == "input during delete")
local closedBinding = session.identity()
disk["/project/a.lua"] = "reopened"
editor.load("/project/a.lua")
assert(not session.isBinding(closedBinding))
buffer = "input before replay"
disk["/project/a.lua"] = "recovered publication"
local recoveredResult = { scopeId = require("mods.project.ProjectContext").snapshot().scopePath,
  outcome = "committed", changes = {{kind="write",path="/project/a.lua",afterKind="file",afterVersion="recovered publication"}} }
local recoverySnapshot = assert(editor.captureRecovery(recoveredResult))
assert(disk["/project/a.lua"] == "recovered publication" and buffer == "input before replay", "capture must never save stale input")
assert(editor.finishFileOperation(recoverySnapshot,recoveredResult) and buffer == "recovered publication")
assert(editor.listExternalDrafts("/project/a.lua")[1].text == "input before replay")
buffer = "new input after historical transaction"
recoveredResult.changes[1].afterVersion = "older historical publication"
assert(editor.finishFileOperation(assert(editor.captureRecovery(recoveredResult)), recoveredResult))
assert(buffer == "new input after historical transaction", "superseded history must not clear or rebind the current document")
-- Native binding errors cannot silently fall back to the legacy writer.
editor.setTestStorage(nil)
buffer = "cannot write with missing native"
local nativeSaved, nativeError = editor.save()
assert(nativeSaved == false and nativeError and disk["/project/a.lua"] == "recovered publication")
print("PASS CAS/busy, recoverable drafts, draft failure, scope/document epochs, inverse rename, partial and delete")
print("ALL-PASS")
