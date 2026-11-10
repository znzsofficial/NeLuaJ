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
agent.classifyParallelBatch = function() return nil end
agent.buildCompressedApiMessages = function() end
agent.resolveToolPath = function(path) return "/proj/" .. path end
json.decode = function() return { path = "main.lua" } end
local prepared, refreshed, executed = 0, 0, 0
local snapshot = {}
local executor = assert(loadfile(assets .. "mods/agent/ToolExecutor.lua"))()
local mutationService = require("mods.files.FileMutationService")
local locked
local settings = {
  json = { encode = function(value) return value end },
  context = { snapshot = function() return { scopePath = "/proj", directory = "/proj", projectGeneration = 1 } end },
  storage = function() return "/storage" end,
  prepare = function(_, args)
    assert(args.path == "/proj/main.lua")
    prepared = prepared + 1
    return snapshot
  end,
  finish = function(value)
    assert(value == snapshot)
    refreshed = refreshed + 1
    return true
  end,
  backend = {
  tryAcquire = function(id) if locked then return "" end; locked = id; return id end,
  release = function() locked = nil end,
  recover = function() return { recovered = true } end,
  observe = function(path) return { path = path, kind = "file", text = "original", version = "v1" } end,
  execute = function(_, _, request)
    executed = executed + 1
    assert(prepared == executed)
    return { transactionId = request.transactionId, scopeId = "/proj", outcome = "committed", changes = {}, warnings = {} }
  end,
  },
}
mutationService.configure(settings)
assert(mutationService.recover().recovered)
executor.configure({ scheduleTimeout = function() return noop end })
agent.executeToolAsync = executor.executeToolAsync
settings.scheduler = function(work, done)
  local result = work()
  done(result)
  done(result)
  return { cancel = noop }
end
reset(nil)
callbacks.onToolCalls({ { id = "write", name = "create_file", arguments = "{}" } }, "")
assert(prepared == 1 and refreshed == 1 and executed == 1)
assert(Session.messages()[3].tool_ok == true and Session.messages()[3].file_result.outcome == "committed")
settings.prepare = function() error("save conflict") end
reset(nil)
callbacks.onToolCalls({ { id = "blocked", name = "apply_patch", arguments = "{}" } }, "")
assert(executed == 1 and refreshed == 1)
assert(Session.messages()[3].content:find("save conflict", 1, true))
settings.prepare = function() return snapshot end
settings.backend.execute = function() return { outcome = "rejected", error = { message = "write failed" }, changes = {} } end
reset(nil)
callbacks.onToolCalls({ { id = "failed", name = "create_file", arguments = "{}" } }, "")
assert(refreshed == 1, "failed writes must not reload the editor")
print("PASS writes prepare and refresh once; save conflicts and failed tools never reload")
-- Stop/timeout retain the exact placeholder for late file transaction facts.
local late, executionOptions, allow, deny
agent.executeToolAsync = function(_, _, cb, opts)
  late, executionOptions = cb, opts
  return { taskId = "task-write", cancel = noop }
end
agent.getTaskSnapshot = function(id)
  return { taskId = id, fileMutation = true, waitState = "cancelled" }
end
reset(nil)
callbacks.onToolCalls({ { id = "late-write", name = "create_file", arguments = "{}" },
  { id = "not-started", name = "read_file", arguments = "{}" } }, "")
assert(executionOptions.scope.conversationId == "conv" and executionOptions.toolCallId == "late-write")
turn.requestStop()
local stoppedMessage = Session.messages()[3]
assert(stoppedMessage.content:find("文件事务结果待确认", 1, true))
assert(stoppedMessage.task_info.taskId == "task-write")
assert(Session.messages()[4].content == res.string.ai_stopped)
callbacks.onError("cancelled") -- stale network cancellation must not invalidate the file owner
local fact = { transactionId = "tx", outcome = "committed" }
late("committed after stop", true, fact, { taskId = "task-write", transactionId = "tx" })
assert(#Session.messages() == 4 and Session.messages()[3] == stoppedMessage)
assert(stoppedMessage.file_result == fact and stoppedMessage.tool_ok == true)
assert(stoppedMessage.task_info.transactionId == "tx" and not turn.isActive())
late("duplicate", false, fact)
assert(stoppedMessage.content == "committed after stop")
print("PASS stopped file result updates its original placeholder exactly once")

reset(nil)
callbacks.onToolCalls({ { id = "timeout", name = "create_file", arguments = "{}" },
  { id = "remaining", name = "read_file", arguments = "{}" } }, "")
executionOptions.onWaitEnd({ taskId = "task-write", waitState = "timed_out", fileMutation = true })
assert(not turn.isActive() and #Session.messages() == 4)
assert(Session.messages()[3].content:find("等待超时", 1, true))
late("committed", true, fact, { taskId = "task-write" })
assert(Session.messages()[3].file_result == fact and #Session.messages() == 4)
print("PASS timeout pairs remaining calls and never resumes the model")

reset(nil)
callbacks.onToolCalls({ { id = "stale", name = "create_file", arguments = "{}" } }, "")
turn.requestStop()
local oldPlaceholder = Session.messages()[3]
turn.invalidate()
Session.activate({ id = "another", messages = {} }, "/other")
late("stale commit", true, fact)
assert(#Session.messages() == 0 and oldPlaceholder.file_result == nil)
print("PASS late file facts cannot cross scope or generation")

reset(nil)
agent.shouldAutoApprove = function() return false end
agent.requiresConfirmation = function() return true end
local opts = options(nil)
opts.showToolConfirm = function(_, _, yes, no) allow, deny = yes, no end
turn.configure(opts)
local dispatches = 0
agent.executeToolAsync = function(_, _, cb) dispatches = dispatches + 1; late = cb end
callbacks.onToolCalls({ { id = "confirm", name = "create_file", arguments = "{}" } }, "")
allow(); allow(); deny()
assert(dispatches == 1 and #Session.messages() == 2)
late("done", true)
assert(#Session.messages() == 3)
print("PASS repeated confirmation cannot execute twice or deny a started write")
agent.shouldAutoApprove = function() return true end
reset(nil)
agent.executeToolAsync = function(_, _, cb, opts)
  late, executionOptions = cb, opts
  return { taskId = "race-write", cancel = noop }
end
callbacks.onToolCalls({ { id = "race", name = "create_file", arguments = "{}" } }, "")
-- Cancelling the underlying transaction may complete before onWaitEnd is delivered.
late("committed at timeout", true, fact, { taskId = "race-write", waitState = "timed_out", fileMutation = true })
executionOptions.onWaitEnd({ taskId = "race-write", waitState = "timed_out" })
assert(not turn.isActive() and #Session.messages() == 3 and Session.messages()[3].file_result == fact)
assert(Session.messages()[3].continuation_state == "stopped")
print("PASS timeout final callback racing wait-end retains fact without continuation")

reset(nil)
pending = {}
agent.classifyParallelBatch = function(calls)
  local out = {}
  for i, call in ipairs(calls) do out[i] = { id = call.id, name = call.name, args = {} } end
  return out
end
agent.executeToolAsync = function(_, _, cb, opts)
  pending[#pending + 1] = { result = cb, options = opts }
  return { taskId = "parallel-" .. #pending }
end
callbacks.onToolCalls({ { id = "pa", name = "read_file", arguments = "{}" },
  { id = "pb", name = "read_file", arguments = "{}" } }, "")
assert(pending[1].options.scope.conversationId == "conv" and pending[2].options.toolCallId == "pb")
pending[1].result("first", true, nil, { taskId = "parallel-1" })
pending[2].options.onWaitEnd({ taskId = "parallel-2", waitState = "timed_out" })
assert(not turn.isActive() and #Session.messages() == 4)
assert(Session.messages()[3].task_info.taskId == "parallel-1")
assert(Session.messages()[4].task_info.waitState == "timed_out")
pending[2].result("late", true)
assert(#Session.messages() == 4)
print("PASS parallel identity and timeout pair all calls without continuation")
-- Exact batch cancellation, including timeout before execute returns its handle.
reset(nil)
local cancelCounts = {}
pending = {}
agent.executeToolAsync = function(_, _, cb, opts)
  local i = #pending + 1
  pending[i] = { result = cb, options = opts }
  return { taskId = "batch-" .. i, cancel = function()
    cancelCounts[i] = (cancelCounts[i] or 0) + 1
    cb("cancel reentrant", false)
  end }
end
local batch = { { id = "b1", name = "read_file", arguments = "{}" },
  { id = "b2", name = "read_file", arguments = "{}" },
  { id = "b3", name = "read_file", arguments = "{}" } }
callbacks.onToolCalls(batch, "")
pending[1].result("done", true)
pending[2].options.onWaitEnd({ taskId = "batch-2", waitState = "timed_out" })
pending[2].options.onWaitEnd({ taskId = "batch-2", waitState = "timed_out" })
assert(cancelCounts[1] == nil and cancelCounts[2] == 1 and cancelCounts[3] == 1)
assert(#Session.messages() == 5)
reset(nil)
pending, cancelCounts = {}, {}
callbacks.onToolCalls(batch, "")
local staleTimeout = pending[2].options.onWaitEnd
Session.activate({ id = "replacement", messages = {} }, "/proj")
staleTimeout({ taskId = "batch-2", waitState = "timed_out" })
assert(next(cancelCounts) == nil and #Session.messages() == 0)
reset(nil)
local syncCancelled, launches = 0, 0
agent.executeToolAsync = function(_, _, cb, opts)
  launches = launches + 1
  opts.onWaitEnd({ taskId = "sync", waitState = "timed_out" })
  return { taskId = "sync", cancel = function() syncCancelled = syncCancelled + 1 end }
end
callbacks.onToolCalls(batch, "")
assert(launches == 1 and syncCancelled == 1 and #Session.messages() == 5)
print("PASS parallel timeout cancels only unfinished batch handles exactly once, including synchronous dispatch")

agent.classifyParallelBatch = function() return nil end
agent.executeToolAsync = function(_, _, cb, opts)
  late, executionOptions = cb, opts
  return { taskId = "parent", cancel = noop }
end
reset(nil)
callbacks.onToolCalls({ { id = "parent-call", name = "run_subtask", arguments = "{}" } }, "")
late("子任务等待超时，文件事务结果待确认", false, nil, { taskId = "parent" })
local parent = Session.messages()[3]
local parentFact = { transactionId = "child-tx", outcome = "committed" }
executionOptions.onLateFileResult("真实提交", true, parentFact, { taskId = "child" }, { taskId = "parent" })
executionOptions.onLateFileResult("真实提交（更新）", true, parentFact, { taskId = "child" }, { taskId = "parent" })
assert(#Session.messages() == 3 and parent == Session.messages()[3] and parent.tool_ok == false)
assert(parent.file_result == nil and parent.task_info.taskId == "parent")
assert(#parent.child_file_results == 1 and parent.child_file_results[1].task_info.taskId == "child")
assert(parent.content:find("真实提交（更新）", 1, true))
local previousContent = parent.content
turn.invalidate()
executionOptions.onLateFileResult("stale", true, { transactionId = "other" }, {}, {})
assert(parent.content == previousContent and #parent.child_file_results == 1)
print("PASS late child facts update original completed parent, deduplicate, preserve failure and reject stale scope")

reset(nil)
callbacks.onToolCalls({ { id = "stopped-parent", name = "run_subtask", arguments = "{}" } }, "")
-- A child fact may arrive before the parent timeout/stop message exists.
executionOptions.onLateFileResult("committed early", true, parentFact, { taskId = "child" }, { taskId = "parent" })
assert(#Session.messages() == 2)
turn.requestStop()
parent = Session.messages()[3]
assert(#parent.child_file_results == 1 and parent.content:find("committed early", 1, true))
executionOptions.onLateFileResult("committed late", true, parentFact, { taskId = "child" }, { taskId = "parent" })
assert(#Session.messages() == 3 and parent.file_result == nil and parent.tool_ok ~= true)
assert(parent.continuation_state == "stopped" and not turn.isActive())
print("PASS stopped parent retains early and late child facts without duplicate messages or continuation")
print("ALL-PASS")
