-- Typed Java arrays: Java indices are zero-based, Lua tables one-based.
-- local Array = require "mods.Array"
-- local names = Array.of("java.lang.String", "Ada", nil, "Lin")
-- local ints = Array.from("int", {1, 2, 3})
-- local empty = Array.new("java.lang.String", 4)
-- Array.toTable(names) -> {[1]="Ada", [3]="Lin", n=3}
-- Types accept a Java Class or class name; primitive names use wrapper TYPE.
-- from accepts dense tables or packed tables with explicit n (null slots).
-- new creates Java defaults (null for references, zero/false for primitives).
-- get/set validate zero-based bounds; direct array indexing uses bridge rules.
-- Legacy: Array.arrayOf[Class](...) / Array.arrayOfNulls[Class](length).
-- Only Array.installLegacy() installs these two names in _G.
local ReflectArray = luajava.bindClass("java.lang.reflect.Array")
local wrappers = {
  boolean = "Boolean", byte = "Byte", short = "Short", int = "Integer",
  long = "Long", float = "Float", double = "Double", char = "Character",
}
local M = {}
local classes = {}
local boundClasses = { ["java.lang.reflect.Array"] = ReflectArray }

local function length(n)
  assert(type(n) == "number" and n >= 0 and n <= 2147483647 and n % 1 == 0,
    "Array length must be a non-negative Java int")
  return n
end

local function resolve(kind)
  if type(kind) == "string" then
    if classes[kind] ~= nil then return classes[kind] end
    local wrapper = wrappers[kind]
    local name = wrapper and ("java.lang." .. wrapper) or kind
    local class = boundClasses[name]
    if class == nil then
      class = luajava.bindClass(name)
      boundClasses[name] = class
    end
    if wrapper then class = class.TYPE end
    classes[kind] = class
    return class
  end
  assert(kind ~= nil, "Array component Class is required")
  return kind
end

function M.new(kind, n)
  return ReflectArray.newInstance(resolve(kind), length(n))
end

function M.from(kind, values)
  assert(type(values) == "table", "Array.from expects a Lua table")
  local n = values.n
  if n == nil then n = #values end
  n = length(n)
  for key in pairs(values) do
    assert(key == "n" or (type(key) == "number" and key % 1 == 0 and key >= 1 and key <= n),
      "Array table keys must be within 1..length")
  end
  local result = ReflectArray.newInstance(resolve(kind), n)
  for i = 1, n do
    assert(values.n ~= nil or values[i] ~= nil, "Array.from expects a dense or packed table")
    -- Reflection rejects primitive null instead of silently skipping nil.
    if values[i] == nil then
      ReflectArray.set(result, i - 1, nil)
    else
      result[i - 1] = values[i]
    end
  end
  return result
end

function M.of(kind, ...)
  return M.from(kind, table.pack(...))
end

function M.toTable(array)
  local n = ReflectArray.getLength(array)
  local values = { n = n }
  for i = 1, n do values[i] = array[i - 1] end
  return values
end

local function index(array, i)
  local n = ReflectArray.getLength(array)
  assert(type(i) == "number" and i % 1 == 0 and i >= 0 and i < n,
    "Array index must be within 0..length-1")
  return i
end

function M.get(array, i)
  return array[index(array, i)]
end

function M.set(array, i, value)
  index(array, i)
  if value == nil then ReflectArray.set(array, i, nil)
  else array[i] = value end
  return array
end

M.arrayOf = setmetatable({}, { __index = function(_, kind)
  return function(...) return M.of(kind, ...) end
end })
M.arrayOfNulls = setmetatable({}, { __index = function(_, kind)
  return function(n) return M.new(kind, n) end
end })

function M.installLegacy(target)
  target = target or _G
  target.arrayOf, target.arrayOfNulls = M.arrayOf, M.arrayOfNulls
  return M
end

return M
