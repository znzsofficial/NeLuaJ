local assets = ASSETS or "app/src/main/assets/"
local callbacks, messages, published, saved, refreshes, released
local function noop() end
local agent = {
  sendStream = function(_, options) callbacks = options end,
  cancelPendingRequest = noop, cancelPendingTools = noop,
}
package.loaded["mods.agent.AgentChat"] = agent
package.loaded["mods.agent.TodoManager"] = {}
package.loaded["mods.agent.SubagentRunner"] = { cancel = noop }
package.loaded["mods.utils.EditorUtil"] = {}
local contracts = assert(loadfile(assets .. "mods/agent/Contracts.lua"))()
package.loaded["mods.agent.Contracts"] = contracts
res = { string = setmetatable({}, { __index = function(_, key) return key end }) }
activity = {}
luajava = { bindClass = function()
  return { acquire = noop, release = function() released = released + 1 end }
end }
local turn = assert(loadfile(assets .. "mods/agent/AgentTurn.lua"))()
local function options(render)
  return {
    getMessages = function() return messages end,
    setMessages = function(value) messages = value end,
    resetTurnHistory = noop,
    saveHistory = function() saved = saved + 1 end,
    refreshMessageList = function() refreshes = refreshes + 1 end,
    isToolError = function() return false end,
    showToolConfirm = function() error("unexpected confirmation") end,
    onStreamChanged = render,
  }
end
local function reset(render)
  messages = { { role = "user", content = "hello" } }
  published, saved, refreshes, released = {}, 0, 0, 0
  turn.configure(options(render))
  turn.invalidate()
  turn.sendRaw(messages, false)
end

-- A UI callback receives copies, never the mutable runtime object.
reset(function(snapshot)
  if snapshot then
    published[#published + 1] = snapshot.text
    snapshot.text, snapshot.container = "UI mutation", {}
  end
end)
callbacks.onChunk("one")
assert(turn.activeStream().text == "one")
local snapshot = turn.activeStream()
snapshot.bubble, snapshot.textView, snapshot.render = {}, {}, noop
assert(turn.activeStream().bubble == nil and turn.activeStream().render == nil)
callbacks.onRetry()
assert(turn.activeStream().text == "")
callbacks.onChunk("two")
turn.rerenderStream()
assert(published[#published] == "two")
callbacks.onDone("two", false)
assert(messages[2].content == "two" and #messages == 2)
assert(turn.activeStream() == nil and not turn.isActive())
print("PASS stream snapshots are isolated and retries replace partial text")

-- No render hook is needed for request execution or persistence.
reset(nil)
callbacks.onChunk("headless")
callbacks.onDone("headless", false)
assert(messages[2].content == "headless" and saved > 0)
print("PASS request lifecycle works without a stream renderer")

-- Stop keeps this generation alive long enough to save partial text.
reset(nil)
callbacks.onChunk("partial")
local generation = turn.generation()
turn.requestStop()
assert(turn.generation() == generation)
callbacks.onError("cancelled")
assert(messages[2].content == "partial" and messages[2].continuation_state == "stopped")
assert(turn.activeStream() == nil)
print("PASS stop saves partial output")

-- Switching contexts invalidates every callback from the old request.
reset(nil)
local old = callbacks
turn.invalidate()
messages = { { role = "user", content = "new conversation" } }
turn.sendRaw(messages, false)
local current = turn.activeStream().id
old.onChunk("stale")
old.onDone("stale", false)
old.onError("stale error")
assert(#messages == 1 and turn.activeStream().id == current and turn.activeStream().text == "")
callbacks.onDone("current", false)
assert(messages[2].content == "current")
print("PASS invalidated request cannot modify the new conversation")

local ok, err = pcall(turn.configure, {})
assert(not ok and tostring(err):find("getMessages", 1, true))
local bad = options(nil)
bad.onStremChanged = noop
ok, err = pcall(turn.configure, bad)
assert(not ok and tostring(err):find("onStremChanged", 1, true))
bad = options(nil); bad.saveHistory = true
assert(not pcall(turn.configure, bad))
-- A rejected reconfiguration must not destroy the last valid wiring.
turn.sendRaw(messages, false)
callbacks.onDone("still wired", false)
assert(messages[#messages].content == "still wired")
print("PASS invalid callback contracts fail before replacing live hooks")
print("ALL-PASS")
