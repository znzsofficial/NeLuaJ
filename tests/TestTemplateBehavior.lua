local assets = ASSETS or "app/src/main/assets/"
package.path = assets .. "?.lua;" .. package.path
local Generator = require "mods.project.templates.Generator"
local generator = Generator.new({ fs = {
  checkRoot = function() return true end, exists = function() return false end,
} })
local function files(id)
  local preview = generator.preview({ templateId = id, appName = "Behavior",
    packageName = "com.example.behavior", rootPath = "/Projects" })
  assert(preview.ok, preview.error)
  local result = {}
  for _, file in ipairs(preview.files) do result[file.path] = file.content end
  return result
end
local function run(source, env, ...)
  return assert(load(assert(source), "generated", "t", setmetatable(env, { __index = _G })))(...)
end
local strings = setmetatable({}, { __index = function(_, key) return key end })
local function widget()
  local value = { text = "", checked = false, enabled = true }
  value.setText = function(text) value.text = text end
  value.getText = function() return value.text end
  value.setEnabled = function(enabled) value.enabled = enabled end
  value.setChecked = function(checked)
    value.checked = checked
    if value.change then value.change(value, checked) end
  end
  value.isChecked = function() return value.checked end
  value.setOnClickListener = function(callback) value.click = callback end
  value.setOnCheckedChangeListener = function(callback) value.change = callback end
  value.setError = function(err) value.error = err end
  value.setVisibility = function(visibility) value.visibility = visibility end
  value.setTextSize = function(size) value.size = size end
  value.requestFocus = function() value.focused = true end
  value.setIcon = function() end
  value.setContentDescription = function() end
  value.setTooltipText = function() end
  return value
end
local function viewsFor(names)
  local views = {}
  for name in names:gmatch("%S+") do views[name] = widget() end
  return views
end
local function uiEnv(views, modules)
  return { res = { string = strings }, require = function(name)
    if name == "app.screen" then return { show = function() return views end } end
    if name:match("^res.layout.") then return {} end
    return assert(modules[name], name)
  end }
end

-- Preferences: execute generated helper against a transactional host double.
local store, commits, fail = {}, 0, false
local prefs = {
  getBoolean = function(key, fallback)
    if store[key] == nil then return fallback end
    assert(type(store[key]) == "boolean", "wrong stored type")
    return store[key]
  end,
  edit = function()
    local pending = {}
    return {
      putBoolean = function(key, value) pending[key] = value end,
      commit = function()
        commits = commits + 1
        if fail then return false end
        store = pending
        return true
      end,
    }
  end,
}
local settingsFiles = files("settings")
local preferences = run(settingsFiles["app/preferences.lua"], {
  activity = { getSharedPreferences = function() return prefs end },
})
assert(preferences.load().friendly == true and preferences.load().large == false)
assert(preferences.save({ friendly = false, large = true }))
assert(preferences.load().friendly == false and preferences.load().large == true)
assert(not preferences.save({ friendly = "false", large = true }))
assert(not preferences.save({ friendly = true }))
assert(commits == 1, "invalid settings must not reach storage")
fail = true
assert(not preferences.save({ friendly = true, large = false }))
store.large = "broken"
assert(preferences.load() == nil, "corrupt preferences must not silently reset")

-- List UI: failed commits preserve input and revert a toggled checkbox; successful
-- mutations survive a fresh script run using the same persistence boundary.
local listFiles = files("list")
local stored, reject = {}, false
local tasks = {
  load = function() return stored end,
  save = function(nextTasks)
    if reject then return false end
    stored = nextTasks
    return true
  end,
}
local rows
local function openList()
  local views = viewsFor("status add empty task taskBox")
  views.rows = {
    removeAllViews = function() rows = {} end,
    addView = function(row) rows[#rows + 1] = row end,
  }
  local env = uiEnv(views, { ["app.tasks"] = tasks })
  env.luajava = { bindClass = function(name) return name end }
  env.loadlayout = function(layout, row)
    row.check, row.delete = widget(), widget()
    row.check.checked = layout[2].checked
    return row
  end
  run(listFiles["main.lua"], env)
  return views
end
local list = openList()
assert(list.empty.visibility == 0)
list.task.text = "  A task  "
reject = true
list.add.click()
assert(#stored == 0 and list.task.text == "  A task  " and list.status.text == "save_failed")
reject = false
list.add.click()
assert(stored[1].title == "A task" and list.task.text == "")
reject = true
rows[1].check.setChecked(true)
assert(rows[1].check.checked == false and stored[1].done == false)
reject = false
rows[1].check.setChecked(true)
list = openList()
assert(rows[1].check.checked == true)
rows[1].delete.click()
assert(#stored == 0 and list.empty.visibility == 0)

-- Store contract: invalid writes must be rejected before editing preferences.
local edits = 0
local taskStore = run(listFiles["app/tasks.lua"], {
  activity = { getSharedPreferences = function() return {
    edit = function() edits = edits + 1; error("unexpected write") end,
  } end },
  luajava = { bindClass = function() return function() return {
    put = function() end,
  } end end },
})
assert(not taskStore.save({ { title = "", done = false } }))
assert(not taskStore.save({ { title = "   ", done = false } }))
assert(not taskStore.save({ { title = string.rep("x", 121), done = false } }))
assert(not taskStore.save({ { title = "valid", done = "false" } }))
assert(not taskStore.save({ extra = { title = "valid", done = false } }))
local tooMany = {}
for i = 1, 101 do tooMany[i] = { title = "task", done = false } end
assert(not taskStore.save(tooMany))
assert(edits == 0, "invalid tasks must not reach storage")

-- Form validation and clear action execute the emitted entry point.
local form = viewsFor("clear submit name nameBox result")
local formEnv = uiEnv(form, {})
formEnv.luajava = { bindClass = function() return { drawable = { ic_menu_close_clear_cancel = 1 } } end }
formEnv.activity = { getDrawable = function() return {} end }
run(files("form")["main.lua"], formEnv)
form.name.text = "  "
form.submit.click()
assert(form.nameBox.error == "name_required")
form.name.text = string.rep("x", 41)
form.submit.click()
assert(form.nameBox.error == "name_too_long")
form.name.text = "  Ada  "
form.submit.click()
assert(form.result.text == "greeting_prefixAda!" and form.nameBox.error == nil)
form.clear.click()
assert(form.name.text == "" and form.result.text == "" and form.name.focused)

-- Navigation keeps the project-root path and the message argument intact.
local navigation = files("navigation")
local path, args
local routes = run(navigation["app/routes.lua"], { activity = {
  getLuaPath = function(relative) return "/project/" .. relative end,
  newActivity = function(p, a) path, args = p, a end,
} })
routes.openDetail("message")
assert(path == "/project/detail.lua" and args[1] == "message")
local detail = viewsFor("message back")
local detailEnv = uiEnv(detail, {})
local finished = false
detailEnv.activity = { finish = function() finished = true end }
run(navigation["detail.lua"], detailEnv, args[1])
assert(detail.message.text == "message")
detail.back.click()
assert(finished)

-- WebView lifecycle is instance-local, detached before destruction and safe
-- against late callbacks. Bundled resources are inlined without IO permissions.
local webFiles = files("webview")
local events, back, html = {}, nil, nil
local dead, detached = false, false
local web = {}
local function event(name)
  assert(not dead, "WebView used after destroy: " .. name)
  events[#events + 1] = name
end
web.getSettings = function() return setmetatable({}, { __index = function()
  return function() end
end }) end
web.setWebViewClient = function() end
web.loadDataWithBaseURL = function(_, contents) html = contents end
web.canGoBack = function() event("canGoBack"); return true end
web.goBack = function() event("back") end
web.onPause = function() event("pause") end
web.onResume = function() event("resume") end
web.stopLoading = function() event("stop") end
web.getParent = function() return { removeView = function(view)
  assert(view == web); detached = true
end } end
web.destroy = function() assert(detached); event("destroy"); dead = true end
local webViews = { web = web, status = widget() }
local webEnv = uiEnv(webViews, {})
webEnv.luajava = { bindClass = function() return function() return {} end end }
webEnv.activity = {
  getLuaPath = function(path) return path end,
  addOnBackPressedCallback = function(callback) back = callback end,
  finish = function() error("should navigate WebView history first") end,
}
webEnv.io = { open = function(path) return {
  read = function() return assert(webFiles[path], path) end, close = function() end,
} end }
run(webFiles["main.lua"], webEnv)
assert(html:find("<style>", 1, true) and html:find("<script>", 1, true))
assert(not html:find('src="app.js"', 1, true))
webEnv.onPause(); webEnv.onResume(); back(); webEnv.onDestroy()
assert(table.concat(events, ",") == "pause,resume,canGoBack,back,stop,destroy")
webEnv.onPause(); webEnv.onResume(); back(); webEnv.onDestroy()
assert(webViews.web == nil)

print("ALL-PASS TestTemplateBehavior (generated persistence, list, form, navigation, WebView)")
