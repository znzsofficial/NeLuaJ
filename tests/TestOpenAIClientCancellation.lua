local assets = ASSETS or "app/src/main/assets/"
package.loaded["mods.agent.OpenAIProtocol"] = {
  buildRequest = function() return {}, false, { role = "user" }, {} end,
  endpoint = function(url) return url .. "/chat/completions" end,
  requestHeaders = function() return {} end,
}
luajava = { bindClass = function(name)
  if name == "android.os.Handler" then
    return function() return { removeCallbacks = function() end } end
  end
  return { getMainLooper = function() return {} end }
end }
json = { encode = function() return "{}" end }
local cancelled, errors, chunks, done = 0, 0, 0, 0
local onChunk, onDone
local client = assert(loadfile(assets .. "mods/agent/OpenAIClient.lua"))()
client.configure({
  getApiKey = function() return "key" end,
  getApiUrl = function() return "https://example.com/v1" end,
  getRetryCount = function() return 0 end,
  getHttpClient = function() return {
    postJsonStream = function(_, _, _, chunk, complete) onChunk, onDone = chunk, complete end,
    cancelAll = function() cancelled = cancelled + 1 end,
  } end,
})
local function callbacks()
  return {
    onError = function() errors = errors + 1 end,
    onChunk = function() chunks = chunks + 1 end,
    onDone = function() done = done + 1 end,
  }
end
local handle = client.sendStream({}, callbacks())
assert(type(handle) == "table" and type(handle.cancel) == "function")
handle.cancel(); handle.cancel()
onChunk("late"); onDone("late")
assert(cancelled == 1 and errors == 1 and chunks == 0 and done == 0)
print("PASS returned stream handle cancels once and suppresses late events")
local completed = client.sendStream({}, callbacks())
onDone("answer")
local nextHandle = client.sendStream({}, callbacks())
completed.cancel()
assert(cancelled == 1 and done == 1)
client.cancelPending()
assert(cancelled == 2 and errors == 2)
print("PASS completed handles cannot cancel a newer request")
print("ALL-PASS")
