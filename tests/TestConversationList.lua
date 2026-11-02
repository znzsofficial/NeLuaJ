local assets = ASSETS or "app/src/main/assets/"
local layouts = {}
local function widget()
  local v = {}
  return setmetatable(v, { __index = function(_, key)
    if key == "setText" then return function(text) v.text = text end end
    if key == "setOnClickListener" then return function(fn) v.click = fn end end
    if key == "setOnLongClickListener" then return function(fn) v.longClick = fn end end
    return function() return v end
  end })
end
luajava = { bindClass = function()
  return setmetatable({ LayoutParams = function() return {} end }, {__call=widget})
end }
local palette = {container=1,onContainer=2,containerLow=3,on=4,onVariant=5}
this = {themeUtil={primary=palette,surface=palette,error=palette},dpToPx=function(n)return n end}
activity = {}
res = {string={ai_unnamed_conv="Unnamed",ai_new_conv="New",ai_center_msg_count="%d messages",
  ai_row_usage="%s tokens",ai_conv_running="Running",ai_center_empty="Center empty"}}
package.loaded["mods.utils.TextUtil"] = {fmtTokens=tostring}
loadlayout = function(node, ids)
  layouts[#layouts + 1] = node
  ids.avatar, ids.badge = widget(), widget()
  return widget()
end
local list = assert(loadfile(assets .. "mods/agent/ConvList.lua"))()
local conv = {name="Example",messageCount=2,running=true,usage={tokens=3},updatedAt="2026-11-02"}
local opened, pressed
local card = list.buildRow(conv,"/projects/very-long-project-name",function(c,p) opened={c,p} end,function(c) pressed=c end)
local content = layouts[1][2]
local meta, badge = content[3][3], content[4]
assert(meta.singleLine == false and meta.layout_height == "wrap" and not meta.ellipsize)
assert(meta.text:find("very%-long%-project%-name"))
assert(badge.layout_height == "wrap" and badge.paddingTop == "4dp" and badge.paddingBottom == "4dp")
card.click(); assert(opened[1]==conv and opened[2]=="/projects/very-long-project-name")
assert(card.longClick() and pressed==conv)
local container = {children={}}
container.removeAllViews = function() container.children={} end
container.addView = function(v) table.insert(container.children,v) end
list.renderList(container, {}, nil, nil, {emptyText="No recent conversations"})
assert(container.children[1].text == "No recent conversations")
list.renderList(container, {})
assert(container.children[1].text == "Center empty")
list.renderList(container, {{conv={name="New",messageCount=0}}}, nil, nil, {emptyText="Recent empty"})
assert(container.children[1].text == "Recent empty")
local built = {}
list.buildRow = function(c) built[#built+1]=c; return c end
list.renderList(container, {{conv={name="Older",updatedAt="2025"}}, {conv=conv}})
assert(built[1]==conv and #built==2)
print("ALL-PASS")
