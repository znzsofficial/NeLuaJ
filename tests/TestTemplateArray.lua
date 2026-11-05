local modules = (ASSETS or "app/src/main/assets/") .. "templates/shared/modules/"
local oldOf, oldNulls = _G.arrayOf, _G.arrayOfNulls
local bindings = {}
local env = setmetatable({ luajava = { bindClass = function(name)
  bindings[name] = (bindings[name] or 0) + 1
  return luajava.bindClass(name)
end } }, { __index = _G })
local Array = assert(loadfile(modules .. "Array.lua", "t", env))()
assert(type(Array) == "table")
assert(_G.arrayOf == oldOf and _G.arrayOfNulls == oldNulls, "require must not install globals")
local String = luajava.bindClass("java.lang.String")
local Integer = luajava.bindClass("java.lang.Integer")
local ReflectArray = luajava.bindClass("java.lang.reflect.Array")
local failureCase = 0
local function fails(fn)
  failureCase = failureCase + 1
  assert(not pcall(fn), "expected validation or Java error, case " .. failureCase)
end

local names = Array.of(String, "Ada", nil, "Lin", nil)
assert(ReflectArray.getLength(names) == 4)
assert(names[0] == "Ada" and names[1] == nil and names[2] == "Lin" and names[3] == nil)
local packed = Array.toTable(names)
assert(packed.n == 4 and packed[1] == "Ada" and packed[2] == nil and packed[3] == "Lin")
local copied = Array.from("java.lang.String", packed)
assert(ReflectArray.getLength(copied) == 4 and copied[2] == "Lin" and copied[3] == nil)
assert(Array.toTable(Array.of(String)).n == 0)
assert(Array.toTable(Array.new(String, 3)).n == 3)
local dense = { "a", "b" }
assert(Array.from(String, dense)[1] == "b" and dense.n == nil)
local ints = Array.from("int", { 3, -5, 9 })
assert(ints[0] == 3 and ints[1] == -5 and ints[2] == 9)
assert(Array.of(Integer.TYPE, 7)[0] == 7)
assert(Array.new("int", 2)[1] == 0)
assert(Array.of("boolean", true, false)[1] == false)
for _, kind in ipairs({"byte", "short", "long", "float", "double", "char"}) do
  assert(ReflectArray.getLength(Array.new(kind, 1)) == 1)
end
fails(function() Array.of("int", nil) end)
fails(function() Array.from("boolean", { n = 2, true }) end)
for _, n in ipairs({-1, 1.5, "2", math.huge, 2147483648, 0/0}) do
  fails(function() Array.new(String, n) end)
end
fails(function() Array.new(String) end)
fails(function() Array.from(String, { [2] = "hole" }) end)
fails(function() Array.from(String, { n = 1, [2] = "outside" }) end)
fails(function() Array.from(String, { n = -1 }) end)
fails(function() Array.from(String, { n = false }) end)
fails(function() Array.from(String, { named = "outside" }) end)
fails(function() Array.toTable({}) end)
fails(function() return Array.get(ints, -1) end)
fails(function() Array.set(ints, 3, 1) end)
fails(function() Array.set(ints, 0, nil) end)
fails(function() Array.get(ints, 0.5) end)
assert(Array.set(ints, 0, 12) == ints and Array.get(ints, 0) == 12)
assert(Array.set(names, 0, nil) == names and Array.get(names, 0) == nil)
Array.new("java.lang.String", 0)
Array.new("int", 0)
Array.new("java.lang.Integer", 0)
assert(bindings["java.lang.String"] == 1 and bindings["java.lang.Integer"] == 1,
  "named reference and primitive types must bind only once")
assert(Array.arrayOf[String]("legacy")[0] == "legacy")
assert(ReflectArray.getLength(Array.arrayOfNulls[String](2)) == 2)
local target = {}
assert(Array.installLegacy(target) == Array)
assert(target.arrayOf == Array.arrayOf and target.arrayOfNulls == Array.arrayOfNulls)
Array.installLegacy()
assert(_G.arrayOf == Array.arrayOf and _G.arrayOfNulls == Array.arrayOfNulls)
_G.arrayOf, _G.arrayOfNulls = oldOf, oldNulls
print("ALL-PASS TestTemplateArray")
