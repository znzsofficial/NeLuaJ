local calls, bindings = {}, {}
local function java(name) return {javaClass=name} end
local target, prop, propY = java("View"), java("android.util.Property"), java("android.util.Property")
local curve = java("android.graphics.Path")
local evaluator, converter = java("android.animation.TypeEvaluator"), java("android.animation.TypeConverter")
local holder, interpolator = java("android.animation.PropertyValuesHolder"), java("android.animation.TimeInterpolator")
local failure
local function record(name, ...)
  calls[#calls+1] = {name=name, n=select("#", ...), ...}
  if failure == name then error("bridge failure " .. name) end
end
local animator = {}
for _, name in ipairs({"setAutoCancel", "setDuration", "setStartDelay", "setRepeatCount", "setRepeatMode",
  "setEvaluator", "setInterpolator", "setCurrentFraction", "setCurrentPlayTime", "start"}) do
  animator[name] = function(...)
    assert(select("#", ...) == (name == "start" and 0 or 1), "dot call required")
    record(name, ...)
  end
end
local native = {}
for _, name in ipairs({"ofFloat", "ofInt", "ofArgb", "ofObject", "ofMultiFloat", "ofMultiInt", "ofPropertyValuesHolder"}) do
  native[name] = function(...)
    assert(select(1, ...) == target, "constructor target/dot dispatch")
    record(name, ...)
    return animator
  end
end
local env = setmetatable({luajava={
  bindClass=function(name)
    assert(not name:find("androidx", 1, true), "public Android API only")
    assert(not bindings[name], "bind each class once")
    bindings[name] = true
    return name == "android.animation.ObjectAnimator" and native or name
  end,
  instanceof=function(value, class)
    return type(value) == "table" and value.javaClass ~= nil and (class == "java.lang.Object" or value.javaClass == class)
  end,
}}, {__index=_G})
local A = assert(loadfile((ASSETS or "app/src/main/assets/") .. "templates/shared/modules/ObjectAnimator.lua", "t", env))()
local function reset() calls = {} end
local function constructor(name, count)
  assert(calls[1].name == name and calls[1].n == count, "wrong Java overload: " .. calls[1].name)
  return calls[1]
end
local function rejected(config, text)
  reset()
  local ok, err = pcall(A.create, config)
  assert(not ok and tostring(err):find(text, 1, true), tostring(err))
  assert(#calls == 0, "invalid config must not create or start a native animator")
end
assert(A.float(target, "alpha", 0) == animator)
local call = constructor("ofFloat", 3)
assert(call[2] == "alpha" and #call[3] == 1 and call[3][1] == 0 and #calls == 1)
reset()
A.int(target, prop, {-2, 0, 2})
call = constructor("ofInt", 3)
assert(call[2] == prop and call[3][3] == 2)
reset()
A.argb(target, "color", {-16777216, -1})
assert(constructor("ofArgb", 3)[3][1] == -16777216)
reset()
local values = {java("PointF"), java("PointF")}
A.objects(target, "position", evaluator, values)
call = constructor("ofObject", 4)
assert(call[3] == evaluator and call[4] == values and #calls == 1)
reset()
A.objects(target, prop, evaluator, values, {converter=converter})
call = constructor("ofObject", 5)
assert(call[3] == converter and call[4] == evaluator and call[5] == values)
reset()
A.propertyValues(target, {holder, holder})
assert(constructor("ofPropertyValuesHolder", 2)[2][2] == holder)
reset()
A.path(target, "x", "y", curve)
call = constructor("ofFloat", 4)
assert(call[2] == "x" and call[3] == "y" and call[4] == curve)
reset()
A{type="int", target=target, xProperty=prop, yProperty=propY, path=curve}
assert(constructor("ofInt", 4)[4] == curve)
reset()
A.pointF(target, prop, curve)
call = constructor("ofObject", 4)
assert(call[2] == prop and call[3] == nil and call[4] == curve, "null converter must not shift Path argument")
reset()
A.pointF(target, prop, curve, {converter=converter})
assert(constructor("ofObject", 4)[3] == converter)
reset()
A{type="pointF", target=target, property=prop, values=curve}
assert(constructor("ofObject", 4)[4] == curve)
reset()
A{type="float", target=target, xProperty="x", yProperty="y", values=curve}
assert(constructor("ofFloat", 4)[4] == curve)
-- Positional adapters select unambiguous overloads, including zero values.
for _, config in ipairs({
  {target, "alpha", 0, type="float"}, {target, prop, 0, type="int"},
  {target, "color", -1, type="argb"}, {target, "position", evaluator, values, type="object"},
  {target, prop, converter, evaluator, values, type="object"},
  {target, {holder}, type="propertyValuesHolder"}, {target, prop, curve, type="pointF"},
  {target, "x", "y", curve, type="float"},
}) do reset(); assert(A(config) == animator and #calls == 1) end
reset()
local options = {start=true, currentFraction=0, interpolator=interpolator, evaluator=evaluator,
  repeatMode=2, repeatCount=-1, startDelay=0, duration=0, autoCancel=false}
A.float(target, "alpha", {0, 1}, options)
local order = {"ofFloat", "setAutoCancel", "setDuration", "setStartDelay", "setRepeatCount",
  "setRepeatMode", "setEvaluator", "setInterpolator", "setCurrentFraction", "start"}
assert(#calls == #order)
for i, name in ipairs(order) do assert(calls[i].name == name, "configuration must finish before start") end
assert(calls[2][1] == false and calls[3][1] == 0 and calls[5][1] == -1)
assert(options.type == nil and options.target == nil, "do not modify caller options")
reset()
A.float(target, "alpha", 1, {currentPlayTime=0, start=false})
assert(#calls == 2 and calls[2].name == "setCurrentPlayTime")
local invalid = {
  {"durationScale", 0, "process-wide"}, {"frameDelay", 10, "process-wide"},
  {"duration", -1, "duration"}, {"duration", 0.5, "duration"}, {"duration", math.huge, "duration"},
  {"startDelay", -1, "startDelay"}, {"repeatCount", -2, "repeatCount"},
  {"repeatCount", 0.5, "repeatCount"}, {"repeatMode", 3, "repeatMode"},
  {"start", 1, "boolean"}, {"autoCancel", 0, "boolean"},
  {"currentFraction", 0/0, "currentFraction"}, {"currentPlayTime", -1, "currentPlayTime"},
  {"interpolator", {}, "interpolator"}, {"evaluator", {}, "evaluator"},
  {"converter", converter, "converter"}, {"typo", true, "unknown option"},
  {"target", false, "target"}, {"property", "", "property"},
  {"values", {}, "nonempty"}, {"values", {1, bad=2}, "dense"},
  {"values", {math.huge}, "finite"}, {"values", {false}, "finite"},
  {"type", "unknown", "unsupported type"}, {"type", "multiFloat", "ofMulti"},
}
for _, entry in ipairs(invalid) do
  local config = {type="float", target=target, property="alpha", values={0, 1}, start=true}
  config[entry[1]] = entry[2]
  rejected(config, entry[3])
end
rejected({type="float", target=target, property="alpha", values=1, currentFraction=0, currentPlayTime=0}, "choose")
rejected({type="int", target=target, property="x", values=0.5}, "32-bit")
rejected({type="argb", target=target, property="color", values=4294967295}, "32-bit")
rejected({type="object", target=target, property="p", values=values}, "evaluator")
rejected({type="object", target=target, property="p", evaluator=evaluator, values={{}}}, "object values")
rejected({type="object", target=target, property="p", evaluator=evaluator, converter=converter, values=values}, "converted object property")
rejected({type="pointF", target=target, property="p", path=curve}, "pointF property")
rejected({type="float", target=target, xProperty="x", yProperty=prop, path=curve}, "both")
rejected({type="float", target=target, xProperty="x", yProperty="y", path={}, start=true}, "path")
rejected({type="propertyValuesHolder", target=target, values={target}}, "holder")
rejected({target, "alpha", 1, type="float", target=target}, "mix")
rejected({target, "p", evaluator, type="object"}, "unsupported positional")
-- A bridge failure is actionable and cannot accidentally start the animator.
reset(); failure = "ofFloat"
local ok, err = pcall(A.float, target, "alpha", 1, {start=true})
assert(not ok and tostring(err):find("native ofFloat failed", 1, true) and #calls == 1)
reset(); failure = "setDuration"
ok, err = pcall(A.float, target, "alpha", 1, {duration=20, start=true})
assert(not ok and tostring(err):find("native setDuration failed", 1, true) and #calls == 2)
failure = nil
reset(); A.ofMultiFloat(target, "coordinates", curve)
assert(constructor("ofMultiFloat", 3)[3] == curve)
print("ALL-PASS TestTemplateAnimator")
