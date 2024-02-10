-- 传入 View(Group) 返回方法表
local _M={}
local table = table
local insert = table.insert
local find = table.find
local remove = table.remove
local copy = table.copy
local sort = table.sort
local luajava = luajava
local instanceof = luajava.instanceof
local bindClass = luajava.bindClass
local ipairs = ipairs
local utf8 = utf8
local len = utf8.len
local tostring = tostring
local old_res = old_res
local type = type

import "android.widget.*"
import "androidx.appcompat.widget.*"
local View = bindClass "android.view.View"
local ViewGroup = bindClass "android.view.ViewGroup"
local SpannableString = bindClass "android.text.SpannableString"
local ForegroundColorSpan = bindClass "android.text.style.ForegroundColorSpan"
local Spannable = bindClass "android.text.Spannable"
local StyleSpan = bindClass "android.text.style.StyleSpan"
local Typeface = bindClass "android.graphics.Typeface"
local Spanned = bindClass "android.text.Spanned"

local getViewMethods = function(view,...)
  local t
  switch view
   case "ViewGroup"
    t = {
      "•"..old_res.string.add,"•"..old_res.string.delete,"•"..old_res.string.parent_view,"•"..old_res.string.child_view,--[["•"..old_res.string.other_methods,]]
      "id",
      "layout_width",
      "layout_height",
      "layout_gravity",
      "onClick",
      "onLongClick",
      "background",
      "backgroundColor",
      "gravity",
      "visibility",
      "alpha",
      "layout_margin",
      "layout_marginLeft",
      "layout_marginTop",
      "layout_marginRight",
      "layout_marginBottom",
      "padding",
      "paddingLeft",
      "paddingTop",
      "paddingRight",
      "paddingButtom",
      "Ration",
      "RationX",
      "RationY",
      "Elevation",
      "Clickable",
      "Enabled",
      "LayoutTransition",
      ...
    }
   case "View"
    t = {
      "•"..old_res.string.delete,"•"..old_res.string.parent_view,--[["•"..old_res.string.other_methods,]]
      "id",
      "layout_width",
      "layout_height",
      "layout_gravity",
      "onClick",
      "onLongClick",
      "background",
      "backgroundColor",
      "gravity",
      "visibility",
      "alpha",
      "layout_margin",
      "layout_marginLeft",
      "layout_marginTop",
      "layout_marginRight",
      "layout_marginBottom",
      "padding",
      "paddingLeft",
      "paddingTop",
      "paddingRight",
      "paddingButtom",
      "Ration",
      "RationX",
      "RationY",
      "Elevation",
      "Clickable",
      "Enabled",
      ...
    }
  end
  --table.sort(t)
  return t
end

_M.LinearLayout = getViewMethods("ViewGroup",
"orientation"
)

_M.TextView = getViewMethods("View",
"text",
"textColor",
"textSize",
"textStyle",
"singleLine",
"ellipsize"
)

_M.EditText = getViewMethods("View",
"text",
"textColor",
"textSize",
"textStyle",
"singleLine",
"hint",
"hintTextColor",
"error"
)

_M.ImageView = getViewMethods("View",
"src",
"scaleType",
"ColorFilter",
"MaxWidth",
"MaxHeight",
"ImageAlpha"
)

_M.RelativeLayoutChildView = getViewMethods("View",
"layout_above",
"layout_alignBaseline",
"layout_alignBottom",
"layout_alignEnd",
"layout_alignLeft",
"layout_alignParentBottom",
"layout_alignParentEnd",
"layout_alignParentLeft",
"layout_alignParentRight",
"layout_alignParentStart",
"layout_alignParentTop",
"layout_alignRight",
"layout_alignStart",
"layout_alignTop",
"layout_alignWithParentIfMissing",
"layout_below",
"layout_centerHorizontal",
"layout_centerInParent",
"layout_centerVertical",
"layout_toEndOf",
"layout_toLeftOf",
"layout_toRightOf",
"layout_toStartOf"
)

local function replaceKeys(t1, t2)
  local newTable = copy(t1)
  for k,v : t2 do
    if type(k) != "number" then
      local i = find(newTable,k)
      if i then
        remove(newTable,i)
      end
      local s = k.." = "..tostring(v)
      local start_len = len(k.." = ")
      local end_len = len(s)
      local spanned = Spanned.SPAN_EXCLUSIVE_EXCLUSIVE

      local spannableString = SpannableString(s)
      spannableString.setSpan(ForegroundColorSpan(ColorPrimary),start_len,end_len,spanned)
      spannableString.setSpan(StyleSpan(Typeface.BOLD),start_len,end_len,spanned)

      insert(newTable, spannableString)
    end
  end
  return newTable
end

local compareData = function(a,b)
  return tostring(a)<tostring(b) -- tostring 是因为 spannableString
end

_M.getViewMethods =function(view)

  local t

  if instanceof(view, LinearLayout) then
    t = _M.LinearLayout
   elseif instanceof(view, ViewGroup) then
    t = getViewMethods("ViewGroup")
   elseif instanceof(view,EditText) then
    t = _M.EditText
   elseif instanceof(view, TextView) then
    t = _M.TextView
   elseif instanceof(view, ImageView) then
    t = _M.ImageView
   else
    t = getViewMethods("View")
  end

  local p = view.getParent()

  if instanceof(p,LinearLayout) or instanceof(p,LinearLayoutCompat) then
    if not find(t,"layout_weight") then
      insert(t,"layout_weight")
    end
   elseif instanceof(p,AbsoluteLayout) then
    if not find(t,"layout_x") then
      insert(t,"layout_x")
    end
    if not find(t,"layout_y") then
      insert(t,"layout_y")
    end
   elseif instanceof(p,RelativeLayout) then
    t = _M.RelativeLayoutChildView
  end

  t = replaceKeys(t, view.Tag)

  sort(t,compareData)

  collectgarbage("collect") -- 清个内存

  return t

end

return _M