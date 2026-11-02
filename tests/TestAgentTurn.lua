local assets = ASSETS or "app/src/main/assets/"
local callbacks, published, saved, refreshes, released
local function noop() end
local agent = {
  sendStream = function(_, options) callbacks = options end,
  cancelPendingRequest = noop, cancelPendingTools = noop,
  normalizeToolName = function(name) return name end,
  classifyParallelBatch = function() return nil end,
  shouldAutoApprove = function() return true end,
  isDestructiveTool = function() return false end,
  executeToolAsync = function(_, _, callback) callback("once", true); callback("twice", true) end,
  buildCompressedApiMessages = function() end,
}
package.loaded["mods.agent.AgentChat"] = agent
package.loaded["mods.agent.TodoManager"] = {}
package.loaded["mods.agent.SubagentRunner"] = { cancel = noop }
package.loaded["mods.utils.EditorUtil"] = {}
package.loaded["mods.agent.SessionState"] = assert(loadfile(assets .. "mods/agent/SessionState.lua"))()
package.loaded["mods.agent.AsyncScope"] = assert(loadfile(assets .. "mods/agent/AsyncScope.lua"))()
local Session = package.loaded["mods.agent.SessionState"]
local contracts = assert(loadfile(assets .. "mods/agent/Contracts.lua"))()
package.loaded["mods.agent.Contracts"] = contracts
json = { encode = function() return "{}" end, decode = function() return {} end }
res = { string = setmetatable({}, { __index = function(_, key) return key end }) }
activity = {}
luajava = { bindClass = function()
  return { acquire = noop, release = function() released = released + 1 end }
end }
local turn = assert(loadfile(assets .. "mods/agent/AgentTurn.lua"))()
local function options(render)
  return {
    saveHistory = function() saved = saved + 1 end,
    refreshMessageList = function() refreshes = refreshes + 1 end,
    isToolError = function() return false end,
    showToolConfirm = function() error("unexpected confirmation") end,
    onStreamChanged = render,
  }
end
local function reset(render)
  Session.activate({ id = "conv", messages = { { role = "user", content = "hello" } } }, "/proj")
  published, saved, refreshes, released = {}, 0, 0, 0
  turn.configure(options(render))
  turn.invalidate()
  turn.sendRaw(Session.messages(), false)
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
assert(Session.messages()[2].content == "two" and #Session.messages() == 2)
assert(turn.activeStream() == nil and not turn.isActive())
print("PASS stream snapshots are isolated and retries replace partial text")

-- No render hook is needed for request execution or persistence.
reset(nil)
callbacks.onChunk("headless")
callbacks.onDone("headless", false)
assert(Session.messages()[2].content == "headless" and saved > 0)
print("PASS request lifecycle works without a stream renderer")

-- Stop keeps this generation alive long enough to save partial text.
reset(nil)
callbacks.onChunk("partial")
local generation = turn.generation()
turn.requestStop()
assert(turn.generation() == generation)
callbacks.onError("cancelled")
assert(Session.messages()[2].content == "partial" and Session.messages()[2].continuation_state == "stopped")
assert(turn.activeStream() == nil)
print("PASS stop saves partial output")

-- Switching contexts invalidates every callback from the old request.
reset(nil)
local old = callbacks
turn.invalidate()
Session.activate({ id = "next", messages = { { role = "user", content = "new conversation" } } }, "/proj")
turn.sendRaw(Session.messages(), false)
local current = turn.activeStream().id
old.onChunk("stale")
old.onDone("stale", false)
old.onError("stale error")
assert(#Session.messages() == 1 and turn.activeStream().id == current and turn.activeStream().text == "")
callbacks.onDone("current", false)
assert(Session.messages()[2].content == "current")
print("PASS invalidated request cannot modify the new conversation")

reset(nil)
old = callbacks
Session.activate({ id = "other", messages = { { role = "user", content = "other" } } }, "/proj")
old.onChunk("stale")
old.onDone("stale", false)
assert(#Session.messages() == 1 and Session.messages()[1].content == "other")
print("PASS session change rejects callbacks without waiting for generation")

reset(function(snapshot)
  if snapshot then published[#published + 1] = snapshot.text end
end)
callbacks.onChunk("alive")
turn.configure(options(function(snapshot)
  if snapshot then published[#published + 1] = "reopen:" .. snapshot.text end
end))
turn.rerenderStream()
assert(published[#published] == "reopen:alive")
print("PASS reopening the panel receives the active stream again")

reset(nil)
callbacks.onToolCalls({ { id = "call-1", name = "read_file", arguments = "{}" } }, "")
local toolCount = 0
for _, message in ipairs(Session.messages()) do
  if message.role == "tool" then
    toolCount = toolCount + 1
    assert(message.content == "once")
  end
end
assert(toolCount == 1)
print("PASS a repeated tool callback does not append a second result")

local ok, err = pcall(turn.configure, {})
assert(not ok and tostring(err):find("saveHistory", 1, true))
local bad = options(nil)
bad.onStremChanged = noop
ok, err = pcall(turn.configure, bad)
assert(not ok and tostring(err):find("onStremChanged", 1, true))
bad = options(nil); bad.saveHistory = true
assert(not pcall(turn.configure, bad))
-- A rejected reconfiguration must not destroy the last valid wiring.
turn.sendRaw(messages, false)
callbacks.onDone("still wired", false)
assert(Session.messages()[#Session.messages()].content == "still wired")
print("PASS invalid callback contracts fail before replacing live hooks")
turn.invalidate()
local partial = { role = "assistant", content = "partial", continuation_state = "stopped" }
Session.activate({ id = "continue", messages = { { role = "user", content = "question" }, partial } }, "/proj")
local requestHistory, compressionDone
agent.buildCompressedApiMessages = function(history, callback)
  requestHistory, compressionDone = history, callback
end
turn.send(true)
partial.continuation_state = nil
assert(requestHistory[2] ~= partial and requestHistory[2].continuation_state == "stopped")
compressionDone(requestHistory, false)
callbacks.onDone("continued", false)
print("PASS asynchronous continuation snapshots survive clearing the UI marker")

-- Recovery actions use real APIs, keep request-only editor context off disk,
-- and do not discard the error card when forced compression is unavailable.
turn.invalidate()
local request = { role = "user", content = "original", request_error = "HTTP 500" }
Session.activate({ id = "retry", messages = { request } }, "/proj")
local sent
agent.sendStream = function(history, opts) sent, callbacks = history, opts end
local payload = { { role = "user", content = "original + editor context" } }
assert(turn.retry(payload))
assert(sent == payload and request.request_error == nil)
assert(Session.messages()[1].content == "original")
assert(not turn.retry(payload), "active requests cannot be retried twice")
callbacks.onError("context too long")
local originalError = request.request_error
local compressor
agent.buildCompressedApiMessages = function(history, cb, force)
  assert(history == payload and force == true)
  compressor = cb
end
assert(turn.compressAndRetry(payload))
compressor(payload, false)
assert(not turn.isActive() and request.request_error == originalError)
assert(turn.compressAndRetry(payload))
local compact = { { role = "user", content = "summary + latest request" } }
compressor(compact, true)
assert(sent == compact and request.request_error == nil)
assert(Session.messages()[1] == request and request.content == "original")
callbacks.onDone("recovered", false)
assert(Session.messages()[2].content == "recovered")
print("PASS retry and forced compression preserve request context and conversation ownership")

turn.invalidate()
assert(turn.compressAndRetry(payload))
local expiredCompression, oldSent = compressor, sent
turn.invalidate()
Session.activate({ id = "new", messages = { { role = "user", content = "new" } } }, "/proj")
expiredCompression(compact, true)
assert(sent == oldSent and #Session.messages() == 1)
print("PASS stale compression cannot restart a request in another session")

-- A cancelled parallel batch has no completion-callback guarantee.
local pending = {}
agent.classifyParallelBatch = function(calls)
  local out = {}
  for i, call in ipairs(calls) do out[i] = { name = call.name, id = call.id, args = {} } end
  return out
end
agent.executeToolAsync = function(_, _, callback) pending[#pending + 1] = callback end
agent.cancelPendingTools = noop
turn.sendRaw(Session.messages(), false)
callbacks.onToolCalls({
  { id = "p1", name = "read_file", arguments = "{}" },
  { id = "p2", name = "read_file", arguments = "{}" },
}, "")
assert(#pending == 2)
pending[1]("completed before stop", true)
turn.requestStop()
assert(not turn.isActive() and #Session.messages() == 4)
assert(Session.messages()[3].tool_call_id == "p1" and Session.messages()[3].content == "completed before stop")
assert(Session.messages()[4].tool_call_id == "p2" and Session.messages()[4].content == res.string.ai_stopped)
assert(Session.messages()[4].continuation_state == "stopped")
pending[2]("late result", true); pending[1]("duplicate", true)
assert(#Session.messages() == 4)
print("PASS parallel stop persists collected results, pairs every tool, and rejects late callbacks")
print("ALL-PASS")
