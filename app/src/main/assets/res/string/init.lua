about_this = [[
还没有写完，不建议外传（]]
code_class = [[-- 定义一个不变对象作为 null
null = setmetatable({},{
  __tostring = (lambda () -> "null"),
  __type = (lambda () -> "null"),
  __call = (lambda () -> nil),
  __newindex = (lambda () -> nil),
  __index = (lambda () -> nil),
  __len = (lambda () -> nil),
  __concat = (lambda () -> nil),
  __metatable = false,
})

-- 定义一个函数，用于创建类
function class(def)
  -- 创建一个空的表，用于存储类
  local cls = {}

  -- 设置索引元方法，指向类本身
  cls.__index = cls
  -- 设置类名，如果没有提供，则默认为 Unnamed
  cls.__name = type(def.name) == "string"
  && def.name
  || "Unnamed"
  -- 设置初始化函数，如果没有提供，则默认为空
  cls.__init = type(def.init) == "function"
  && def.init
  || null
  -- 设置 open 修饰符，如果没有提供，则默认为 false
  cls.__open = def.open
  || false
  -- 设置 static 修饰符，如果没有提供，则默认为 false
  cls.__static = def.static
  || false
  -- 设置类型函数，用于返回字符串 "class"
  cls.__type = lambda
  () -> "class"
  -- 设置 tostring 元方法，用于显示类名
  cls.__tostring = lambda
  (self) -> "class " .. self.__name
  -- 设置相等性的比较函数，只比较类名是否相同
  cls.__eq = function(self, other)
    if not type(other) == "class" then
      return false
    end
    return rawequal(self, other)
    || (getmetatable(self).__name == getmetatable(other).__name)
  end
  -- 设置 call 元方法，用于创建实例
  cls.__call = function(self, ...)
    -- 如果是静态类，则报错
    if self.__static then
      error("InstantiationException : Attempt to instantiate a static class ".. self.__name)
    end
    return self:__constructor(...)
  end

  -- 判断是否继承自另一个类
  if type(def.extend) == "class" then
    -- 判断是否使用 open 修饰符
    if not def.extend.__open then
      error("InvalidExtendException : Attempt to extend a final class " .. def.extend.__name)
    end
   elseif def.extend
    && def.extend ~= null then
    -- 如果父类为 Jvm 类，则报错
    if luajava.instanceof(def.extend, luajava.bindClass"java.lang.Class") then
      error("InvalidExtendException : Attempt to extend a Jvm class : " .. def.extend)
    end
    -- 如果父类不是一个 class，则报错
    error("InvalidExtendException : Attempt to extend a " .. type(def.extend))
  end

  -- 设置元表，用于处理类的各种操作
  setmetatable(cls, {
    __index = def.extend,
    __tostring = cls.__tostring,
    __call = cls.__call,
    __eq = cls.__eq,
    __type = cls.__type,
  })

  -- 静态类和非静态类分别处理
  if not cls.__static then

    -- 给非静态类设置实例构造器
    function cls:__constructor(...)
      -- 设置实例对象的元表
      local __mt = table.clone(self)
      math.randomseed(tostring(os.time()):reverse():sub(1, 6))
      __mt.__id = math.random(1, 1000000000)
      __mt.__tostring = lambda
      (self) -> self.__name.." @"..self.__id
      __mt.__type = lambda
      () -> "object"
      __mt.__eq = function(self, other)
        if not type(other) == "object" then
          return false
        end
        return rawequal(self, other)
        || (getmetatable(self).__name == getmetatable(other).__name)
      end
      __mt.__call = lambda
      (self) -> error("ObjectCallException : Attempt to call a object " .. tostring(self))

      -- 创建一个空表，作为实例对象
      local instance = setmetatable({}, __mt)

      -- 如果存在初始化函数，则调用
      if type(self.__init) == "function" then
        -- 处理父类初始化函数
        local super = def.extend
        && type(def.extend.__init) == "function"
        && function(...)
          return def.extend.__init(instance, ...)
        end
        -- 如果存在，则传递给子类
        if super then
          self.__init(instance, super, ...)
         else
          self.__init(instance, ...)
        end
      end

      -- 返回实例
      return instance
    end

    -- 使用 fields 表定义类的字段
    if type(def.fields) == "table" then
      for name, field in pairs(def.fields) do
        if cls[name] and cls[name] ~= null then
          error("RedefinedVariableException : Attempt to assign a defined value " .. name)
        end
        cls[name] = field
      end
    end

    -- 使用 final 表定义final变量
    if type(def.final) == "table" then
      cls.__final = setmetatable({},{__newindex = function(table, key, value)
          -- 拦截对不存在的索引的赋值操作
          error("FinalTableModificationException : Attempt to modify the final table.")
        end
      })
      for name, v in pairs(def.final) do
        rawset(cls.__final, name, v)
        cls["get"..name] = lambda
        (self) -> self.__final[name]
      end
    end

    -- 使用 methods 表定义类的方法
    if type(def.methods) == "table" then
      for name, fn in pairs(def.methods) do
        if not type(fn) == "function" then
          error("InvalidMethodException : Method must be a function or a lambda expression")
         elseif cls[name] and cls[name] ~= null then
          error("RedefinedVariableException : Attempt to assign a defined value " .. name)
        end
        cls[name] = fn
      end
    end

    -- 使用 overrides 表重写父类方法
    if type(def.overrides) == "table" and def.extend then
      for name, fn in pairs(def.overrides) do
        local super = rawget(def.extend, name)
        if super then
          -- 如果父类中也存在该方法，则将它包装起来，并传递给子类的函数
          cls[name] = function(self, ...)
            return fn(self, function(...)
              return super(self, ...)
            end, ...)
          end
         else
          error("MethodNotFoundException : Can not find method " .. name .. " in base class")
        end
      end
    end

   else
    -- 静态类

    -- 使用 fields 表定义类的字段
    if type(def.fields) == "table" then
      for name, field in pairs(def.fields) do
        if cls[name] and cls[name] ~= null then
          error("RedefinedVariableException : Attempt to assign a defined value " .. name)
        end
        cls[name] = field
      end
    end
    -- 使用 methods 表定义类的方法
    if type(def.methods) == "table" then
      for name, fn in pairs(def.methods) do
        if not type(fn) == "function" then
          error("InvalidMethodException : Method must be a function or a lambda expression")
         elseif cls[name] and cls[name] ~= null then
          error("RedefinedVariableException : Attempt to assign a defined value " .. name)
        end
        cls[name] = fn
      end
    end
    -- 如果有初始化函数就执行一下
    if type(def.init) == "function"
      def.init(cls)
    end

  end
  -- 返回创建的类
  return cls
end

return class]]
code_fragment=[[-- create on 2022/8/14 / ikimasho
-- please fix if there's something wrong

import "android.os.Bundle"
import "androidx.fragment.app.Fragment"

local LuaFragment={}
LuaFragment.__index = LuaFragment

local function BaseFragment(t)
  return Fragment.override(t)()
end

local create = function()
  local self = { interface = nil }
  self.fragment = "override the fragment"
  return setmetatable(self, LuaFragment)
end

function LuaFragment.newInstance(self)
  local bundle = Bundle()
  self.fragment = BaseFragment(self.interface)
  self.fragment.setArguments(bundle)
  return self.fragment
end

function LuaFragment.initCreator(self, creator)
  assert(type(creator) == "table", "required a table")
  -- so we override the interface here
  self.interface = {
    -- this looks so fucking ugly i dont like it
    onCreate = function(super, savedInstanceState)
      if creator.onCreate then creator.onCreate(savedInstanceState) end
      super(savedInstanceState)
    end,
    onCreateView = function(super, inflater, container, savedInstanceState)
      -- here we create our view
      if not creator.onCreateView then
        error("please override onCreateView")
       else
        return creator.onCreateView(inflater, container, savedInstanceState)
      end
      return super(inflater, container, savedInstanceState)
    end,
    onActivityCreated = function(super, savedInstanceState)
      super(savedInstanceState)
      if creator.onActivityCreated then creator.onActivityCreated(savedInstanceState) end
    end,
    onViewCreated = function(super, view, savedInstanceState)
      super(view, savedInstanceState)
      if creator.onViewCreated then creator.onViewCreated(view, savedInstanceState) end
    end,
    onViewStateRestored = function(super, savedInstanceState)
      super(savedInstanceState)
      if creator.onViewStateRestored then creator.onViewStateRestored(savedInstanceState) end
    end,
    onSaveInstanceState = function(super, outState)
      super(outState)
      if creator.onSaveInstanceState then creator.onSaveInstanceState(outState) end
    end,
    onConfigurationChanged = function(super, newConfig)
      super(newConfig)
      if creator.onConfigurationChanged then creator.onConfigurationChanged(newConfig) end
    end,
    onAttach = function(super, context)
      super(context) if creator.onAttach then creator.onAttach(context) end
    end,
    onStart = function(super)
      super() if creator.onStart then creator.onStart() end
    end,
    onResume = function(super)
      super() if creator.onResume then creator.onResume() end
    end,
    onStop = function(super)
      super() if creator.onStop then creator.onStop() end
    end,
    onDestroyView = function(super)
      super()
      if creator.onDestroyView then creator.onDestroyView() end
    end,
    onDestroy = function(super)
      super() if creator.onDestroy then creator.onDestroy() end
    end,
    onDetach = function(super)
      super() if creator.onDetach then creator.onDetach() end
    end
  }
end

return create
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
import "androidx.appcompat.app.*"

activity
.setTitle(res.string.app_title)
.setContentView(res.layout.main);
]]
lcode = [[import "android.widget.*";
import "androidx.appcompat.widget.*";

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
ver_name="1.0"
ver_code="1"
developer="dev"
description="a luaj application"
NeLuaJ_Theme="Theme_NeLuaJ_Compat"
debug_mode=true
user_permission={
  "INTERNET",
  "WRITE_EXTERNAL_STORAGE"
}]]
build_problem=[[问题不明
建议打包后使用MT管理器制作共存后安装

下方填写的目录格式为 ..Projects/demo1
]]