local assets = ASSETS or "app/src/main/assets/"
local sent, prepared, awaited = {}, {}, {}
local values, serial = {}, 0
json = {
  encode = function(value)
    serial = serial + 1
    local token = tostring(serial)
    values[token] = value
    return token
  end,
  decode = function(token) return assert(values[token], "unknown JSON token") end,
}
local protocolVersion = "2025-11-25"
local responseBody = json.encode({ result = { protocolVersion = protocolVersion } })
local connection = {
  isUsable = function() return true end,
  awaitEndpoint = function() return "https://test.invalid/messages" end,
  prepareResponse = function(id) prepared[#prepared + 1] = id end,
  awaitResponse = function(id) awaited[#awaited + 1] = id; return responseBody end,
}
local http = {
  validateServerUrl = function() return "" end,
  postJson = function(_, body, _, expectedId)
    local payload = json.decode(body)
    sent[#sent + 1] = { payload = payload, expectedId = expectedId }
    return {
      code = function() return 200 end,
      header = function() return nil end,
      body = function()
        assert(payload.method == "initialize", "notification response body must not be read")
        return responseBody
      end,
    }
  end,
}
luajava = { bindClass = function(name)
  if name == "java.util.concurrent.locks.ReentrantLock" then
    return function() return { lock = function() end, unlock = function() end } end
  elseif name == "com.nekolaska.mcp.McpHttpClient" then
    return function() return http end
  elseif name == "android.util.Base64" then return {} end
  error("unexpected class: " .. name)
end }
local protocol = assert(loadfile(assets .. "mods/agent/MCPProtocol.lua"))()
package.loaded["mods.agent.MCPProtocol"] = protocol
package.loaded["mods.agent.McpTransport"] = assert(loadfile(assets .. "mods/agent/McpTransport.lua"))()
local allocated = 0
local function allocateId() allocated = allocated + 1; return allocated end
assert(protocol.newRequest("notification", {}, false, allocateId).id == nil)
assert(allocated == 0)
assert(protocol.newRequest("request", {}, 0, allocateId).id == 0)
assert(protocol.newRequest("request", {}, "explicit", allocateId).id == "explicit")
assert(allocated == 0)
assert(protocol.newRequest("request", {}, nil, allocateId).id == 1)
print("PASS shared envelopes preserve explicit IDs and omit notification IDs")
local function checkTransport(sse)
  sent, prepared, awaited = {}, {}, {}
  local client = assert(loadfile(assets .. "mods/agent/MCPClient.lua"))()
  local server = { url = "https://test.invalid/mcp", protocolVersion = protocolVersion }
  if sse then
    client._serverState[protocol.serverKey(server)] = { mode = "legacy_sse", sseConnection = connection }
  end
  local version, err = client.initialize(server)
  assert(version == protocolVersion, tostring(err))
  assert(#sent == 2)
  assert(sent[1].payload.method == "initialize" and type(sent[1].payload.id) == "number")
  assert(sent[2].payload.method == "notifications/initialized")
  assert(sent[2].payload.id == nil, "notification must omit id")
  assert(sent[2].expectedId == -1, "notification must not expect a transport response")
  assert(client._nextRequestId == 1, "notification must not allocate an ID")
  assert(#prepared == (sse and 1 or 0))
  assert(#awaited == (sse and 1 or 0), "SSE must only wait for initialize")
  print("PASS " .. (sse and "SSE" or "HTTP") .. " initialization notification")
end
checkTransport(false)
checkTransport(true)
print("ALL-PASS")
