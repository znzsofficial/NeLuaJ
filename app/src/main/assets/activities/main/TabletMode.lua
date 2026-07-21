--- 平板真分栏：head reparent 到 workspace / drawer
local GravityCompat = luajava.bindClass "androidx.core.view.GravityCompat"
local DrawerLayout = luajava.bindClass "androidx.drawerlayout.widget.DrawerLayout"
local LinearLayoutCls = luajava.bindClass "android.widget.LinearLayout"
local DrawerLayoutCls = luajava.bindClass "androidx.drawerlayout.widget.DrawerLayout"

local VISIBLE = 0
local INVISIBLE = 4
local GONE = 8
local MATCH_PARENT = -1

local TABLET_DRAWER_DP = 320
local PHONE_DRAWER_DP = 280
local TABLET_DRAWER_MAX_DP = 380
local TABLET_MINIMAP_DP = 72
local PHONE_MINIMAP_DP = 52

local lastTabletEnabled = nil
local drawerToggle

local function isSharedTruthy(value)
  return value == true or value == "true" or value == 1
end

local function isTabletModeOn()
  return isSharedTruthy(this.getSharedData("tablet_mode", false))
end

local function screenWidthDp()
  local ok, w = pcall(function()
    local dm = this.getResources().getDisplayMetrics()
    return dm.widthPixels / dm.density
  end)
  return ok and w or 360
end

local function isLargeScreen()
  return screenWidthDp() >= 600
end

local function tabletDrawerWidthDp()
  local sw = screenWidthDp()
  local w = math.floor(sw * 0.28 + 0.5)
  if w < TABLET_DRAWER_DP then w = TABLET_DRAWER_DP end
  if w > TABLET_DRAWER_MAX_DP then w = TABLET_DRAWER_MAX_DP end
  return w
end

local function setViewWidth(view, px)
  if not view then return end
  local lp = view.getLayoutParams()
  lp.width = px
  view.setLayoutParams(lp)
end

local function setRightMargin(view, px)
  if not view then return end
  local lp = view.getLayoutParams()
  pcall(function() lp.rightMargin = px end)
  pcall(function()
    if lp.setMarginEnd then lp.setMarginEnd(px) end
  end)
  view.setLayoutParams(lp)
end

local function headParentIs(view)
  local ok, p = pcall(function() return head.getParent() end)
  return ok and p == view
end

local function removeHeadFromParent()
  local ok, parent = pcall(function() return head.getParent() end)
  if ok and parent then
    pcall(function() parent.removeView(head) end)
  end
end

local function hideSideHostPlaceholder()
  if not side_host then return end
  pcall(function()
    side_host.setVisibility(GONE)
    local lp = side_host.getLayoutParams()
    lp.width = 0
    pcall(function() lp.weight = 0 end)
    side_host.setLayoutParams(lp)
  end)
end

local function attachHeadToWorkspace(drawerW)
  if not head or not workspace or not drawer then return end
  hideSideHostPlaceholder()

  if headParentIs(workspace) then
    pcall(function()
      local lp = head.getLayoutParams()
      lp.width = drawerW
      lp.height = MATCH_PARENT
      pcall(function() lp.weight = 0 end)
      head.setLayoutParams(lp)
      head.setVisibility(VISIBLE)
    end)
    return
  end

  removeHeadFromParent()

  local ok = pcall(function()
    local lp = LinearLayoutCls.LayoutParams(drawerW, MATCH_PARENT, 0)
    workspace.addView(head, 0, lp)
    head.setVisibility(VISIBLE)
    head.requestLayout()
    workspace.requestLayout()
  end)
  if not ok then
    pcall(function()
      local lp = LinearLayoutCls.LayoutParams(drawerW, MATCH_PARENT)
      pcall(function() lp.weight = 0 end)
      workspace.addView(head, 0, lp)
      head.setVisibility(VISIBLE)
    end)
  end

  pcall(function()
    drawer.setDrawerLockMode(DrawerLayout.LOCK_MODE_LOCKED_CLOSED, GravityCompat.START)
    drawer.setScrimColor(0)
  end)
end

local function attachHeadToDrawer(drawerW)
  if not head or not drawer then return end
  hideSideHostPlaceholder()

  if headParentIs(drawer) then
    pcall(function()
      local lp = head.getLayoutParams()
      lp.width = drawerW
      lp.height = MATCH_PARENT
      pcall(function() lp.gravity = GravityCompat.START end)
      head.setLayoutParams(lp)
      head.setVisibility(VISIBLE)
    end)
    return
  end

  removeHeadFromParent()

  pcall(function()
    local lp = DrawerLayoutCls.LayoutParams(drawerW, MATCH_PARENT)
    lp.gravity = GravityCompat.START
    drawer.addView(head, lp)
    head.setVisibility(VISIBLE)
    drawer.setDrawerLockMode(DrawerLayout.LOCK_MODE_UNLOCKED, GravityCompat.START)
    drawer.setScrimColor(0x99000000)
  end)
end

local _M = {}

function _M.setDrawerToggle(toggle)
  drawerToggle = toggle
end

function _M.isTabletMode()
  return isTabletModeOn()
end

function _M.isLargeScreen()
  return isLargeScreen()
end

function _M.syncEditorEmptyState()
  pcall(function()
    if not editor_empty_state then return end
    local noFile = mLuaEditor and mLuaEditor.getVisibility() == INVISIBLE
    local tablet = isTabletModeOn()
    if noFile and not tablet then
      editor_empty_state.setVisibility(VISIBLE)
      editor_empty_state.bringToFront()
    else
      editor_empty_state.setVisibility(GONE)
    end
  end)
end

function _M.apply()
  if not drawer or not head then return end
  local enabled = isTabletModeOn()
  local drawerDp = enabled and tabletDrawerWidthDp() or PHONE_DRAWER_DP
  local drawerW = math.floor(this.dpToPx(drawerDp) + 0.5)
  local minimapW = math.floor(this.dpToPx(enabled and TABLET_MINIMAP_DP or PHONE_MINIMAP_DP) + 0.5)

  if enabled then
    attachHeadToWorkspace(drawerW)
    pcall(function()
      if side_divider then side_divider.setVisibility(VISIBLE) end
    end)
  else
    attachHeadToDrawer(drawerW)
    pcall(function()
      if side_divider then side_divider.setVisibility(GONE) end
    end)
    pcall(function()
      if lastTabletEnabled == true then
        drawer.closeDrawer(GravityCompat.START)
      end
    end)
  end

  pcall(function()
    setViewWidth(mCodeMinimap, minimapW)
    setRightMargin(minimap_divider, minimapW)
  end)

  pcall(function()
    if mSearch then
      local left = math.floor(this.dpToPx(enabled and 14 or 10) + 0.5)
      local right = left
      local mlp = mSearch.getLayoutParams()
      pcall(function()
        mlp.leftMargin = left
        mlp.rightMargin = right
      end)
      mSearch.setLayoutParams(mlp)
    end
  end)

  pcall(function()
    if drawerToggle then
      drawerToggle.setDrawerIndicatorEnabled(not enabled)
      drawerToggle.syncState()
    end
    if activity.getSupportActionBar then
      activity.getSupportActionBar().setDisplayHomeAsUpEnabled(true)
    end
  end)

  pcall(function()
    if mCodeMinimap then mCodeMinimap.bringToFront() end
    if head then
      head.setVisibility(VISIBLE)
      head.requestLayout()
      head.invalidate()
    end
    if mRecycler then mRecycler.requestLayout() end
    if swipeRefresh then swipeRefresh.requestLayout() end
    if workspace then workspace.requestLayout() end
    drawer.requestLayout()
  end)

  if enabled then
    pcall(function()
      head.post(function()
        pcall(function()
          if MainActivity and MainActivity.RecyclerView and MainActivity.RecyclerView.update then
            MainActivity.RecyclerView.update()
          end
        end)
      end)
    end)
  end

  lastTabletEnabled = enabled
  _M.syncEditorEmptyState()
end

return _M
