-- Exercise the real reparenting/state module against activity-window doubles.
local assets = ASSETS or "app/src/main/assets/"
local width, configWidth, metricsWidth, saved = 1000, 1000, 1000, true
local metricsAvailable = true
local writes, menuChanges, pending = 0, 0, {}
local function view()
  local v = { lp = {}, visibility = 0 }
  v.getLayoutParams = function() return v.lp end
  v.setLayoutParams = function(lp) v.lp = lp end
  v.setVisibility = function(value) v.visibility = value end
  v.getParent = function() return v.parent end
  v.addView = function(child, _, lp) child.parent = v; child.lp = lp or {} end
  v.removeView = function(child) child.parent = nil end
  v.post = function(fn) pending[#pending + 1] = fn end
  v.requestLayout = function() end
  v.invalidate = function() end
  v.bringToFront = function() end
  v.setText = function(text) v.text = text end
  return v
end
drawer, head, workspace = view(), view(), view()
head.parent = drawer
drawer.getWidth = function() return width end
drawer.setDrawerLockMode = function(mode) drawer.lock = mode end
drawer.setScrimColor = function(color) drawer.scrim = color end
drawer.closeDrawer = function() end
drawer.addOnLayoutChangeListener = function(listener) drawer.listener = listener end
drawer.removeOnLayoutChangeListener = function() end
editor_empty_state, editor_empty_hint, open_drawer_btn = view(), view(), view()
side_divider, side_host, mCodeMinimap, minimap_divider = view(), view(), view(), view()
this = {
  getSharedData = function() return saved end,
  setSharedData = function() writes = writes + 1 end,
  dpToPx = function(n) return n end,
  getResources = function() return {
    getDisplayMetrics = function() return { widthPixels = 2000, density = 1 } end,
    getConfiguration = function() return { screenWidthDp = configWidth } end,
  } end,
}
activity = {
  getWindowManager = function() return { getCurrentWindowMetrics = function()
    assert(metricsAvailable, "pre-30 host has no current window metrics")
    return {
      getBounds = function() return { width = function() return metricsWidth end } end,
      getWindowInsets = function() return { getInsetsIgnoringVisibility = function() return {left=0,right=0} end } end,
    }
  end } end,
  invalidateOptionsMenu = function() menuChanges = menuChanges + 1 end,
  isFinishing = function() return false end,
  isDestroyed = function() return false end,
}
res = { string = { no_file_hint_side = "side", no_file_hint = "drawer" } }
luajava = {
  bindClass = function(name)
    return {
      START = 3, LOCK_MODE_LOCKED_CLOSED = 1, LOCK_MODE_UNLOCKED = 0,
      systemBars = function() return 1 end, displayCutout = function() return 2 end,
      LayoutParams = function(w, h) return {width=w,height=h} end,
    }
  end,
  createProxy = function(_, listener) return listener end,
}
local function flush()
  local jobs = pending; pending = {}
  for _, fn in ipairs(jobs) do fn() end
end
package.loaded["mods.utils.EditorUtil"] = { currentFile = function() return "" end }
local mode = assert(loadfile(assets .. "activities/main/TabletMode.lua"))()
mode.apply()
assert(head.parent == workspace and mode.isTabletMode())
assert(mode.isTabletModePreferred() and open_drawer_btn.visibility == 8)
assert(editor_empty_hint.text == "side" and drawer.lock == 1)
flush()
-- A shrinking task must not trust its stale measured or physical display size.
metricsWidth, configWidth = 420, 420
mode.apply()
assert(head.parent == drawer and not mode.isTabletMode())
assert(saved and mode.isTabletModePreferred() and writes == 0)
assert(drawer.lock == 0 and drawer.scrim ~= 0)
assert(open_drawer_btn.visibility == 0 and editor_empty_hint.text == "drawer")
-- Layout listener restores the column after expansion, without an activity restart.
width, configWidth, metricsWidth = 900, 900, 900
drawer.listener.onLayoutChange()
drawer.listener.onLayoutChange()
assert(#pending == 1, "resize posts must coalesce")
flush()
assert(head.parent == workspace and mode.isTabletMode())
assert(open_drawer_btn.visibility == 8 and writes == 0)
flush()
drawer.listener.onLayoutChange()
assert(#pending == 0, "unchanged width caused a layout feedback loop")
-- Width boundary, disabled preference, nonempty editor and lifecycle guard.
width, configWidth, metricsWidth = 599, 599, 599
mode.apply(); assert(not mode.isTabletMode())
width, configWidth, metricsWidth = 600, 600, 600
mode.apply(); assert(mode.isTabletMode())
saved = false
mode.apply(); assert(head.parent == drawer and not mode.isTabletMode())
package.loaded["mods.utils.EditorUtil"].currentFile = function() return "/main.lua" end
mode.syncEditorEmptyState(); assert(editor_empty_state.visibility == 8)
flush()
width, configWidth, metricsWidth = 800, 800, 800
drawer.listener.onLayoutChange()
activity.isDestroyed = function() return true end
local before = menuChanges
flush(); assert(menuChanges == before)
-- Before measurement on pre-30, configuration is sufficient; physical display
-- width remains 2000px and must never force the expanded layout.
metricsAvailable, width, configWidth, saved = false, 0, 360, true
assert(not mode.isTabletMode())
configWidth = 900
assert(mode.isTabletMode())
width, configWidth = 240, 240
mode.apply()
assert(head.parent == drawer and head.lp.width == 184, "compact drawer must fit the available window")
print("ALL-PASS")
