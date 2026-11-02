-- Actual homepage + ConversationStore.loadIndex + HomeProjects + LuaKV. Android/IO only doubled.
local assets = ASSETS or "app/src/main/assets/"
package.path = assets .. "?.lua;" .. package.path
local memory, refs, serial = {}, {}, 0
io.open = function(path, mode)
  assert(mode == "rb")
  if not memory[path] then return nil, "not found", 2 end
  return { read = function() return memory[path] end, close = function() end }
end
os.remove = function(path) memory[path] = nil return true end
local background, permission, requested, pendingWritable = false, true, 0, true
local jobs, views, adapters, nav, notices = {}, {}, {}, {}, {}
local entries, dialog, inflated = { { name = "Alpha", isDir = true } }, nil, 0
local util = { replaceText = function(path, text) memory[path] = text return true end,
  lastModified = function() return 0 end,
  listMeta = function() assert(background) return entries end }
local function newView()
  local v = { text = "", visibility = 0 }
  v.setText = function(t) v.text = t end
  v.setVisibility = function(n) v.visibility = n end
  v.setId = function(n) v.id = n end
  v.setLayoutManager = function(manager) v.manager = manager end
  v.setAdapter = function(adapter) v.adapter = adapter end
  return v
end
local function makeDialog()
  local d = {}
  for _, name in ipairs({ "setTitle", "setMessage", "setNegativeButton" }) do d[name] = function() return d end end
  d.setItems = function(items, callback) d.items, d.select = items, callback return d end
  d.setPositiveButton = function(_, callback) d.positive = callback return d end
  d.show = function() dialog = d return d end
  d.dismiss = function() d.dismissed = true end
  return d
end
local classCache = {}
luajava = {
  kotlinObject = function() return util end,
  bindClass = function(name)
    if name == "java.io.File" then return function(path)
      local valid = path == "/Projects" or path == "/Projects/Alpha"
      return { exists = function() return valid end, isDirectory = function() return valid end,
        canRead = function() return valid end, listFiles = function() return {} end,
        isFile = function() return false end, getCanonicalPath = function() return path end }
    end end
    if name == "com.google.android.material.dialog.MaterialAlertDialogBuilder" then return makeDialog end
    if name == "com.google.android.material.snackbar.Snackbar" then return {
      LENGTH_LONG = 1, make = function(_, text) notices[#notices + 1] = text return { show = function() end } end } end
    if name == "androidx.recyclerview.widget.LinearLayoutManager" then return function() return { position = 0 } end end
    if name == "com.androlua.adapter.LuaRecyclerAdapter" then return function(_, data, layout)
      local adapter = { data = data, layout = layout, notifications = 0, submittedCount = #data, events = {} }
      for _, kind in ipairs({ "notifyDataSetChanged", "notifyItemRangeChanged", "notifyItemRangeRemoved", "notifyItemRangeInserted" }) do
        adapter[kind] = function(start, count)
          assert(not background)
          adapter.notifications = adapter.notifications + 1
          adapter.submittedCount = #data
          adapter.events[#adapter.events + 1] = { kind = kind, start = start, count = count }
        end
      end
      adapters[#adapters + 1] = adapter
      return adapter
    end end
    if not classCache[name] then classCache[name] = {} end
    return classCache[name]
  end,
}
file = { readall = function() assert(background) return nil end }
Bean = { Path = { app_root_pro_dir = "/Projects", agent_root_dir = "/agents" } }
this = { checkStoragePermission = function() return permission end,
  requestStoragePermission = function() error("shell owns permission request") end,
  themeUtil = setmetatable({}, { __index = function() return function() return 0 end end }),
  getSharedData = function(_, fallback) return fallback end }
activity = { isFinishing = function() return false end, isDestroyed = function() return false end }
android = { R = { string = { cancel = "cancel" } } }
local ready, readyCount = 0, nil
__homeUi = { requestStoragePermission = function() requested = requested + 1 end,
  pageContentReady = function(key)
    assert(key == "conversations")
    ready = ready + 1
    local adapter = views.convList.adapter
    assert(adapter.submittedCount == #adapter.data, "content-ready must follow adapter submission")
    readyCount = #adapter.data
  end }
res = { drawable = function(name) return name end, string = setmetatable({ ai_confirm_delete_conv = "Delete %s?", ai_center_msg_count = "%d messages", ai_row_usage = "%s tokens" },
  { __index = function(_, k) return k end }) }
loadlayout = function(layout, binding)
  inflated = inflated + 1
  local v = newView()
  v.layout = layout
  if layout.id then views[layout.id] = v if binding then binding[layout.id] = v end end
  for i = 2, #layout do if type(layout[i]) == "table" then loadlayout(layout[i], binding) end end
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
  local j = jobs[index or #jobs]
  background = true
  local result = j.work()
  background = false
  if j.callback then j.callback(result) end
end
package.loaded["mods.utils.ActivityUtil"] = {
  setPending = function(action, payload)
    if not pendingWritable then return false end
    nav.action, nav.payload = action, payload return true
  end,
  open = function(route, path) nav.route, nav.path = route, path return true end,
}
local KV = require "mods.utils.LuaKV"
local function encode(value) serial = serial + 1 refs[tostring(serial)] = value return tostring(serial) end
local function decode(text) return refs[text] end
KV.configure({ root = function() return "/kv" end, encode = encode, decode = decode })
local Store = require "mods.agent.ConversationStore"
Store.configure({ getData = function(_, fallback) return fallback end, setData = function() return true end,
  encode = encode, decode = decode })
local function index(rows) memory["/kv/conversations/_index.json"] = encode(rows) end
index({ { id = "chat1", name = "Review", projectPath = "/Projects/Alpha", messageCount = 2, updatedAt = "2026-01-01" } })
local Page = require "activities.home.ConversationsPage"
Page.build()
assert(views.chooseProject == nil, "one new-conversation action, not a duplicate choose-project button")
assert(views.pageHeader.layout[2].layout_scrollFlags == 5 and views.convList.layout.layout_height == "match")
local adapter = adapters[1]
assert(adapter.layout.layout_marginBottom == "12dp" and adapter.layout[2].padding == "16dp")
local initialInflated = inflated
assert(#jobs == 0, "build cannot scan hidden pages")
permission = false
Page.refresh()
assert(#jobs == 0 and views.status.text == "need_manage_permission" and ready > 0)
assert(views.retry.visibility == 0 and views.statusBlock.visibility == 0)
views.retry.onClick()
assert(requested == 1)
permission = true
Page.refresh()
assert(views.status.text == "home_loading")
assert(views.retry.visibility == 8)
finish()
assert(#adapter.data == 1 and adapter.data[1].metadata:find("2 messages", 1, true) and readyCount == 1)
assert(views.statusBlock.visibility == 8 and views.retry.visibility == 8)
assert(adapter.data[1].project.text == "Alpha" and not adapter.data[1].metadata:find("Alpha", 1, true),
  "project identity has its own line instead of a long metadata soup")
adapter.data[1].conversationRow.onLongClick()
assert(dialog.items[1] == "open" and dialog.items[2] == "ai_delete", "real row menu remains available")
dialog.select(nil, 0)
finish()
assert(nav.action == "open_agent_conv_switch" and nav.payload == "/Projects/Alpha\nchat1" and nav.route == "editor")
pendingWritable, nav.route = false, nil
adapter.data[1].conversationRow.onClick()
finish()
assert(nav.route == nil and notices[#notices] == "home_open_failed", "pending failure stops navigation")
pendingWritable = true
index({ { id = "missing", name = "Missing project", projectPath = "/Projects/Missing", messageCount = 1 } })
Page.refresh()
finish()
adapter.data[1].conversationRow.onClick()
finish()
assert(nav.route == nil and notices[#notices] == "home_invalid_project")
-- Thousands of metadata-only rows cause no per-row View inflation. LM state is not reset.
local many = {}
for i = 1, 2000 do many[i] = { id = tostring(i), name = "Conversation " .. i, projectPath = "/Projects/Alpha",
  messageCount = 1, updatedAt = string.format("%04d", i) } end
index(many)
views.convList.manager.position = 1250
Page.refresh()
finish()
assert(#adapter.data == 2000 and adapter.data[1].title == "Conversation 2000" and readyCount == 2000)
assert(inflated == initialInflated, "refresh must not inflate thousands of row Views")
assert(views.convList.manager.position == 1250, "refresh must not reset LayoutManager state")
local keptFirst, keptLast, beforeRefresh = adapter.data[1], adapter.data[2000], adapter.notifications
for _ = 1, 20 do Page.refresh(); finish() end
assert(adapter.notifications == beforeRefresh and adapter.data[1] == keptFirst and adapter.data[2000] == keptLast,
  "2000 unchanged conversations do not rebuild their binding tables or rebind Views")
assert(views.statusBlock.visibility == 8, "background refresh does not expand/collapse the loading header")
many[2000].messageCount = 2
index(many)
Page.refresh(); finish()
local change = adapter.events[#adapter.events]
assert(adapter.notifications == beforeRefresh + 1 and change.kind == "notifyItemRangeChanged" and change.start == 0 and change.count == 1)
assert(adapter.data[1] ~= keptFirst and adapter.data[2000] == keptLast, "only the changed row gets a new binding")
many[2000].usage = { tokens = 2048 }
index(many); Page.refresh(); finish()
assert(adapter.data[1].metadata:find("tokens", 1, true), "usage changes invalidate the cached binding too")
many[2000].usage = nil
index(many); Page.refresh(); finish()
assert(adapter.data[1].badge.visibility == 8 and not adapter.data[1].metadata:find("tokens", 1, true))
print("PERF conversations: 2000 rows x 20 unchanged refreshes -> 0 adapter notifications; one changed record -> one-row change")
adapter.data[2000].conversationRow.onClick()
finish()
assert(nav.payload == "/Projects/Alpha\n1", "recycled row actions retain the right ID")
local previousNotifications = adapter.notifications
memory["/kv/conversations/_index.json"] = "corrupt"
Page.refresh()
finish()
assert(views.status.text == "home_conversations_failed" and #adapter.data == 2000 and adapter.notifications == previousNotifications)
assert(views.retry.visibility == 0 and views.statusBlock.visibility == 0)
index({})
Page.refresh()
finish()
assert(views.status.text == "home_conversation_guidance" and #adapter.data == 0 and readyCount == 0)
assert(views.retry.visibility == 8, "empty conversation guidance must not add a recovery action")
views.newConversation.onClick()
finish()
assert(dialog.items[1]:find("Alpha", 1, true))
dialog.select(nil, 0)
finish()
assert(nav.action == "open_agent_new" and nav.payload == "/Projects/Alpha")
entries = {}
views.newConversation.onClick()
finish()
assert(views.status.text == "home_no_project_guidance" and dialog.positive, "empty CTA can create a real project")
local deleteRecord = { id = "delete-me", name = "Delete me", projectPath = "/Projects/Alpha", seq = 1,
  createdAt = "2026-01-01", updatedAt = "2026-01-01", messages = { { role = "user", content = "hello" } } }
assert(KV.set("conversations", "delete-me", deleteRecord))
index({ { id = "delete-me", name = "Delete me", projectPath = "/Projects/Alpha", seq = 1,
  createdAt = "2026-01-01", updatedAt = "2026-01-01", messageCount = 1 } })
Page.refresh()
finish()
adapter.data[1].conversationRow.onLongClick()
dialog.select(nil, 1)
assert(dialog.positive, "delete requires real confirmation")
dialog.positive()
finish()
assert(notices[#notices] == "ai_deleted")
finish() -- confirmed deletion scheduled a fresh lightweight index load
assert(#adapter.data == 0, "confirmed menu deletion removes the actual persisted record")
entries = { { name = "Alpha", isDir = true } }
Page.refresh()
local pending = #jobs
local pausedStatus = views.status.text
Page.pause()
assert(jobs[pending].cancelled)
finish(pending)
assert(views.status.text == pausedStatus, "paused job cannot overwrite")
Page.dispose()
local oldView = views.convList
Page.build()
assert(views.convList ~= oldView and #adapters == 2)
print("ALL-PASS TestHomeConversations")
