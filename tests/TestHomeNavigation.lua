local assets = ASSETS or "app/src/main/assets/"
package.path = assets .. "?.lua;" .. package.path
_G["import"] = function() end
bindClass = function() return {} end
package.loaded["com.google.android.material.dialog.MaterialAlertDialogBuilder"] = {}
res = { string = {} }
local data, ackFails = {}, false
this = {
  getSharedData = function(key) return data[key] end,
  setSharedData = function(key, value)
    if ackFails and key == "_nav_pending_v1" and value == nil then return false end
    data[key] = value return true
  end,
}
activity = { getLuaDir = function() return "/assets" end }
local nav = require "mods.utils.ActivityUtil"
local opens, refreshes, failures = 0, 0, {}
local alive, permission, opensOK = true, true, true
local home = require("activities.home.HomeNavigation").new {
  navigation = nav, alive = function() return alive end,
  hasPermission = function() return permission end,
  isDirectory = function(path) return path == "/project" end,
  isFile = function(path) return path == "/project/main.lua" end,
  refresh = function() refreshes = refreshes + 1 end,
  open = function(path) assert(path == "/project") opens = opens + 1 return opensOK end,
  failure = function(p, reason) failures[#failures + 1] = { p, reason } end,
}
nav.setPending("open_project", "/project")
local p = nav.peekPending()
assert(home.process(false) and opens == 1 and nav.peekPending() == nil)
assert(home.result(p.action, p.payload, p.id) and opens == 1)
assert(home.result("project_created", "/project") and refreshes == 1 and opens == 1)
nav.setPending("open_file", "/foreign")
p = nav.peekPending()
assert(not home.process(false) and not home.result("open_project", "/project", "old"))
assert(nav.peekPending().token == p.token)
nav.ackPending(p)
permission = false
nav.setPending("open_project", "/project")
p = nav.peekPending()
assert(not home.process(false) and failures[#failures][2] == "permission" and opens == 1)
permission = true
assert(not home.process(false) and opens == 1)
assert(home.process(true, p) and opens == 2)
nav.setPending("open_project", "/missing")
assert(not home.process(false) and failures[#failures][2] == "project_missing")
nav.ackPending(nav.peekPending())
ackFails = true
nav.setPending("open_project", "/project")
p = nav.peekPending()
assert(home.process(false) and opens == 3 and failures[#failures][2] == "unacknowledged")
ackFails = false
assert(home.process(true, p) and opens == 3 and not nav.peekPending(), "ack retry must not launch again")
nav.setPending("project_created", "/project")
alive = false
assert(not home.process(false) and refreshes == 1 and nav.peekPending())
print("ALL-PASS TestHomeNavigation pending/result identity, retry, ownership and disposal")
