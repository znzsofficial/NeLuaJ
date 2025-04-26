about_this = [[QQ群：603327362]]
code_time = [[local System = luajava.bindClass "java.lang.System"

local _M = {
  points = {System.nanoTime()},
  callback = function(i)
    print(tostring(i / 1000).." ms")
  end
}

_M.newInstance = function(self, callback)
  local obj = table.clone(self)
  if callback then obj.callback = callback end
  return obj
end

_M.addPoint = function(self)
  local time = System.nanoTime()
  table.insert(self.points, time)
  return time
end

_M.record = function(self)
  local time = self:addPoint() -
    (self.points[#self.points - 1])
  self.callback(time)
end

_M.callAndCount = function(func)
  assert(getmetatable(func) == _M,
    "The static method cannot be called by an instance! ")
  local start = System.nanoTime()
  func()
  local time = System.nanoTime() - start
  self.callback(time)
  return time
end

_M.getTotalTime = function(self)
  return self.points[#self.points]
    - self.points[1]
end

setmetatable(_M, {
  __call = lambda v, callback
    -> v:newInstance(callback)
})

return _M]]
code_array=[[local Array = luajava.bindClass("java.lang.reflect.Array")

_G.arrayOf = setmetatable({}, {
  __index = function(_, type)
    return function(...)
      local varargs = table.pack(...)
      local list = Array.newInstance(type, varargs.n)
      for i = 1, varargs.n do
        list[i - 1] = varargs[i]
      end
      return list
    end
  end,
})

_G.arrayOfNulls = setmetatable({}, {
  __index = function(_, type)
    return function(n)
      return Array.newInstance(type, n)
    end
  end,
})
]]
code_strings=[[local find = utf8.find
local sub = utf8.sub
local insert = table.insert
local lower = utf8.lower
local match = utf8.match
local String = luajava.bindClass "java.lang.String"

string.len = utf8.len
string.length = utf8.len
string.find = utf8.find
string.gsub = utf8.gsub
string.upper = utf8.upper
string.lower = utf8.lower

string.charAt = function(self, i)
  return sub(self, i, i)
end

string.codePointAt = function(str, i)
  return String(str).codePointAt(i - 1)
end

string.codePointBefore = function(str, i)
  return String(str).codePointBefore(i - 1)
end

string.codePointCount = function(str, start, ends)
  return String(str).codePointCount(start - 1, ends)
end

string.compareTo = function(str, comp)
  return String(str).compareTo(comp)
end

string.compareToIgnoreCase = function(str, comp)
  return String(str).compareToIgnoreCase(comp)
end

string.concat = function(str, add)
  return str..add
end

string.contains = match

string.endsWith = function(str, ends)
  return find(str, ends.."$") ~= nil
end

string.startsWith = function(str, start)
  return find(str, "^"..start) ~= nil
end

string.equalsIgnoreCase = function(str, comp)
  return lower(str) == lower(comp)
end

string.hashCode = function(str)
  return String(str).hashCode()
end

string.isEmpty = function(str)
  return (str == nil) or (#str == 0)
end

string.findLast = function(str)
  -- TODO()
end

string.toCharArray = function(str)
  local t = {}
  for i = 1, utf8.len(str) do
    table.insert(t, str:charAt(i))
  end
  return t
end

string.trim = function(str)
  return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

string.trimLeading = function(str)
  return (str:gsub("^%s+", ""))
end

string.trimTrailing = function(str)
  return (str:gsub("%s+$", ""))
end

string.isBlank = function(str)
  return str:trim() == ""
end

string.repeat = function(str, count)
  local t = ""
  for i = 1, count do
    t = t..str
  end
  return t
end

string.transform = function()
  -- TODO()
end

string.indent = function(str, count)
  local indent = string.repeat(" ", count)
  return (str:gsub("^", indent)
    :gsub("\n", "\n"..indent))
end 

-- @static
string.join = function(delimiter, ...)
  local result = ""
  local args = {...}
  
  if type(args[1]) == "table" then
    args = args[1]
  end

  for i = 1, #args do
    if i > 1 then
      result = result..delimiter
    end
    result = result..args[i]
  end
  return result
end

string.capitalize = function(str)
  return (str:gsub("^%l", utf8.upper, 1))
end

string.caseFold = function()
  -- TODO()
end

string.center = function()
  -- TODO()
end

string.expandTabs = function(self, size)
  return (self:gsub("\t", string.repeat(" ", size)))
end

-- isAlnum
-- isAlpha
-- isAscii
-- isDecimal
-- isDigit
-- isIdentifier
-- isLower
-- isNumeric
-- isPrintable
-- isTitle
-- isUpper
-- ljust
-- partition
-- removePrefix
-- removeSuffix
-- splitLines
-- swapCase
-- title

string.get = string.charAt
string.at = string.charAt
string.plus = string.concat
--string.forEach

string.isNone = function(self)
  return self == ""
end

-- at
-- random
-- reverse
-- slice
-- raw
-- padStart/End
-- ellipsize
-- trimToNull
-- trimToEmpty
-- strip..
-- countMatches
-- toBuffer
-- toBuilder

table.slice = function(t, first, last, step)
  local sliced = {}
  for i = first or 1, last or #t, step or 1 do
    sliced[#sliced + 1] = t[i]
  end
  return sliced
end

string.split = function(str, regex, limit)
  local limit = limit or 0
  local index = 1
  local matchLimited = limit > 0
  local matchList = {}
  
  local start, ends = find(str, regex)
  -- Add segments before each match found
  while start ~= nil do
    if (not matchLimited || #matchList < limit) then
      if (index == 1 && index == start && start == ends) then
        -- no empty leading substring included for zero-width match
        -- at the beginning of the input char sequence.
        start, ends = find(str, regex, ends + 1)
        index = 2
        continue
      end
      local match = sub(str, index, start - 1)
      if match ~= "" then
        insert(matchList, match)
      end
      index = ends + 1
     elseif #matchList == limit - 1 then -- last one
      local match = sub(str, index, #str)
      insert(matchList, match)
      index = ends + 1
    end
    start, ends = find(str, regex, ends + 1)
  end
  -- If no match was found, return this
  --if (index == 1)
  --  return {}
  --end

  if (!matchLimited || #matchList < limit)
    local match = sub(str, index, #str)
    if match ~= "" then
      insert(matchList, match)
    end
  end 

  -- Construct result
  local resultSize = #matchList
  if limit == 0 then
    while (resultSize > 0 && matchList[resultSize - 1]=="") do
      resultSize = resultSize - 1
    end
  end
  return table.slice(matchList, 1, resultSize)
end
]]
code_anim=[[local ObjectAnimator = luajava.bindClass "android.animation.ObjectAnimator"
local ObjectAnimatorUtils = luajava.bindClass "androidx.transition.ObjectAnimatorUtils"
local getType = type

local _M = {
  TYPE_ARGB = "argb",
  TYPE_FLOAT = "float",
  TYPE_INT = "int",
  TYPE_MULTI_FLOAT = "multiFloat",
  TYPE_MULTI_INT = "multiInt",
  TYPE_OBJECT = "object",
  TYPE_POINT_F = "pointF",
  TYPE_PROPERTY_VALUES_HOLDER = "propertyValuesHolder",

  ofArgb = ObjectAnimator["ofArgb"],
  ofFloat = ObjectAnimator["ofFloat"],
  ofInt = ObjectAnimator["ofInt"],
  ofMultiFloat = ObjectAnimator["ofMultiFloat"],
  ofMultiInt = ObjectAnimator["ofMultiInt"],
  ofPropertyValuesHolder = ObjectAnimator["ofPropertyValuesHolder"],
}

pcall(function()
  _M.ofPointF = ObjectAnimatorUtils["ofPointF"]
end)

local METHODS = {
  argb = "ofArgb", float = "ofFloat", int = "ofInt",
  multiFloat = "ofMultiFloat", multiInt = "ofMultiInt",
  object = "ofObject", pointF = "ofPointF",
  propertyValuesHolder = "ofPropertyValuesHolder"
}

_M.__call = function(self, t) 
  local type = METHODS[t.type]
  local target = t.target
  local xProperty = t.xProperty or t.property
  local yProperty = t.yProperty
  local converter = t.converter
  local evaluator = t.evaluator
  local values = t.values

  if t[1] then
    if t[5] then
      target = t[1]
      xProperty = t[2]
      converter = t[3]
      evaluator = t[4]
      values = t[5]
     elseif t[4] then
      if t.type == _M.TYPE_OBJECT then
        target = t[1]
        xProperty = t[2]
        converter = t[3]
        values = t[4]
       else 
        target = t[1]
        xProperty = t[2]
        yProperty = t[3]
        values = t[4]
      end
     elseif t[3] then
      target = t[1]
      xProperty = t[2]
      values = t[3]
     elseif t[2] then
      target = t[1]
      values = t[2]
    end
  end

  if getType(values) ~= "table" then
    values = {values}
  end 
 
  local animator

  if (converter && evaluator) then
    animator = ObjectAnimator[type]
      (target, xProperty, converter,
        evaluator, values)
 
   elseif (t.type == _M.TYPE_OBJECT &&
   (converter || evaluator)) then     
    animator = ObjectAnimator[type]
      (target, xProperty, converter or evaluator, values)

   elseif xProperty and yProperty then
    animator = ObjectAnimator[type]
      (target, xProperty, yProperty, values)

   elseif (t.type == _M.TYPE_POINT_F && xProperty) then
    animator = ObjectAnimatorUtils[type]
      (target, xProperty, values)

   elseif xProperty then
    animator = ObjectAnimator[type]
      (target, xProperty, values)

   else 
    animator = ObjectAnimator[type]
      (target, values)
  end

  for k, v in pairs(t) do
    switch k do
     case "autoCancel"
      animator.setAutoCancel(v)
     case "duration"
      animator.setDuration(v)
     case "durationScale"
      animator.setDurationScale(v)
     case "frameDelay"
      animator.setFrameDelay(v)
     case "currentFraction" 
      animator.setCurrentFraction(v)
     case "currentPlayTime" 
      animator.setCurrentPlayTime(v)
     case "evaluator" 
      if t.type ~= _M.TYPE_OBJECT then
       animator.setEvaluator(v)
      end
     case "interpolator" 
      animator.setInterpolator(v)
     case "repeatCount"
      animator.setRepeatCount(v)
     case "repeatMode"
      animator.setRepeatMode(v)
     case "startDelay"
      animator.setStartDelay(v)
     case 1, 2, 3, 4, 5, "target", "property", "xProperty",
      "yProperty", "converter", "values", "type", "start"
     default 
      error(tostring(animator)
        ..": ObjectAnimator does not support the property: "
        ..k, 0)
    end
  end

  if t.start then
    animator.start()
  end
  return animator
end

setmetatable(_M, _M)

return _M]]
mcode = [[import "java.lang.*","java.util.*"
import "android.os.*","android.app.*"

activity {
  Title = res.string.app_title,
  ContentView = res.layout.main
}
]]
lcode = [[import "android.widget.*", "androidx.appcompat.widget.*";

return {
  LinearLayout,
  orientation="vertical",
  layout_width="match",
  layout_height="match",
  gravity="center",
  {
    AppCompatTextView,
    text="Hello NeLuaJ+",
  },
}]]
icode = [[
ver_name = "1.0"
ver_code = "1"
min_sdk = "21"
target_sdk = "29"
debug_mode = true
NeLuaJ_Theme = "Theme_NeLuaJ_Compat"
user_permission = {
  "INTERNET",
  "WRITE_EXTERNAL_STORAGE"
}]]
build_problem=[[问题不明
建议打包后使用MT管理器制作共存后安装

下方填写的目录格式为 ..Projects/demo1
]]