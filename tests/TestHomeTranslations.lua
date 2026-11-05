-- Locale contracts are tested without loading an Android page or executing user projects.
local assets = ASSETS or "app/src/main/assets/"
local function read(path)
  local handle = assert(io.open(assets .. path, "rb"))
  local text = handle:read("*a")
  handle:close()
  return text
end
local function locale(name)
  local env, seen = {}, {}
  assert(load(read("res/string/init.lua"), "@string/init.lua", "t", env))()
  local text = read("res/string/" .. name .. ".lua")
  for key in ("\n" .. text):gmatch("\n([%a_][%w_]*)%s*=") do
    assert(not seen[key], name .. " duplicate translation: " .. key)
    seen[key] = true
  end
  local chunk = assert(load(text, "@" .. name .. ".lua", "t", env))
  chunk()
  return env
end
local zh, en = locale("zh"), locale("en")
local function formats(text)
  local result = {}
  for token in text:gsub("%%%%", ""):gmatch("%%[-+ #0]*%d*%.?%d*([cdiouxXeEfgGqs])") do
    result[#result + 1] = token
  end
  return table.concat(result, ",")
end
for key, value in pairs(zh) do
  assert(type(en[key]) == "string" and en[key] ~= "", "Missing English locale: " .. key)
  assert(formats(value) == formats(en[key]), "Format contract differs: " .. key)
end
for key in pairs(en) do assert(type(zh[key]) == "string", "Missing Chinese locale: " .. key) end
print("PASS locale keys and printf argument contracts agree in both languages")

for _, path in ipairs({
  "activities/home/ProjectsPage.lua", "activities/home/ConversationsPage.lua",
  "activities/home/HomeActivity.lua", "activities/main/CreateProject.lua",
  "activities/main/MainActivity.lua", "activities/main/TabletMode.lua", "res/layout/new_project.lua",
  "activities/projectcreate/Preview.lua", "activities/projectcreate/CreateProjectActivity.lua",
}) do
  local text = read(path)
  for key in text:gmatch("res%.string%.([%a_][%w_]*)") do
    assert(type(zh[key]) == "string" and type(en[key]) == "string", path .. " missing locale: " .. key)
  end
  for key in text:gmatch("S%.([%a_][%w_]*)") do
    assert(type(zh[key]) == "string" and type(en[key]) == "string", path .. " missing locale: " .. key)
  end
end
print("PASS home and editor literal resource references resolve in both languages")
package.path = assets .. "?.lua;" .. package.path
local templates = require "mods.project.templates.Registry"
for _, template in ipairs(templates.list()) do
  for _, key in ipairs({ template.titleKey, template.descriptionKey, "template_" .. template.id .. "_structure" }) do
    assert(type(zh[key]) == "string" and type(en[key]) == "string", "missing template locale: " .. key)
  end
end
print("PASS registered template labels and structure previews resolve in both languages")
print("ALL-PASS")
