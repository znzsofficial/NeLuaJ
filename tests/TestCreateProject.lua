local assets = ASSETS or "app/src/main/assets/"
package.path = assets .. "?.lua;" .. package.path
local files, notices, calls, binding, dialog, button = {}, {}, {}, nil, nil, nil
local openAfter, failWrite = true, false
local function field(text, checked)
  local v = { text = text or "", checked = checked == nil and false or checked }
  v.setText = function(t) v.text = t end
  v.isChecked = function() return v.checked end
  v.setChecked = function(b) v.checked = b end
  v.setOnCheckedChangeListener = function() end
  v.addTextChangedListener = function() end
  return v
end
local function FileDouble(path)
  return { exists = function() return files[path] ~= nil end, mkdirs = function() return true end,
    isFile = function() return files[path] ~= nil end }
end
local function DialogDouble()
  local d = { dismissed = false }
  for _, name in ipairs({ "setTitle", "setView", "setPositiveButton", "setNegativeButton" }) do
    d[name] = function() return d end
  end
  d.create = function() return d end
  d.setOnShowListener = function(fn) d.onShow = fn end
  d.getButton = function() return button end
  d.dismiss = function() d.dismissed = true end
  d.show = function() d.onShow() end
  dialog, button = d, {}
  return d
end
_G["import"] = function(name)
  if name == "java.io.File" then File = FileDouble else MaterialAlertDialogBuilder = DialogDouble end
end
package.preload["java.io.File"] = function() return FileDouble end
package.preload["com.google.android.material.dialog.MaterialAlertDialogBuilder"] = function() return DialogDouble end
luajava = { bindClass = function(name)
  if name == "android.content.DialogInterface" then return { BUTTON_POSITIVE = -1 } end
  return function(value) return value end
end }
this, Bean, android = {}, { Path = { app_root_pro_dir = "/Projects" } }, { R = { string = { ok = "ok", cancel = "cancel" } } }
res = { string = setmetatable({}, { __index = function(_, key) return key end }), layout = { new_project = "new_project" } }
loadlayout = function(_, b)
  binding = b
  for _, id in ipairs({ "project_appName", "project_packageName", "project_path_preview" }) do b[id] = field() end
  for _, id in ipairs({ "theme_m3", "theme_m3_dyn", "theme_m2", "theme_m1" }) do b[id] = field() end
  b.project_open_after = field("", openAfter)
  b.project_sample_ui, b.project_internet, b.project_debug_mode = field("", true), field("", true), field("", true)
  return {}
end
LuaFileUtil = { create = function(path, text)
  if failWrite then error("write failed") end
  files[path] = text
  -- Deliberately Unit/nil like the production Kotlin API, not a chainable fake.
end }
package.loaded["mods.utils.PathManager"] = { updateDir = function(path) calls.fallback = path end }
package.loaded["mods.utils.ActivityUtil"] = { assetsRoot = function() return "/assets" end }
package.loaded["mods.utils.EditorUtil"] = { load = function(path) calls.file = path end }
filetab = { setPath = function(path) calls.tab = path end }
MainActivity = { RecyclerView = { update = function() calls.refresh = true end } }
local Create = require "activities.main.CreateProject"
local function show(deps)
  files, notices, calls = {}, {}, {}
  deps = deps or {}
  deps.snack = function(text) notices[#notices + 1] = text end
  Create.show(deps)
  return function() button.onClick() end
end
local notified, opened
local click = show({ onCreated = function(path, checked) notified = { path, checked } end,
  openProject = function(path) opened = path return true end })
click()
assert(dialog.dismissed and files["/Projects/demo1/init.lua"] and files["/Projects/demo1/res/layout/main.lua"], table.concat(notices, "\n"))
assert(notified[1] == "/Projects/demo1" and notified[2] == true and opened == notified[1])
assert(calls.fallback == nil and calls.file == nil, "host navigation excludes editor fallback")
openAfter, opened, notified = false, nil, nil
click = show({ onCreated = function(path, checked) notified = { path, checked } end,
  openProject = function() error("must not open") end })
click()
assert(notified[2] == false and opened == nil and calls.fallback == nil)
openAfter = true
click = show()
click()
assert(calls.fallback == "/Projects/demo1" and calls.file == "/Projects/demo1/main.lua")
click = show({ openProject = function() return false end })
click()
assert(notices[#notices] == "home_open_failed" and not calls.fallback)
click = show({ openProject = function() error("navigation unavailable") end })
click()
assert(notices[#notices]:find("navigation unavailable", 1, true) and not calls.fallback)
failWrite = true
click = show({ onCreated = function() error("must not notify failed creation") end })
click()
assert(not dialog.dismissed and notices[#notices]:find("project_create_failed", 1, true))
print("ALL-PASS TestCreateProject")
