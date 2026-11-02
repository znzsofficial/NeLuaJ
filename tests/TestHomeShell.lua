-- Real home host/layout modules; only Android/native shell and page IO boundaries are doubled.
local assets = ASSETS or "app/src/main/assets/"
package.path = assets .. "?.lua;" .. package.path
package.loaded["mods.bootstrap"] = true
_G["import"] = function() end
local permission, prepareCount, permissionRequests = false, 0, 0
local builds, refreshes, pauses, disposes, loads = {}, {}, {}, {}, {}
local function increment(t, key) t[key] = (t[key] or 0) + 1 end
local keys = { "projects", "conversations", "help", "settings" }
local names = { "ProjectsPage", "ConversationsPage", "HelpPage", "SettingsPage" }
for i, name in ipairs(names) do
  local key = keys[i]
  package.preload["activities.home." .. name] = function()
    increment(loads, key)
    return {
      build = function() increment(builds, key); return { key = key } end,
      refresh = function() increment(refreshes, key) end,
      pause = function() increment(pauses, key) end,
      dispose = function() increment(disposes, key) end,
    }
  end
end
package.loaded["mods.utils.AppInit"] = {
  prepareDirs = function() prepareCount = prepareCount + 1 end,
}
package.loaded["mods.utils.SystemBars"] = { apply = function() end }
local dialogCount, backCallbacks = 0, 0
MaterialAlertDialogBuilder = function()
  dialogCount = dialogCount + 1
  local d = {}
  for _, method in ipairs({"setTitle", "setMessage", "setPositiveButton", "setNegativeButton", "setCancelable", "show"}) do
    d[method] = function() return d end
  end
  return d
end
package.loaded["com.google.android.material.dialog.MaterialAlertDialogBuilder"] = MaterialAlertDialogBuilder
local colors = { getColorSurface = function() return 1 end,
  getColorSurfaceContainer = function() return 2 end }
this = {
  themeUtil = colors,
  checkStoragePermission = function() return permission end,
  requestStoragePermission = function() permissionRequests = permissionRequests + 1 end,
  addOnBackPressedCallback = function() backCallbacks = backCallbacks + 1 end,
}
R = { style = { Theme_NeLuaJ_Material3_DynamicColors_NoActionBar = 1 } }
android = { R = { string = { ok = "OK", cancel = "Cancel" } } }
res = { layout = { home_layout = "home" },
  string = { home_tab_projects = "Projects", home_tab_conversations = "Conversations",
    home_tab_help = "Help", home_tab_settings = "Settings", tip = "Tip",
    need_manage_permission = "Permission" }, drawable = function(icon) return icon end }
local shell
local function nativeShell()
  local nav = { setBackgroundColor = function() end }
  local value = { destinations = {}, requests = 0, disposed = false, selected = 1 }
  value.setBackgroundColor = function() end
  value.getBottomNav = function() return nav end
  value.getRail = function() return nav end
  value.getPager = function() return { getCurrentItem = function() return value.selected - 1 end } end
  value.addDestination = function(key, title, icon)
    value.destinations[#value.destinations + 1] = { key, title, icon }
  end
  value.bindPages = function() value.bound = true end
  value.requestVisibleRefresh = function() value.requests = value.requests + 1 end
  value.selectPage = function(key) for i, k in ipairs(keys) do if k == key then value.selected = i end end end
  value.selectTab = function(index) value.selected = index end
  value.pageContentReady = function(key) value.contentReady = key end
  value.dispose = function() value.disposed = true end
  shell = value
  return value
end
luajava = { bindClass = function(name)
  assert(name == "com.nekolaska.home.HomeShellView")
  return nativeShell
end }
activity = {
  setTheme = function() end, dynamicColor = function() end,
  getWindow = function() return { setSoftInputMode = function() end } end,
  setContentView = function() assert(loadfile(assets .. "res/layout/home_layout.lua"))() end,
}

assert(loadfile(assets .. "activities/home/HomeActivity.lua"))()
onCreate()
assert(dialogCount == 1 and prepareCount == 0)
assert(next(loads) == nil and next(refreshes) == nil, "shell creation must not load/scan offscreen pages")
assert(shell.bound and #shell.destinations == 4)
for i, key in ipairs(keys) do
  assert(shell.destinations[i][1] == key and shell.destinations[i][2] ~= "")
end
assert(backCallbacks == 0, "root Back must fall through to system")
assert(__homeBuildPage("projects").key == "projects")
assert(builds.projects == 1 and not refreshes.projects)
__homeRefreshPage("projects")
assert(refreshes.projects == 1 and prepareCount == 0)
__homeUi.requestStoragePermission()
assert(permissionRequests == 1)
onStorageRequestResult(false)
assert(dialogCount == 1, "denial must not immediately reopen forced dialog")
permission = true
onStorageRequestResult(true)
onResume()
assert(prepareCount == 1, "directory preparation must be once per host")
assert(not refreshes.conversations and not loads.conversations)
__homeUi.selectPage("settings")
assert(shell.selected == 4)
__homeUi.selectTab(2)
assert(shell.selected == 2)
__homeUi.pageContentReady("projects")
assert(shell.contentReady == "projects")
__homePausePage("projects")
__homeDisposePage("projects")
assert(pauses.projects == 1 and disposes.projects == 1)
local oldRefresh, oldVisible = __homeRefreshPage, __homePageVisible
onDestroy()
local destroyedShell = shell
assert(destroyedShell.disposed and __homeUi == nil)
oldRefresh("projects")
oldVisible("projects")
assert(refreshes.projects == 1, "late callbacks cannot refresh destroyed host")
assert(__homeBuildPage("projects") == nil)

-- A recreated host rebinds named factories; no creator from the old instance is reused.
assert(loadfile(assets .. "activities/home/HomeActivity.lua"))()
onCreate()
assert(shell ~= destroyedShell and __homeBuildPage("settings").key == "settings")
onResume()
assert(prepareCount == 2)
assert(not pcall(__homeBuildPage, "unknown"))

-- Real static page modules must release cached Views when their Fragment view dies.
local helpAdapters = {}
local function helpClass(name)
  if name == "com.androlua.adapter.LuaRecyclerAdapter" then return function(_, data, layout)
    local adapter = { data = data, layout = layout }
    helpAdapters[#helpAdapters + 1] = adapter
    return adapter
  end end
  if name == "androidx.recyclerview.widget.LinearLayoutManager" then return function() return {} end end
  return name
end
luajava.bindClass = helpClass
colors.getColorOnSurface = function() return 3 end
colors.getColorOnSurfaceVariant = function() return 4 end
colors.getColorPrimary = function() return 5 end
package.loaded["mods.utils.ActivityUtil"] = {}
package.loaded["mods.help.DocCatalog"] = {}
local wiringCount, inflateCount = 0, 0
package.loaded["mods.settings.SettingsWiring"] = {
  apply = function() wiringCount = wiringCount + 1 end,
}
loadlayout = function(layout, views)
  inflateCount = inflateCount + 1
  if views then
    views.docList = { setLayoutManager = function() end, setAdapter = function() end }
    views.pageHeader = { setId = function() end }
  end
  return { generation = inflateCount }
end
local helpPage = assert(loadfile(assets .. "activities/home/HelpPage.lua"))()
local helpView = helpPage.build()
assert(helpPage.build() == helpView)
helpPage.dispose()
assert(helpPage.build() ~= helpView, "re-created Help fragment must get a fresh, unparented View")
local settingsPage = assert(loadfile(assets .. "activities/home/SettingsPage.lua"))()
local settingsView = settingsPage.build()
assert(settingsPage.build() == settingsView and wiringCount == 1)
settingsPage.dispose()
assert(settingsPage.build() ~= settingsView and wiringCount == 2,
  "re-created Settings fragment must rewire new controls")

-- Actual Help keeps card/section data but only inflates a constant-size shell.
this.dpToPx = function(n) return n end
local openedDoc
package.loaded["mods.utils.ActivityUtil"] = { open = function(route, file) openedDoc = route .. ":" .. file end }
package.loaded["mods.help.DocCatalog"] = {
  { title = "Start", items = {
    { title = "Projects", desc = "A longer guide description", file = "home_en.html" },
    { title = "Config", desc = "Project settings", file = "init_lua_en.html" },
  } },
  { title = "Code", items = { { title = "Layouts", desc = "Layout reference", file = "module_loadlayout.html" } } },
}
luajava.bindClass = helpClass
local helpInflations = 0
loadlayout = function(node, target)
  helpInflations = helpInflations + 1
  local v = { node = node, children = {} }
  v.addView = function(child, params) child.params = params v.children[#v.children + 1] = child end
  v.setId = function(id) v.id = id end
  v.setLayoutManager = function(manager) v.manager = manager end
  v.setAdapter = function(adapter) v.adapter = adapter end
  for i = 2, #node do v.addView(loadlayout(node[i], target)) end
  if node.id and target then target[node.id] = v end
  return v
end
local populatedPage = assert(loadfile(assets .. "activities/home/HelpPage.lua"))()
local populatedHelp = populatedPage.build()
local docList = populatedHelp.children[2]
assert(docList.node.paddingLeft == "20dp")
local docs, docLayout = docList.adapter.data, docList.adapter.layout
assert(#docs == 3 and docs[1].section.visibility == 0 and docs[2].section.visibility == 8 and docs[3].section.text == "Code")
assert(docLayout.layout_marginBottom == "12dp" and docLayout[3].radius == "16dp")
assert(docLayout[3][2][3].maxLines == 2, "help descriptions retain their two-line space")
docs[1].docRow.onClick()
assert(openedDoc == "help:home_en.html")
local shellInflations = helpInflations
populatedPage.dispose()
local items = package.loaded["mods.help.DocCatalog"][1].items
for i = 1, 2000 do items[#items + 1] = { title = "Doc " .. i, desc = "Reference", file = "doc" .. i .. ".html" } end
populatedPage.build()
assert(helpInflations == shellInflations * 2, "catalog size must not increase shell View inflation count")
assert(#helpAdapters[#helpAdapters].data == 2003)
print("PERF Help: 3 vs 2003 documents -> identical shell View inflation count (row inflation remains RecyclerView-owned)")
print("ALL-PASS Home shell lazy binding, permission/lifecycle contracts and static view disposal")
