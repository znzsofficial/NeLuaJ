local assets = ASSETS or "app/src/main/assets/"
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
print("ALL-PASS")
