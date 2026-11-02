-- Run the actual layout and wiring with Android host doubles, then operate rows.
local assets = ASSETS or "app/src/main/assets/"
local bindings, layouts, saved, views = {}, {}, {}, {}
local function widget()
  local v = {children={}}
  return setmetatable(v, {__index=function(_, key)
    if key == "isChecked" then return function() return v.checked == true end end
    if key == "setOnClickListener" then return function(fn) v.onClick=fn end end
    if key == "removeAllViews" then return function() v.children={} end end
    if key == "addView" then return function(child) v.children[#v.children+1]=child end end
    if key == "post" then return function(fn) fn() end end
    if key == "requestFocus" then return function() v.focused=true end end
    if key == "performAccessibilityAction" then return function(action) v.accessibilityAction=action end end
    if key == "getResourceId" then return function() return 1 end end
    return function() return v end
  end})
end
local classes = {}
luajava = {bindClass=function(name)
  if name == "com.nekolaska.widget.SettingsAccessibility" then
    return {bindSwitch=function(row,toggle) bindings[#bindings+1]={row,toggle} end}
  end
  if name == "android.graphics.Color" then
    return {argb=function() return 1 end,alpha=function()return 255 end,red=function()return 0 end,
      green=function()return 0 end,blue=function()return 0 end}
  end
  if name == "com.google.android.material.R" then return {style={Widget_Material3_TextInputLayout_OutlinedBox=1}} end
  if not classes[name] then classes[name]=setmetatable({OnClickListener=function(v)return v end}, {__call=widget}) end
  return classes[name]
end}
_G["import"] = function(name)
  if name == "android.widget.*" then
    for _, suffix in ipairs({"LinearLayout","ScrollView"}) do _G[suffix]=luajava.bindClass("android.widget."..suffix) end
  else
    _G[name:match("[^.]+$")] = luajava.bindClass(name)
  end
end
local strings=setmetatable({function_bar_move_up="Move %s up",function_bar_move_down="Move %s down"},
  {__index=function(_,k)return k end})
res={string=strings,drawable=function(name)return name end}
android={R={attr={selectableItemBackground=1,selectableItemBackgroundBorderless=2},string={ok=1,cancel=2}}}
this={
  themeUtil=setmetatable({}, {__index=function() return function()return 1 end end}),
  getSharedData=function(key,fallback) if key==nil then return saved end; if saved[key]==nil then return fallback end; return saved[key] end,
  setSharedData=function(key,value)saved[key]=value end,
  dpToPx=function(n)return n end,
  getVersionName=function()return "test" end,
}
activity={obtainStyledAttributes=function()return widget() end}
for _,name in ipairs({
  "android.widget.ScrollView", "android.widget.LinearLayout", "android.widget.FrameLayout",
  "android.widget.SeekBar", "android.widget.CheckBox", "android.widget.Button",
  "androidx.appcompat.widget.AppCompatImageView", "androidx.appcompat.widget.AppCompatImageButton",
  "android.graphics.Bitmap", "android.graphics.Canvas", "android.graphics.Paint", "android.graphics.drawable.BitmapDrawable",
  "vinx.material.textfield.MaterialTextField", "com.google.android.material.textview.MaterialTextView",
  "com.google.android.material.divider.MaterialDivider", "com.google.android.material.card.MaterialCardView",
  "com.google.android.material.checkbox.MaterialCheckBox",
  "com.google.android.material.materialswitch.MaterialSwitch",
}) do
  package.loaded[name]=luajava.bindClass(name)
  _G[name:match("[^.]+$")]=package.loaded[name]
end
loadlayout=function(node, target)
  target=target or _G
  layouts[#layouts+1]=node
  local function build(n)
    local v=widget(); v.node=n
    views[#views+1]=v
    for key,value in pairs(n) do if type(key)=="string" then v[key]=value end end
    if n.id then target[n.id]=v end
    for i=2,#n do v.children[#v.children+1]=build(n[i]) end
    return v
  end
  return build(node)
end
package.loaded["mods.utils.RunKeyConfig"]={getMode=function()return "off" end,label=function()return "Off" end}
package.loaded["mods.utils.RunWindowConfig"]={getMode=function()return "off" end,label=function()return "Off" end}
package.loaded["mods.utils.EditorUtil"]={notifyPrefsChanged=function()end}
package.loaded["activities.main.TabletMode"]={isLargeScreen=function()return false end}
package.loaded["mods.utils.FunctionBarConfig"]=assert(loadfile(assets.."mods/utils/FunctionBarConfig.lua"))()
loadlayout(assert(loadfile(assets.."res/layout/setting_layout.lua"))())
assert(FunctionBarItem.node[3].layout_width == "0dp" and FunctionBarItem.node[3].layout_weight == 1,
  "settings text must share the remaining width with its icon, not overflow a match-parent column")
assert(FunctionBarItem.node[3][3].layout_marginTop == "4dp")
local group = layouts[1][2][4]
assert(group.radius == "16dp" and group.layout_marginLeft == "20dp", "home settings keeps the shared gutter and shape scale")
assert(loadfile(assets.."mods/settings/SettingsWiring.lua"))().apply()
assert(#bindings==8, "every settings switch must install the supported native delegate")
for _, pair in ipairs(bindings) do
  local row,toggle=pair[1],pair[2]
  assert(type(row.contentDescription)=="string" and #row.contentDescription>0)
  assert(row.minimumHeight=="48dp")
  local old=toggle.checked
  row.onClick(); assert(toggle.checked~=old, "row click did not toggle the controlled switch")
end
assert(saved.tablet_mode==true and saved.editor_magnifier==false)
FunctionBarItem.onClick()
local rows={}
for _,node in ipairs(layouts)do if node[2] and node[2].id=="enabled" then rows[#rows+1]=node end end
assert(#rows>2)
local first=rows[1]
assert(first[2].text=="save_file" and first[2].minHeight=="48dp", "checkbox must carry its visible label")
assert(first[3].layout_width=="48dp" and first[4].layout_height=="48dp")
assert(first[3].src=="s_up" and first[4].src=="s_down")
assert(first[3].enabled==false and first[4].enabled==true)
assert(first[4].contentDescription=="Move save_file down")
first[4].onClick()
local after={}
for _,node in ipairs(layouts)do if node[2] and node[2].id=="enabled" then after[#after+1]=node end end
assert(after[#rows+1][2].text=="backup", "reorder did not operate the actual list")
assert(after[#rows+2][2].text=="save_file")
-- Confirm rebuilt control receives keyboard AND accessibility focus.
local focused
for _,v in ipairs(views)do if rawget(v,"focused") then focused=v end end
assert(focused and focused.id=="down" and focused.accessibilityAction==64)
after[#rows+2][3].onClick()
for _,v in ipairs(views)do if rawget(v,"focused") then focused=v end end
assert(focused.id=="enabled" and focused.text=="save_file" and focused.accessibilityAction==64,
  "reaching the boundary must focus the same item's checkbox, not a disabled button")
local function checkSp(node)
  if node.textSize then assert(not tostring(node.textSize):match("dp$"), "dialog text ignores font scaling") end
  for i=2,#node do checkSp(node[i]) end
end
SymbolBarItem.onClick(); CustomApp.onClick()
for _,node in ipairs(layouts)do checkSp(node) end
print("ALL-PASS")
