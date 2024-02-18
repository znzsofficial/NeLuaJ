-- 一些方法（
local _M={}
local bindClass = luajava.bindClass
local tostring = tostring
local type = type
local table = table
local insert = table.insert
local concat = table.concat
local string = string
local format = string.format
local ipairs = ipairs

local LuaDrawable = bindClass "com.androlua.LuaDrawable"
local Paint = bindClass "android.graphics.Paint"
local MaterialAlertDialogBuilder = bindClass "com.google.android.material.dialog.MaterialAlertDialogBuilder"
local View = bindClass "android.view.View"
local ViewGroup = bindClass "android.view.ViewGroup"

local ColorError = ColorUtil.getColorError()

local selectForegroundDrawable = LuaDrawable(function(c,p)
  p.style = Paint.Style.STROKE
  p.setStrokeWidth(20)
  p.setStrokeJoin(Paint.Join.ROUND)
  p.color = ColorPrimary --边框
  c.drawRect(0,0,c.width,c.height,p)
  p.setTextSize(40)
  p.color = ColorPrimary--字体
  p.setStyle(Paint.Style.FILL)
  c.drawText(LayoutHelperActivity.data.current_view.class.getSimpleName(),20,50,p) --左上控件名称
  p.setTextSize(30)
  c.drawText(old_res.string.edit_quality, 20,85,p)
end)

local cancelSelectForegroundDrawable = LuaDrawable(function(c,p)
  p.style = Paint.Style.STROKE
  p.setStrokeWidth(20)
  p.setStrokeJoin(Paint.Join.ROUND)
  p.color = ColorError --边框
  c.drawRect(0,0,c.width,c.height,p)
  p.setTextSize(40)
  p.color = ColorError--字体
  p.setStyle(Paint.Style.FILL)
  c.drawText(LayoutHelperActivity.data.current_view.class.getSimpleName(),20,50,p) --左上控件名称
  p.setTextSize(30)
  c.drawText(old_res.string.cancel_select, 20,85,p)
end)

_M.setSelectForeground = function(view)
  view.setForeground(selectForegroundDrawable)
  return _M
end

_M.setCancelSelectForeground = function(view)
  view.setForeground(cancelSelectForegroundDrawable)
  return _M
end

local edit_view_dialog = MaterialAlertDialogBuilder(activity)

_M.showEditViewDialog = function(view)

  local view_name = view.class.getSimpleName()
  local methods = LayoutHelperActivity.method.getViewMethods(view)

  edit_view_dialog.setTitle(view_name)
  .setItems(methods,function(dialog,position)

    local value = methods[position+1]

    if type(value)=="userdata" then

      local text = tostring(value):gsub("% =% .*","")
      LayoutHelperActivity.event[text]()

     else
      LayoutHelperActivity.event[value]()
    end

  end)
  .show()

end

local function dumparray(arr)
  local ret={}
  table.insert(ret,"{\n")
  for k,v in ipairs(arr) do
    table.insert(ret,string.format("\"%s\";\n",v))
  end
  table.insert(ret,"};\n")
  return table.concat(ret)
end

_M.ret = {}

_M.dumpLayouttable = function(t)
  local ret = _M.ret
  insert(ret,"{\n")
  insert(ret,tostring(t[1].getSimpleName()..";\n"))
  for k,v in pairs(t) do
    if type(k)=="number" then
      --do nothing
     elseif type(v)=="table" then
      insert(ret,k.."="..dumparray(v))
     elseif type(v)=="string" then
      if v:find("[\"\'\r\n]") then
        insert(ret,format("%s=[==[%s]==];\n",k,v))
       else
        insert(ret,format("%s=\"%s\";\n",k,v))
      end
     else
      insert(ret,format("%s=%s;\n",k,tostring(v)))
    end
  end
  for k,v in ipairs(t) do
    if type(v)=="table" then
      _M.dumpLayouttable(v)
    end
  end
  insert(ret,"};\n")

  return concat(ret)
end

return _M