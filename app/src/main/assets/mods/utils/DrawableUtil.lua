local:bindClass
local:res
local BitmapDrawable = bindClass "android.graphics.drawable.BitmapDrawable";
-- local BitmapFactory = bindClass "android.graphics.BitmapFactory";
local PorterDuff = bindClass "android.graphics.PorterDuff";
local PorterDuffColorFilter = bindClass "android.graphics.PorterDuffColorFilter";
-- local FileInputStream = bindClass "java.io.FileInputStream";
local Resources = activity.getResources()
-- local luadir = activity.getLuaDir()
local _M = {}

_M.getFilter=function(color)
  return PorterDuffColorFilter(color, PorterDuff.Mode.SRC_ATOP)
end

_M.getDrawable = function(file,color)
  -- local fis = FileInputStream(luadir.."/res/drawable/"..file..".png")
  -- local drawable = BitmapDrawable(Resources, BitmapFactory.decodeStream(fis))
  local drawable = BitmapDrawable(Resources, res.bitmap[file])
  if color
    drawable.setColorFilter(_M.getFilter(color))
  end
  return drawable
end

return _M