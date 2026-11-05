local assets = ASSETS or "app/src/main/assets/"
package.path = assets .. "?.lua;" .. package.path
local memory, refs, serial = {}, {}, 0
local realOpen = io.open
io.open = function(path, mode)
  if mode ~= "rb" then return realOpen(path, mode) end
  if not memory[path] then return nil, "not found", 2 end
  return { read = function() return memory[path] end, close = function() end }
end
local background, reads, permission, denied = false, 0, true, 0
local rootType, scanFails = "directory", false
local entries = { { name = "Older", isDir = true, mtime = 9000 }, { name = "Newer", isDir = true, mtime = 1 } }
local sources = {
  ["/Projects/Older/init.lua"] = 'app_name="Reader"\npackage_name="com.example.reader"',
  ["/Projects/Newer/init.lua"] = 'appname="Writer"\npackage_name="com.example.writer"',
}
local util = {
  replaceText = function(path, content) memory[path] = content return true end,
  listMeta = function() assert(background, "scan must run off UI") if scanFails then error("EIO") end return entries end,
  lastModified = function() return 100 end,
}
local allViews, jobs, adapters, notices, nav = {}, {}, {}, {}, {}
local inflations, drawables = 0, 0
local pendingWritable, createDeps, shownDialog = true, nil, nil
local function view()
  local v = { text = "", visibility = 0, children = {} }
  v.setText = function(t) v.text = t if v.watcher then v.watcher.afterTextChanged(t) end end
  v.setError = function(t) v.error = t end
  v.getText = function() return v.text end
  v.setVisibility = function(x) v.visibility = x end
  v.setEnabled = function(x) v.enabled = x end
  v.setHint = function() end
  v.setTextSize = function() end
  v.setSingleLine = function() end
  v.setId = function(id) v.id = id end
  v.setSaveEnabled = function(enabled) v.saveEnabled = enabled end
  v.setFreezesText = function(enabled) v.freezesText = enabled end
  v.addView = function(child, params) child.params = params v.children[#v.children + 1] = child end
  v.removeAllViews = function() v.children = {} end
  v.setLayoutManager = function() end
  v.setAdapter = function(a) v.adapter = a end
  v.addTextChangedListener = function(w) v.watcher = w end
  return v
end
local classCache = {}
local function makeDialog()
  local d = {}
  for _, name in ipairs({ "setTitle", "setMessage", "setView", "setNegativeButton" }) do d[name] = function() return d end end
  d.setPositiveButton = function(_, callback) d.positive = callback return d end
  d.create = function() return d end
  d.setView = function(content) d.content = content return d end
  d.setOnShowListener = function(callback) d.onShow = callback end
  d.getButton = function() return d.button end
  d.button = view()
  d.show = function() shownDialog = d if d.onShow then d.onShow() end end
  d.isShowing = function() return not d.dismissed end
  d.dismiss = function() d.dismissed = true end
  return d
end
luajava = {
  kotlinObject = function() return util end,
  bindClass = function(name)
    if name == "com.google.android.material.R" then return { style = { Widget_Material3_TextInputLayout_OutlinedBox = 123 } } end
    if name == "java.io.File" then return function(path)
      return {
        exists = function() return rootType ~= "missing" end,
        isDirectory = function() return rootType ~= "file" and rootType ~= "missing" end,
        canRead = function() return rootType ~= "unreadable" end,
        listFiles = function() return rootType == "unreadable" and nil or {} end,
        isFile = function() return false end,
        getCanonicalPath = function() return path:gsub("/+$", "") end,
      }
    end end
    if name == "android.text.TextWatcher" then return function(t) return t end end
    if name == "com.google.android.material.dialog.MaterialAlertDialogBuilder" then return makeDialog end
    if name == "com.google.android.material.snackbar.Snackbar" then
      return { LENGTH_LONG = 1, make = function(_, msg) notices[#notices + 1] = msg return { show = function() end } end }
    end
    if name == "com.androlua.adapter.LuaRecyclerAdapter" then return function(_, data, layout)
      local a = { data = data, layout = layout, notifications = 0, events = {} }
      for _, kind in ipairs({ "notifyDataSetChanged", "notifyItemRangeChanged", "notifyItemRangeRemoved", "notifyItemRangeInserted" }) do
        a[kind] = function(start, count)
          a.notifications = a.notifications + 1
          a.events[#a.events + 1] = { kind = kind, start = start, count = count }
        end
      end
      adapters[#adapters + 1] = a
      return a
    end end
    if not classCache[name] then
      classCache[name] = setmetatable({ LayoutParams = function(w, h)
        local lp = { width = w, height = h }
        lp.setMarginEnd = function(n) lp.marginEnd = n end
        return lp
      end }, { __call = function() return {} end })
    end
    return classCache[name]
  end,
}
file = { readall = function(path) assert(background) reads = reads + 1 return sources[path] end }
Bean = { Path = { app_root_pro_dir = "/Projects", agent_root_dir = "/agents" } }
this = { checkStoragePermission = function() return permission end, requestStoragePermission = function() error("use shell permission action") end,
  dpToPx = function(n) return n end,
  themeUtil = setmetatable({}, { __index = function() return function() return 0 end end }) }
activity = { isFinishing = function() return false end, isDestroyed = function() return false end }
__homeUi = { requestStoragePermission = function() denied = denied + 1 end }
android = { R = { string = { cancel = "cancel" } } }
res = { string = setmetatable({}, { __index = function(_, k) return k end }), drawable = function() drawables = drawables + 1 return {} end }
loadlayout = function(layout, binding)
  inflations = inflations + 1
  local v = view()
  v.layout = layout
  v.text = layout.text or ""
  if layout.id then allViews[layout.id] = v if binding then binding[layout.id] = v end end
  for i = 2, #layout do if type(layout[i]) == "table" then v.addView(loadlayout(layout[i], binding)) end end
  return v
end
xTask = function(work, callback, dispatcher)
  assert(dispatcher == "io")
  local j = { work = work, callback = callback }
  j.cancel = function() j.cancelled = true end
  jobs[#jobs + 1] = j
  return j
end
local function finish(index)
  local job = jobs[index]
  background = true
  local result = job.work()
  background = false
  if job.callback then job.callback(result) end
  return result
end
package.loaded["mods.utils.ActivityUtil"] = {
  setPending = function(action, payload)
    if not pendingWritable then return false end
    nav.action, nav.payload = action, payload return true
  end,
  open = function(route, path) nav.route, nav.path = route, path return true end,
}
package.loaded["activities.main.CreateProject"] = { show = function(deps) createDeps = deps end }
local KV = require "mods.utils.LuaKV"
KV.configure({ root = function() return "/kv" end,
  encode = function(value) serial = serial + 1 refs[tostring(serial)] = value return tostring(serial) end,
  decode = function(text) return refs[text] end })
local Recent = require "mods.project.RecentProjects"
assert(Recent.record("/Projects/Older", 100))
assert(Recent.record("/Projects/Newer/", 200))
assert(Recent.list()[1].path == "/Projects/Newer")
assert(Recent.rename("/Projects/Older", "/Projects/Newer"))
assert(#Recent.list() == 1 and Recent.list()[1].openedAt == 200)
assert(Recent.rename("/Projects/Older", "/Projects/Newer"), "migration is idempotent")
assert(Recent.record("/Projects/Older", 100))
local Data = require "mods.project.HomeProjects"
background = true
local first = Data.scan("/Projects")
assert(first.status == "ready" and #first.projects == 2)
assert(Data.filter(first.projects, " ") == first.projects, "empty search need not copy the full project array")
assert(first.projects[1].searchText:find("com.example.reader", 1, true), "scan prepares search text off the UI thread")
assert(first.recent[1].name == "Newer", "history must ignore directory mtime")
assert(#Data.filter(first.projects, "reader") == 1)
assert(#Data.filter(first.projects, "com.example.writer") == 1)
assert(#Data.filter(first.projects, "newer") == 1)
assert(Data.filter(first.projects, "writer")[1].appName == "Writer", "support legacy appname")
local oldReads = reads
Data.scan("/Projects")
assert(reads == oldReads, "unchanged init files use cache")
rootType = "file"
assert(Data.scan("/Projects").status == "root_not_directory")
rootType = "unreadable"
assert(Data.scan("/Projects").status == "error")
rootType = "directory"
assert(Data.chooseDirectory("relative") == nil)
background = false
local Page = require "activities.home.ProjectsPage"
Page.build()
assert(allViews.btnNew.layout.text == "home_create_project")
assert(allViews.btnNew.layout.allCaps == false and allViews.btnNew.layout.textAllCaps == nil,
  "use the native setAllCaps property, not the XML-only textAllCaps attribute")
assert(allViews.openDirectory.layout.contentDescription == "home_open_directory" and
  allViews.openDirectory.layout.styleAttr == "?attr/materialIconButtonStyle" and
  allViews.openDirectory.layout.layout_width == "wrap")
assert(allViews.search.layout.backgroundColor == 0 and allViews.search.layout.minHeight == "56dp")
assert(allViews.pageHeader.layout[2].layout_scrollFlags == 5 and allViews.projectList.layout.layout_height == "match",
  "headers must scroll away rather than reducing a short viewport to a zero-height list")
assert(allViews.projectList.layout.layout_behavior == "@string/appbar_scrolling_view_behavior")
assert(adapters[1].layout.layout_marginBottom == "12dp" and adapters[1].layout[2].padding == "16dp")
assert(#jobs == 0, "shell owns initial loading")
permission = false
Page.refresh()
assert(#jobs == 0 and allViews.status.text == "need_manage_permission")
assert(allViews.retry.visibility == 0 and allViews.statusBlock.visibility == 0)
allViews.retry.onClick()
assert(denied == 1)
permission = true
Page.refresh()
assert(allViews.status.text == "home_loading" and #adapters[1].data == 0)
assert(allViews.retry.visibility == 8, "no retry button while loading")
finish(1)
assert(#adapters[1].data == 2)
assert(allViews.statusBlock.visibility == 8 and allViews.retry.visibility == 8, "successful list has no leftover status/actions")
assert(allViews.recentRow.children[1].params.width == 184 and allViews.recentRow.children[1].params.marginEnd == 12,
  "recent cards need explicit root width and spacing when attached")
allViews.search.setText("WRITER")
assert(#adapters[1].data == 1 and adapters[1].data[1].title == "Writer")
allViews.search.setText("missing")
assert(#adapters[1].data == 0 and allViews.status.text == "home_no_search_results")
assert(allViews.retry.visibility == 8, "empty search is not a recoverable read failure")
allViews.clear.onClick()
assert(#adapters[1].data == 2)
scanFails = true
Page.refresh()
finish(2)
assert(#adapters[1].data == 2 and allViews.status.text == "home_scan_failed", "failed refresh retains rows")
assert(allViews.retry.visibility == 0 and allViews.statusBlock.visibility == 0)
scanFails = false
Page.refresh()
Page.refresh()
finish(3)
assert(allViews.status.text == "", "stale result cannot own UI; cached refresh keeps the header height stable")
finish(4)
nav.action, nav.payload = "unrelated", "keep"
adapters[1].data[1].projectRow.onClick()
assert(nav.action == "unrelated" and nav.payload == "keep" and nav.route == "editor",
  "ordinary project without main.lua preserves workspace and unrelated pending")
allViews.btnNew.onClick()
assert(createDeps.openProject("/Projects/Created"))
assert(nav.action == "open_file" and nav.payload == "/Projects/Created/main.lua")
pendingWritable, nav.route = false, nil
assert(createDeps.openProject("/Projects/FailedPending") == false)
assert(nav.route == nil and notices[#notices] == "home_open_failed", "pending failure must stop navigation")
pendingWritable = true
Page.refresh()
local pending = #jobs
Page.pause()
assert(jobs[pending].cancelled)
finish(pending)
assert(allViews.status.text == "")
Page.dispose()
Page.build()
assert(#adapters == 2, "destroyed views must be rebuilt")
local stableSearchId = allViews.search.id
assert(stableSearchId and allViews.search.saveEnabled and allViews.search.freezesText)
local Persistence = require "mods.project.ProjectPersistence"
local realResume, realPending = Persistence.resumePending, Persistence.pendingRename
local pendingPresent, repairs, guardAllowed, guardCalls = true, 0, false, 0
Persistence.pendingRename = function()
  return pendingPresent and { oldPath = "/Projects/Older", newPath = "/Projects/Renamed" } or nil
end
Persistence.resumePending = function()
  assert(not background, "explicit recovery must stay on UI with its ownership gate")
  repairs, pendingPresent = repairs + 1, false
  return true, { stage = "complete", completed = true }
end
package.loaded["mods.project.ProjectMenu"] = { resumePendingRename = function()
  assert(not background, "editor ownership guard is UI-only")
  guardCalls = guardCalls + 1
  if not guardAllowed then return false, { stage = "editor", error = "project_in_use" } end
  return Persistence.resumePending()
end }
Page.refresh()
finish(#jobs)
assert(allViews.status.text == "home_rename_pending" and #adapters[2].data == 2)
assert(repairs == 0, "read-only scan cannot silently resume a rename")
allViews.retry.onClick()
shownDialog.positive()
assert(repairs == 0 and notices[#notices] == "project_rename_close_editor", "live editor blocks explicit recovery")
guardAllowed = true
local beforeGuards = guardCalls
allViews.retry.onClick()
shownDialog.positive()
assert(repairs == 1 and guardCalls == beforeGuards + 1, "foreground retry uses the guarded ProjectMenu wrapper")
finish(#jobs)
Persistence.resumePending, Persistence.pendingRename = realResume, realPending
-- New Lua module represents an Activity/process recreation. Native hierarchy restoration
-- addresses the explicitly stable EditText ID and dispatches its restored text watcher.
Page.dispose()
package.loaded["activities.home.ProjectsPage"] = nil
local Recreated = require "activities.home.ProjectsPage"
Recreated.build()
assert(allViews.search.id == stableSearchId)
allViews.search.setText("Writer")
Recreated.refresh()
finish(#jobs)
assert(#adapters[3].data == 1 and adapters[3].data[1].title == "Writer")
local savedRecent = memory["/kv/home/recent-projects.json"]
memory["/kv/home/recent-projects.json"] = "corrupt"
local migrated, migrationError = Recent.rename("/Projects/Older", "/Projects/Again")
assert(migrated == false and migrationError == "recent_corrupt", "do not discard corrupt history during rename")
local oldRead, oldGet, oldExists = KV.read, KV.get, KV.exists
KV.read = function() return nil, "missing" end
KV.get = function() return nil end
KV.exists = function() return true end
migrated, migrationError = Recent.rename("/Projects/Older", "/Projects/Again")
assert(migrated == false and migrationError == "recent_corrupt", "existing undecodable history is not a no-op")
KV.read, KV.get, KV.exists = oldRead, oldGet, oldExists

allViews.openDirectory.onClick()
local directoryDialog, directoryInput = shownDialog, allViews.directoryInput
assert(directoryDialog.content.layout.paddingLeft == "20dp" and directoryDialog.content.layout.paddingTop == "12dp")
assert(directoryDialog.content.layout.focusableInTouchMode == true)
assert(directoryInput.layout[1] == classCache["vinx.material.textfield.MaterialTextField"])
assert(directoryInput.layout.style == 123 and directoryInput.layout.boxBackgroundMode == 2)
assert(directoryInput.layout.hint == "home_directory_path" and directoryInput.getText() == "/Projects")
directoryInput.setText("relative")
directoryDialog.button.onClick()
assert(directoryDialog.button.enabled == false)
finish(#jobs)
assert(directoryInput.error == "home_invalid_directory" and not directoryDialog.dismissed,
  "invalid path stays in the Material field with an inline error")
assert(directoryDialog.button.enabled == true)
directoryInput.setText("/Projects/Newer")
directoryDialog.button.onClick()
assert(directoryInput.error == nil, "retry clears the previous field error")
finish(#jobs)
assert(directoryDialog.dismissed and nav.route == "editor" and nav.path == "/Projects/Newer")

memory["/kv/home/recent-projects.json"] = savedRecent
Recreated.refresh(); finish(#jobs)
local currentAdapter = adapters[3]
local beforeNotify, beforeInflate, beforeDrawable = currentAdapter.notifications, inflations, drawables
local keptRow, keptCard = currentAdapter.data[1], allViews.recentRow.children[1]
for _ = 1, 20 do Recreated.refresh(); finish(#jobs) end
allViews.search.setText("  WRITER  ")
assert(currentAdapter.notifications == beforeNotify and currentAdapter.data[1] == keptRow,
  "unchanged refreshes and equivalent searches do not rebind project rows")
assert(inflations == beforeInflate and allViews.recentRow.children[1] == keptCard,
  "unchanged recent history creates zero replacement Views")
assert(drawables == beforeDrawable, "unchanged data creates zero replacement placeholder drawables")
assert(allViews.statusBlock.visibility == 8, "cached refresh does not flash a loading header")
print("PERF project: 20 unchanged refreshes -> 0 adapter notifications, 0 View inflations, 0 placeholder drawables")
sources["/Projects/Newer/init.lua"] = 'app_name="Writer revised"\npackage_name="com.example.writer"'
util.lastModified = function() return 101 end
Recreated.refresh(); finish(#jobs)
local changed = currentAdapter.events[#currentAdapter.events]
assert(currentAdapter.data[1].title == "Writer revised" and currentAdapter.data[1] ~= keptRow)
assert(changed.kind == "notifyItemRangeChanged" and changed.start == 0 and changed.count == 1,
  "an edited init.lua must update search results and the single changed row")
print("ALL-PASS TestHomeProjects")
