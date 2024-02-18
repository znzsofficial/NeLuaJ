local bindClass = luajava.bindClass
local File = bindClass "java.io.File"
local const = table.const
local luadir = LayoutHelperActivity.data.this_project_lua_dir .. "/"
local drawableDir = luadir .. "res/drawable/"
local fontDir = luadir .. "res/font/"
local Drawable = bindClass "android.graphics.drawable.Drawable"
local Locale = bindClass "java.util.Locale"
local LuaBitmap = bindClass "com.androlua.LuaBitmap"
local LuaBitmapDrawable = bindClass "com.androlua.LuaBitmapDrawable"
local Typeface = bindClass "android.graphics.Typeface"

local function Meta(func)
  return setmetatable({},{__index=func})
end

local function loadFile(path)
  local file = io.open(path, "r")
  if file then
    local content = file:read("*a")
    file:close()
    return content
  end
  return nil
end

local function loadLuaFile(path, env)
  local content = loadFile(path)
  if content then
    local chunk, err = load(content, "@" .. path, "t", env or _G)
    if chunk then
      return chunk()
     else
      error(err)
    end
  end
  return nil
end

local res = {
  env = _G,
  language = Locale.default.language,
  orientation = activity.resources.configuration.orientation,
  drawable = Meta(function(_, key)
    local path = drawableDir .. key
    if File(path .. ".png").exists() == true then
      return Drawable.createFromPath(path .. ".png")
     elseif File(path .. ".jpg").exists() == true then
      return Drawable.createFromPath(path .. ".jpg")
     elseif File(path .. ".gif").exists() == true then
      return Drawable.createFromPath(path .. ".gif")
     elseif File(path .. ".lua").exists() == true then
      return loadLuaFile(path .. ".lua")
    end
    return nil
  end),
  bitmap = Meta(function(_, key)
    local path = drawableDir .. key
    if File(path .. ".png").exists() == true then
      return LuaBitmap.getBitmap(activity, path .. ".png")
     elseif File(path .. ".jpg").exists() == true then
      return LuaBitmap.getBitmap(activity, path .. ".jpg")
     elseif File(path .. ".gif").exists() == true then
      return LuaBitmap.getBitmap(activity, path .. ".gif")
     elseif File(path .. ".lua").exists() == true then
      return loadLuaFile(path .. ".lua")
    end
    return nil
  end),
  layout = Meta(function(_, key)
    return loadLuaFile(luadir.."res/layout/" .. key .. ".lua")
  end),
  view = Meta(function(_, key)
    return loadlayout(
    loadLuaFile(luadir.."res/layout/" .. key .. ".lua"),
    {}
    )
  end),
  font = Meta(function(_, key)
    local path = fontDir .. key
    if File(path .. ".ttf").exists() == true then
      return Typeface.createFromFile(path .. ".ttf")
     elseif File(path .. ".otf").exists == true then
      return Typeface.createFromFile(path .. ".otf")
    end
    return nil
  end)
}

local orients = const{
  [1] = "res/dimen/port.lua",
  [2] = "res/dimen/land.lua"
}

res.string = {}

local p = luadir .. "res/string/init.lua"
local defTable = {}
loadLuaFile(p,defTable)
for k, v in pairs(defTable) do
  res.string[k] = v
end

p = luadir .. "res/string/" .. res.language .. ".lua"
-- 如果当前语言文件不存在
if File(p).exists() == false then
  -- 从default.lua中读取默认语言
  res.defaultLanguage = loadLuaFile(luadir .. "res/string/default.lua")
  p = luadir .. "res/string/" .. res.defaultLanguage .. ".lua"
end
local langTable = {}
loadLuaFile(p,langTable)
for k, v in pairs(langTable) do
  res.string[k] = v
end
res.string = const(res.string)

res.dimen = {}

defTable = loadLuaFile(luadir .. "res/dimen/init.lua") or {}

for k, v in pairs(defTable) do
  res.dimen[k] = v
end

local dimTable = loadLuaFile(luadir .. orients[res.orientation]) or {}
for k, v in pairs(dimTable) do
  res.dimen[k] = v
end
res.dimen = const(res.dimen)



return res