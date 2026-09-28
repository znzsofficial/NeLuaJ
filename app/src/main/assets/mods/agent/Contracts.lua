--- Validate callback wiring once, before replacing a module's active hooks.
local _M = {}

function _M.callbacks(owner, options, required, optional)
  assert(type(options) == "table", owner .. ".configure requires a table")
  local allowed, copy = {}, {}
  for _, name in ipairs(required or {}) do
    allowed[name] = true
    assert(type(options[name]) == "function", owner .. ".configure missing callback: " .. name)
  end
  for _, name in ipairs(optional or {}) do allowed[name] = true end
  for name, value in pairs(options) do
    assert(allowed[name], owner .. ".configure unknown callback: " .. tostring(name))
    assert(type(value) == "function", owner .. ".configure callback must be a function: " .. name)
    copy[name] = value
  end
  return copy
end

return _M
