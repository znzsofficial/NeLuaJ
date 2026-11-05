-- Public android.animation API, minSdk 26. Helpers use dot calls:
-- float(target, property, values [, options])
-- int(target, property, values [, options])
-- argb(target, property, values [, options])
-- objects(target, property, evaluator, values [, options])
-- path(target, xProperty, yProperty, Path [, options]) -- float coordinates
-- pointF(target, Property, Path [, options]) -- optional TypeConverter
-- propertyValues(target, holders [, options]); create(config); Animator(config).
-- Numeric values: scalar or nonempty dense Lua array. Object values/holders:
-- nonempty dense Lua arrays. Object entries: Java objects or Lua strings,
-- booleans and finite numbers. int/argb values must be signed 32-bit integers
-- (for example -1 for opaque white). property: name or android.util.Property.
-- Options: duration/startDelay/currentPlayTime (nonnegative integer milliseconds),
-- repeatCount (-1 or nonnegative int), repeatMode (1=RESTART, 2=REVERSE),
-- autoCancel/start (boolean), interpolator, evaluator, converter, currentFraction.
-- currentFraction/currentPlayTime are mutually exclusive. start defaults false.
-- Example: Animator.float(view, "alpha", {0, 1}, {duration=200, start=true})
-- Example: Animator{type="int", target=view, property="scrollX", values=0}
-- Example: Animator.path(view, "translationX", "translationY", curve)
-- Named types: float/int/argb/object/pointF/propertyValuesHolder. Float/int
-- coordinate paths use xProperty,yProperty,path; pointF uses property,path.
-- Objects require TypeEvaluator; converter additionally requires Property.
-- pointF uses public ofObject(target, Property, TypeConverter-or-nil, Path).
-- Legacy positional payloads: float/int/argb {target,property,values}; object
-- {target,property,evaluator,values} or {target,Property,converter,evaluator,values};
-- propertyValuesHolder {target,holders}; pointF {target,Property,Path}; float/int
-- paths {target,xProperty,yProperty,Path}. Do not mix positional/named payloads.
-- Migration: durationScale/frameDelay are rejected (process-wide settings).
-- Unknown/irrelevant fields are errors. No AndroidX internal API dependency.
-- multiFloat/multiInt require raw ofMultiFloat/ofMultiInt. All exported of*
-- constructors forward public Java APIs without validation/configuration.
local Native = luajava.bindClass "android.animation.ObjectAnimator"
local JavaObject = luajava.bindClass "java.lang.Object"
local Property = luajava.bindClass "android.util.Property"
local Path = luajava.bindClass "android.graphics.Path"
local Evaluator = luajava.bindClass "android.animation.TypeEvaluator"
local Converter = luajava.bindClass "android.animation.TypeConverter"
local Holder = luajava.bindClass "android.animation.PropertyValuesHolder"
local Interpolator = luajava.bindClass "android.animation.TimeInterpolator"
local M = {}
for _, name in ipairs({"Argb", "Float", "Int", "Object", "MultiFloat", "MultiInt", "PropertyValuesHolder"}) do M["of" .. name] = Native["of" .. name] end
M.TYPE_FLOAT, M.TYPE_INT, M.TYPE_ARGB = "float", "int", "argb"
M.TYPE_OBJECT, M.TYPE_POINT_F = "object", "pointF"
M.TYPE_PROPERTY_VALUES_HOLDER = "propertyValuesHolder"
M.TYPE_MULTI_FLOAT, M.TYPE_MULTI_INT = "multiFloat", "multiInt"
local function fail(message) error("ObjectAnimator: " .. message, 3) end
local function is(value, class)
  local ok, result = pcall(luajava.instanceof, value, class)
  return ok and result
end
local function requireJava(value, class, label)
  if not is(value, class) then fail(label .. " must be a Java " .. tostring(class)) end
end
local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function integer(v) return finite(v) and v % 1 == 0 end
local function property(v)
  if not (type(v) == "string" and v ~= "") and not is(v, Property) then fail("property must be a nonempty name or android.util.Property") end
end
local function array(v, label)
  if type(v) ~= "table" or #v == 0 then fail(label .. " must be a nonempty dense Lua array") end
  local n = #v
  for k in pairs(v) do if not integer(k) or k < 1 or k > n then fail(label .. " must be a dense Lua array") end end
  for i = 1, n do if v[i] == nil then fail(label .. " must be a dense Lua array") end end
  return v
end
local payload = {"target", "property", "xProperty", "yProperty", "values", "path", "evaluator", "converter"}
local allowed = {type=true, target=true, property=true, xProperty=true, yProperty=true,
  values=true, path=true, evaluator=true, converter=true, duration=true, startDelay=true,
  autoCancel=true, repeatCount=true, repeatMode=true, interpolator=true,
  currentFraction=true, currentPlayTime=true, start=true}
local function normalize(input)
  if type(input) ~= "table" then fail("config must be a table") end
  local c = {}
  for k, v in pairs(input) do c[k] = v end
  if c[1] ~= nil then
    for _, k in ipairs(payload) do if c[k] ~= nil then fail("cannot mix positional and named payloads") end end
    local count = 0
    for k in pairs(c) do
      if type(k) == "number" then
        if not integer(k) or k < 1 or k > 5 then fail("invalid positional argument") end
        count = math.max(count, k)
      end
    end
    for i = 1, count do if c[i] == nil then fail("positional arguments must be dense") end end
    c.target = c[1]
    if c.type == "propertyValuesHolder" and count == 2 then c.values = c[2]
    elseif c.type == "object" and count == 4 then c.property, c.evaluator, c.values = c[2], c[3], c[4]
    elseif c.type == "object" and count == 5 then c.property, c.converter, c.evaluator, c.values = c[2], c[3], c[4], c[5]
    elseif (c.type == "float" or c.type == "int") and count == 4 then c.xProperty, c.yProperty, c.path = c[2], c[3], c[4]
    elseif c.type == "pointF" and count == 3 then c.property, c.path = c[2], c[3]
    elseif (c.type == "float" or c.type == "int" or c.type == "argb") and count == 3 then c.property, c.values = c[2], c[3]
    else fail("unsupported positional signature; use named config or raw of* constructors") end
    for i = 1, count do c[i] = nil end
  end
  if c.durationScale ~= nil or c.frameDelay ~= nil then fail("durationScale/frameDelay are process-wide settings and are not supported") end
  for k in pairs(c) do if not allowed[k] then fail("unknown option " .. tostring(k)) end end
  if c.property ~= nil and c.xProperty ~= nil then fail("use property or xProperty, not both") end
  if c.property == nil then c.property = c.xProperty end
  if (c.type == "float" or c.type == "int") and c.yProperty ~= nil and c.path == nil and is(c.values, Path) then
    c.path, c.values = c.values, nil -- legacy named coordinate path
  end
  return c
end
local function validateOptions(c)
  for _, k in ipairs({"duration", "startDelay", "currentPlayTime"}) do
    if c[k] ~= nil and (not integer(c[k]) or c[k] < 0 or c[k] > 9007199254740991) then fail(k .. " must be a nonnegative safe integer") end
  end
  if c.repeatCount ~= nil and (not integer(c.repeatCount) or c.repeatCount < -1 or c.repeatCount > 2147483647) then fail("repeatCount must be -1 or a nonnegative int") end
  if c.repeatMode ~= nil and c.repeatMode ~= 1 and c.repeatMode ~= 2 then fail("repeatMode must be 1 (RESTART) or 2 (REVERSE)") end
  for _, k in ipairs({"autoCancel", "start"}) do if c[k] ~= nil and type(c[k]) ~= "boolean" then fail(k .. " must be boolean") end end
  if c.currentFraction ~= nil and (not finite(c.currentFraction) or c.currentFraction < 0) then fail("currentFraction must be finite and nonnegative") end
  if c.currentFraction ~= nil and c.currentPlayTime ~= nil then fail("choose currentFraction or currentPlayTime") end
  if c.interpolator ~= nil then requireJava(c.interpolator, Interpolator, "interpolator") end
  if c.evaluator ~= nil then requireJava(c.evaluator, Evaluator, "evaluator") end
  if c.converter ~= nil then requireJava(c.converter, Converter, "converter") end
end
local function nativeCall(label, fn, ...)
  local ok, result = pcall(fn, ...)
  if not ok then fail("native " .. label .. " failed: " .. tostring(result)) end
  return result
end
function M.create(input)
  local c = normalize(input)
  validateOptions(c)
  local kind = c.type
  if kind ~= "float" and kind ~= "int" and kind ~= "argb" and kind ~= "object" and kind ~= "pointF" and kind ~= "propertyValuesHolder" then fail("unsupported type " .. tostring(kind) .. "; multiFloat/multiInt require raw ofMulti* constructors") end
  requireJava(c.target, JavaObject, "target")
  local method, args
  if kind == "propertyValuesHolder" then
    if c.property ~= nil or c.yProperty ~= nil or c.path ~= nil or c.converter ~= nil or c.evaluator ~= nil then fail("propertyValuesHolder accepts only target and values payload") end
    array(c.values, "values")
    for _, v in ipairs(c.values) do requireJava(v, Holder, "holder") end
    method, args = "ofPropertyValuesHolder", {c.target, c.values}
  else
    property(c.property)
    if kind == "pointF" then
      requireJava(c.property, Property, "pointF property")
      if c.path ~= nil and c.values ~= nil then fail("choose path or values, not both") end
      local curve = c.path
      if curve == nil then curve = c.values end -- legacy named values=Path
      requireJava(curve, Path, "path")
      if c.yProperty ~= nil or c.evaluator ~= nil then fail("pointF does not accept yProperty/evaluator") end
      method, args = "ofObject", {c.target, c.property, c.converter, curve, n=4}
    elseif c.path ~= nil or c.yProperty ~= nil then
      if kind ~= "float" and kind ~= "int" then fail("coordinate paths require float or int type") end
      if c.values ~= nil or c.converter ~= nil or c.evaluator ~= nil then fail("coordinate paths do not accept values/converter/evaluator") end
      property(c.yProperty)
      if type(c.property) ~= type(c.yProperty) then fail("path properties must both be names or both be Property objects") end
      requireJava(c.path, Path, "path")
      method = kind == "float" and "ofFloat" or "ofInt"
      args = {c.target, c.property, c.yProperty, c.path}
    elseif kind == "object" then
      requireJava(c.evaluator, Evaluator, "object evaluator")
      array(c.values, "object values")
      for _, value in ipairs(c.values) do
        local t = type(value)
        if not (t == "string" or t == "boolean" or finite(value) or is(value, JavaObject)) then
          fail("object values must contain Java objects or scalar strings/booleans/finite numbers")
        end
      end
      method = "ofObject"
      if c.converter ~= nil then
        requireJava(c.property, Property, "converted object property")
        args = {c.target, c.property, c.converter, c.evaluator, c.values}
      else args = {c.target, c.property, c.evaluator, c.values} end
    else
      if c.converter ~= nil then fail("converter is only supported for object or pointF") end
      local values = c.values
      if type(values) == "number" then values = {values} end
      array(values, "values")
      for _, v in ipairs(values) do
        if not finite(v) then fail("values must contain finite numbers") end
        if kind == "float" then
          if math.abs(v) > 3.4028234663852886e38 then fail("float value is out of range") end
        elseif not integer(v) or v < -2147483648 or v > 2147483647 then fail("int/argb values must be signed 32-bit integers") end
      end
      method = ({float="ofFloat", int="ofInt", argb="ofArgb"})[kind]
      args = {c.target, c.property, values}
    end
  end
  local animator = nativeCall(method, Native[method], table.unpack(args, 1, args.n or #args))
  -- Stable order: timing/repeats, evaluator, interpolation, seek, then start.
  for _, item in ipairs({{"autoCancel", "setAutoCancel"}, {"duration", "setDuration"},
    {"startDelay", "setStartDelay"}, {"repeatCount", "setRepeatCount"}, {"repeatMode", "setRepeatMode"},
    {"evaluator", "setEvaluator"}, {"interpolator", "setInterpolator"},
    {"currentFraction", "setCurrentFraction"}, {"currentPlayTime", "setCurrentPlayTime"}}) do
    local key, setter = item[1], item[2]
    if c[key] ~= nil and not (key == "evaluator" and kind == "object") then nativeCall(setter, animator[setter], c[key]) end
  end
  if c.start then nativeCall("start", animator.start) end
  return animator
end
local function helper(kind, fields, options)
  if options ~= nil and type(options) ~= "table" then fail("options must be a table") end
  local c = {}
  for k, v in pairs(options or {}) do
    if k == "type" or k == "target" or k == "property" or k == "xProperty" or k == "yProperty" or k == "values" or k == "path" or type(k) == "number" then fail("payload field " .. tostring(k) .. " is not an option") end
    c[k] = v
  end
  c.type = kind
  for k, v in pairs(fields) do if c[k] ~= nil then fail("duplicate " .. k) end; c[k] = v end
  return M.create(c)
end
function M.float(target, property, values, options) return helper("float", {target=target, property=property, values=values}, options) end
function M.int(target, property, values, options) return helper("int", {target=target, property=property, values=values}, options) end
function M.argb(target, property, values, options) return helper("argb", {target=target, property=property, values=values}, options) end
function M.objects(target, property, evaluator, values, options) return helper("object", {target=target, property=property, evaluator=evaluator, values=values}, options) end
function M.path(target, xProperty, yProperty, path, options) return helper("float", {target=target, xProperty=xProperty, yProperty=yProperty, path=path}, options) end
function M.pointF(target, property, path, options) return helper("pointF", {target=target, property=property, path=path}, options) end
function M.propertyValues(target, holders, options) return helper("propertyValuesHolder", {target=target, values=holders}, options) end
return setmetatable(M, {__call=function(_, config) return M.create(config) end})
