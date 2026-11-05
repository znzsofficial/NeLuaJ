-- UI-independent flow. Never cancel a writer: it must finish publish/cleanup.
local M = {}
local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for k, v in pairs(value) do result[k] = copy(v) end
  return result
end
function M.new(deps)
  local state = { page = "templates", busy = false, disposed = false, token = 0 }
  local function alive() return not state.disposed and deps.alive() end
  local function emit() if alive() then deps.changed(state) end end
  local function invalidate()
    state.token = state.token + 1
    state.preview, state.options, state.error = nil, nil, nil
  end
  local function run(work, done)
    state.token = state.token + 1
    local token = state.token
    state.busy = true
    emit()
    local function finish(reply)
      if not alive() or token ~= state.token then return end
      state.token = state.token + 1 -- duplicate deliveries are ignored
      state.busy = false
      done(reply)
      emit()
    end
    local ok, err = pcall(deps.task, function()
      local success, result = pcall(work)
      return { ok = success, result = result }
    end, finish, "io")
    if not ok then finish({ ok = false, result = err }) end
  end
  function state.select(template)
    if state.busy or not alive() then return false end
    invalidate()
    state.template, state.page = template, "configuration"
    emit()
    return true
  end
  function state.edit()
    if state.busy or not alive() then return false end
    invalidate()
    emit()
    return true
  end
  function state.back()
    -- Leaving a running writer closes the page; it never cancels the transaction.
    if state.busy and state.phase == "generate" then return false end
    if state.page == "configuration" then
      invalidate()
      state.busy = false
      state.page = "templates"
      emit()
      return true
    end
    return false
  end
  function state.review(options, openAfter)
    if state.busy or state.page ~= "configuration" or not alive() then return end
    invalidate()
    local snapshot = copy(options)
    state.phase = "preview"
    run(function() return deps.generator.preview(snapshot) end, function(reply)
      local result = reply and reply.result
      if reply and reply.ok and type(result) == "table" and result.ok == true then
        state.preview, state.options, state.openAfter = result, snapshot, openAfter
      else state.error = result or "preview failed" end
    end)
  end
  function state.create()
    if state.busy or not state.preview or not alive() then return end
    local options, openAfter = copy(state.options), state.openAfter
    state.phase = "generate"
    run(function() return deps.generator.generate(options) end, function(reply)
      local result = reply and reply.result
      state.preview, state.options = nil, nil
      if reply and reply.ok and type(result) == "table" and result.ok == true then
        state.disposed = true
        deps.complete(result, openAfter)
      else state.error = result or "generation failed" end
    end)
  end
  function state.initialize(work, apply)
    state.phase = "initialize"
    run(work, function(reply) if reply.ok then apply(reply.result) end end)
  end
  function state.dispose()
    state.disposed = true
    state.token = state.token + 1
  end
  return state
end
return M
