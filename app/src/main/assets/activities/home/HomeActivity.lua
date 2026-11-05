---@diagnostic disable: undefined-global
--- IDE 首页：底栏四 tab（项目 / 会话 / 帮助 / 设置）+ ViewPager2 分页。
--- 作为应用的根页面（根 main.lua import 本文件），权限门禁与首次目录准备
--- 在此完成；打开工程跳转编辑器页（activities/main/MainActivity.lua）。
require "mods.bootstrap"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"

local AppInit = require "mods.utils.AppInit"
local ActivityUtil = require "mods.utils.ActivityUtil"
local File = luajava.bindClass "java.io.File"

local ColorUtil = this.themeUtil
local res = res

local modules = {
  projects = "activities.home.ProjectsPage",
  conversations = "activities.home.ConversationsPage",
  help = "activities.home.HelpPage",
  settings = "activities.home.SettingsPage",
}
local pages = {}
local destroyed = false
local function getPage(key)
  assert(modules[key], "Unknown home page: " .. tostring(key))
  if not pages[key] then pages[key] = require(modules[key]) end
  return pages[key]
end

local ready = false

local function ensureReady()
  if ready then return true end
  AppInit.prepareDirs()
  ready = true
  return true
end

-- Named host functions survive FragmentManager restoration by being rebound in the new
-- Activity's Lua state. Arguments store only the stable key, never callbacks or Views.
function __homeBuildPage(key)
  if destroyed then return nil end
  return getPage(key).build()
end

function __homeRefreshPage(key)
  if destroyed then return end
  if this.checkStoragePermission() then ensureReady() end
  -- Denied state is still rendered; page.refresh must gate storage IO itself.
  local page = getPage(key)
  if page.refresh then page.refresh() end
end

function __homePageVisible(key)
  if not destroyed and _G.__homeUi then _G.__homeUi.refreshVisiblePage() end
end

function __homePausePage(key)
  local page = pages[key]
  if page and page.pause then page.pause() end
end

function __homeDisposePage(key)
  local page = pages[key]
  if page and page.dispose then page.dispose() end
end

local function refreshVisiblePage()
  if not destroyed and _G.__homeUi then
    _G.__homeUi.refreshVisiblePage()
  end
end

local navigation, navigationDialog, shownNavigationToken
local function showNavigationFailure(pending, reason, retry)
  if destroyed or navigationDialog or (pending.token and shownNavigationToken == pending.token and not retry) then return end
  shownNavigationToken = pending.token
  local messages = {
    permission = res.string.need_manage_permission,
    expired = res.string.navigation_expired,
    project_missing = res.string.navigation_project_missing,
    file_missing = res.string.navigation_file_missing,
  }
  local function close() navigationDialog = nil end
  navigationDialog = MaterialAlertDialogBuilder(activity)
    .setTitle(res.string.navigation_failed)
    .setMessage(messages[reason] or res.string.navigation_retry_hint)
    .setPositiveButton(res.string.retry, function()
      close()
      if pending.token then navigation.process(true, pending)
      else navigation.result(pending.action, pending.payload, pending.id) end
    end)
    .setNegativeButton(res.string.navigation_dismiss, function()
      close()
      ActivityUtil.ackPending(pending)
    end)
    .setNeutralButton(android.R.string.cancel, close)
    .setOnCancelListener(close)
    .show()
end
navigation = require("activities.home.HomeNavigation").new {
  navigation = ActivityUtil,
  alive = function() return not destroyed and not activity.isFinishing() and not activity.isDestroyed() end,
  hasPermission = function() return this.checkStoragePermission() end,
  isDirectory = function(path) return File(path).isDirectory() end,
  isFile = function(path) return File(path).isFile() end,
  open = function(path) return ActivityUtil.open("editor", path) end,
  refresh = refreshVisiblePage,
  failure = showNavigationFailure,
}

function onResult(name, action, path, requestId)
  return navigation.result(action, path, requestId)
end

local function setupWindow()
  activity.getWindow().setSoftInputMode(0x10)
  -- 底栏是 BottomNavigationView，默认色是 surfaceContainer，不是页面的 surface。
  require("mods.utils.SystemBars").apply(
    activity.getWindow(),
    ColorUtil.getColorSurface(),
    ColorUtil.getColorSurfaceContainer()
  )
end

function onCreate()
  activity.setTheme(R.style.Theme_NeLuaJ_Material3_DynamicColors_NoActionBar)
  activity.dynamicColor()
  activity.setContentView(res.layout.home_layout)
  setupWindow()

  if this.checkStoragePermission() then
    ensureReady()
  else
    MaterialAlertDialogBuilder(activity)
      .setTitle(res.string.tip)
      .setMessage(res.string.need_manage_permission)
      .setPositiveButton(android.R.string.ok, function()
        this.requestStoragePermission()
      end)
      .setNegativeButton(android.R.string.cancel, nil)
      .setCancelable(false)
      .show()
  end
end

function onStorageRequestResult(isGranted)
  if destroyed then return end
  if isGranted then ensureReady() end
  -- A denial is not another forced modal: ProjectsPage offers the explicit retry action.
  refreshVisiblePage()
end

function onResume()
  -- 从编辑器/设置等子页返回时只刷新当前 tab；后台授权返回也在此就绪
  if this.checkStoragePermission() then
    ensureReady()
  end
  refreshVisiblePage()
  navigation.process(false)
end

function onDestroy()
  destroyed = true
  if navigationDialog then navigationDialog.dismiss() navigationDialog = nil end
  if _G.__homeUi then _G.__homeUi.root.dispose() end
  for key in pairs(pages) do __homePausePage(key) end
  _G.__homeUi = nil
end

-- No root Back interception: the system owns Home's Back behavior.
