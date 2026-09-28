local assets = ASSETS or "app/src/main/assets/"
local session = assert(loadfile(assets .. "mods/agent/SessionState.lua"))()

local conv = {
  id = "conv-1",
  messages = { { role = "user", content = "one" }, { role = "assistant", content = "two" } },
  usage = { requests = 3, tokens = 40 },
}
assert(session.activate(conv, "/proj") == conv.messages)
assert(session.id() == "conv-1" and session.loaded())
assert(session.usage().requests == 3 and session.usage().tokens == 40)
assert(not session.canPersist("/other", nil))
local original = session.messages()
session.setMessages({})
assert(not session.canPersist("/proj", nil), "empty wipe must be rejected")
assert(session.canPersist("/proj", { __allow_empty = true }))
session.setMessages(original)
session.addUsage(5)
assert(session.usageRecord().requests == 4 and session.usageRecord().tokens == 45)
print("PASS session identity, usage, and persistence guard")

local removed = session.undoTurn()
assert(removed and removed[1].content == "one" and #session.messages() == 0)
assert(session.canRedo())
assert(session.redoTurn()[1].content == "one")
assert(#session.messages() == 2 and not session.canRedo())
session.resetTurns()
assert(not session.canRedo())
print("PASS undo and redo keep the same message objects")

local kept = session.messages()
session.suspend()
assert(not session.loaded() and session.messages() == kept)
local switched = session.beginSwitch("conv-2", "/proj")
assert(switched ~= kept and #switched == 0 and session.id() == "conv-2")
local created = session.beginCreated({ id = "conv-3", messages = {} }, "/proj")
assert(session.usage().requests == 0 and created ~= switched)
session.select("conv-4", "/other")
assert(session.projectPath() == "/other" and not session.hadMessages())
session.reset()
assert(not session.loaded() and #session.messages() == 0)
print("PASS switch, create, and project suspension replace ownership explicitly")
print("ALL-PASS")
