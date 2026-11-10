local root = ASSETS or "app/src/main/assets/"
package.path = root .. "?.lua;" .. package.path
local encoded, seq = {}, 0
json = {
  encode = function(value) seq = seq + 1; local key = "json" .. seq; encoded[key] = value; return key end,
  decode = function(value) return assert(encoded[value], value) end,
}
local groups, tasks, posts = {}, {}, {}
local http = {}
function http.newRequestGroup()
  local group = { cancelled = false, calls = {} }
  group.isCancelled = function() return group.cancelled end
  group.cancel = function()
    group.cancelled = true
    for _, call in ipairs(group.calls) do call.cancelled = true end
  end
  group.lock = function() return not group.cancelled end
  groups[group] = true
  return group
end
function http.releaseRequestGroup(group) groups[group] = nil end
function http.cancelAll() for group in pairs(groups) do group.cancel() end end
function http.validateServerUrl() return nil end
function http.postJson(url, body, headers, id, group)
  assert(not group or not group.isCancelled(), "registered after cancel")
  local call = { group = group, payload = encoded[body] }
  posts[#posts + 1] = call
  if group then group.calls[#group.calls + 1] = call end
  if http.onPost then http.onPost(call) end
  if call.cancelled then error("cancelled") end
  local reply = json.encode({ result = { content = { { type = "text", text = "ok" } } } })
  return { code = function() return 200 end, header = function() return nil end, body = function() return reply end }
end
luajava = { bindClass = function(name)
  if name:find("ReentrantLock", 1, true) then
    return function() return { lock = function() end, unlock = function() end } end
  end
  return function() return http end
end }
xTask = function(work, done)
  local task = { work = work, done = done, cancellations = 0 }
  task.cancel = function() task.cancellations = task.cancellations + 1 end
  tasks[#tasks + 1] = task
  return task
end
local client = require("mods.agent.MCPClient")
local protocol = require("mods.agent.MCPProtocol")
local server = { name = "test", url = "https://example.test/mcp" }
local key = protocol.serverKey(server)
client._initCache[key] = protocol.DEFAULT_PROTOCOL
client._serverState[key] = { mode = "modern", protocolVersion = protocol.DEFAULT_PROTOCOL }
local callbacks = {}
local a = client.callToolAsync(server, "a", {}, function() callbacks.a = (callbacks.a or 0) + 1 end)
local b = client.callToolAsync(server, "b", {}, function(ok, text)
  assert(ok and text == "ok"); callbacks.b = (callbacks.b or 0) + 1
end)
-- A is in HTTP while B enters its own HTTP; cancel A inside that overlap.
http.onPost = function(call)
  if call.payload.params.name == "a" then
    tasks[2].done(tasks[2].work())
  else a.cancel(); a.cancel() end
end
tasks[1].done(tasks[1].work())
assert(callbacks.a == nil and callbacks.b == 1)
assert(posts[1].cancelled and not posts[2].cancelled)
assert(tasks[1].cancellations == 1 and tasks[2].cancellations == 0)
assert(next(groups) == nil and next(client._toolCalls) == nil)
b.cancel()
assert(tasks[2].cancellations == 0)

-- Cancel before the worker registers its very first network request.
http.onPost = nil
local before = #posts
local early = client.callToolAsync(server, "early", {}, function() error("late callback") end)
early.cancel()
tasks[3].done(tasks[3].work())
assert(#posts == before and next(groups) == nil)

-- Initialization/probe use the same cancellation group; no fallback/retry starts.
client._initCache[key] = nil
client._serverState[key] = nil
local initializing = client.callToolAsync(server, "init", {}, function() error("cancelled init callback") end)
http.onPost = function() initializing.cancel() end
before = #posts
tasks[4].done(tasks[4].work())
assert(#posts == before + 1 and next(groups) == nil)

-- Synchronous xTask completion and duplicate callbacks must not leak a handle.
client._initCache[key] = protocol.DEFAULT_PROTOCOL
http.onPost = nil
xTask = function(work, done)
  local result = work()
  done(result); done(result)
  return { cancel = function() error("completed job cancelled") end }
end
local count = 0
local sync = client.callToolAsync(server, "sync", {}, function(ok)
  assert(ok); count = count + 1
  assert(next(client._toolCalls) == nil)
end)
sync.cancel()
assert(count == 1 and next(groups) == nil)

-- Reentrant global cancellation before xTask returns cancels the late job once.
local lateCancel = 0
xTask = function(work, done)
  client.cancelPending()
  done(work())
  return { cancel = function() lateCancel = lateCancel + 1 end }
end
client.callToolAsync(server, "late", {}, function() error("late callback") end)
assert(lateCancel == 1 and next(groups) == nil and next(client._toolCalls) == nil)

-- Cancel during the initial SSE endpoint wait. The next task must await the
-- same stream (isUsable is still false), initialize it and call its tool.
local originalPost = http.postJson
local opened, closed, endpointWaits = 0, 0, 0
local awaiting = {}
local connection = {}
connection.getError = function() return nil end
connection.isUsable = function() return endpointWaits >= 2 end
connection.close = function() closed = closed + 1 end
connection.prepareResponse = function(id, group)
  assert(not group.isCancelled()); awaiting[id] = true
end
connection.cancelResponse = function(id) awaiting[id] = nil end
connection.awaitResponse = function(id, timeout, group)
  assert(awaiting[id] and not group.isCancelled())
  awaiting[id] = nil
  return json.encode({ result = {
    protocolVersion = protocol.LEGACY_DEFAULT_PROTOCOL,
    content = { { type = "text", text = "recovered" } },
  } })
end
local pendingInit
connection.awaitEndpoint = function(timeout, group)
  endpointWaits = endpointWaits + 1
  if endpointWaits == 1 then pendingInit.cancel(); return nil end
  assert(not group.isCancelled())
  return "https://example.test/messages"
end
http.openSse = function(url, headers, group)
  assert(not group.isCancelled()); opened = opened + 1; return connection
end
http.postJson = function(url, body, headers, id, group)
  assert(not group.isCancelled())
  return {
    code = function() return url:find("messages", 1, true) and 202 or 405 end,
    header = function() return nil end,
    body = function() return "" end,
  }
end
xTask = function(work, done)
  local task = { work = work, done = done, cancel = function() end }
  tasks[#tasks + 1] = task
  return task
end
client._initCache[key] = nil
client._serverState[key] = nil
pendingInit = client.callToolAsync(server, "init", {}, function() error("cancelled callback") end)
local task = tasks[#tasks]
task.done(task.work())
assert(opened == 1 and closed == 0 and client._serverState[key].mode == "legacy_sse")
local recovered = 0
client.callToolAsync(server, "recover", {}, function(ok, text)
  assert(ok and text == "recovered"); recovered = recovered + 1
end)
task = tasks[#tasks]
task.done(task.work())
assert(recovered == 1 and opened == 1 and closed == 0 and next(awaiting) == nil)
client.cancelPending()
assert(client._serverState[key].sseConnection == nil and client._initCache[key] == nil)
http.postJson = originalPost
print("ALL-PASS McpClientCancellation")
