local assets = ASSETS or "app/src/main/assets/"
local Inline = assert(loadfile(assets .. "mods/agent/markdown/MarkdownInline.lua"))()
local function check(name, condition)
  assert(condition, name)
  print("PASS " .. name)
end
check("multiple backticks preserve nested tick", Inline.render("`` a ` b ``"):find("a ` b", 1, true))
check("balanced parentheses in link URL", Inline.render("[**docs**](https://example.com/a_(b))")
  == "<a href='https://example.com/a_(b)'><b>docs</b></a>")
check("code in link label", Inline.render("[`x`](https://example.com)"):find("<m-code>", 1, true))
check("escaped emphasis remains literal", Inline.render("\\*not italic\\*") == "*not italic*")
check("snake case remains literal", Inline.render("user_id_param") == "user_id_param")
check("code escapes HTML", Inline.render("`<x>`"):find("&lt;x&gt;", 1, true))
check("unclosed inline code remains literal", Inline.render("before ``after") == "before ``after")

-- Native table behavior, with strict view mocks rather than Android stubs.
local function view()
  local v = { children = {} }
  v.addView = function(child) v.children[#v.children + 1] = child end
  v.removeView = function(child)
    for i, c in ipairs(v.children) do if c == child then table.remove(v.children, i); break end end
  end
  v.setText = function(text) assert(text ~= nil); v.text = text end
  v.setOnClickListener = function(callback) v.click = callback end
  v.setMovementMethod = function(method) v.movement = method end
  v.getTypeface = function() return {} end
  return setmetatable(v, { __index = function(_, key)
    if key:match("^set") then return function() end end
    error("Unsupported mock method: " .. key)
  end })
end
local classes = {}
local env = setmetatable({
  activity = {}, res = { string = { ai_table_more = "More: %d" } },
  this = { dpToPx = function(n) return n end, themeUtil = {
    primary = { main = 1, onContainer = 2, container = 3 },
    surface = { container = 4, on = 5, onVariant = 6, containerLow = 7, containerHigh = 8 },
    outline = { variant = 9 },
  } },
  ColorUtils = { blendARGB = function() return 1 end },
  ["import"] = function() end,
  require = function(name)
    assert(name == "mods.agent.Markdown")
    return { renderInline = function(text) return Inline.render(text) end }
  end,
}, { __index = _G })
env.luajava = { bindClass = function(name)
  if not classes[name] then
    classes[name] = setmetatable({
      LayoutParams = function() return {} end,
      getInstance = function() return "links" end,
      CENTER = 1, RIGHT = 2, LEFT = 3,
    }, { __call = function() return view() end })
  end
  return classes[name]
end }
env.loadlayout = function(layout, ids)
  local function inflate(node)
    local v = view()
    if node.id then ids[node.id] = v end
    for i = 2, #node do v.addView(inflate(node[i])) end
    return v
  end
  return inflate(layout)
end
local chunk = assert(loadfile(assets .. "mods/agent/markdown/TableComponent.lua"))
for key, value in pairs(env) do _G[key] = value end
package.loaded["androidx.core.graphics.ColorUtils"] = env.ColorUtils
local Table = chunk()
local rows = {}
for i = 1, 65 do rows[i] = { "**row " .. i .. "**", "[docs](https://example.com)" } end
local card = Table.createTableView({ headers = { "A", "B" }, rows = rows }, false)
local root = card.children[1].children[1]
check("initial table contains header, 30 rows and more button", #root.children == 32)
check("table cells render inline Markdown", root.children[2].children[1].text == "<b>row 1</b>")
check("table links are interactive", root.children[2].children[2].movement == "links")
root.children[#root.children].children[1].click()
check("first expansion appends 30 rows", #root.children == 62)
root.children[#root.children].children[1].click()
check("every row accessible after expansion", #root.children == 66
  and root.children[66].children[1].text == "<b>row 65</b>")
print("ALL-PASS")
