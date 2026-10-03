---@diagnostic disable: undefined-global
--- IDE 首页：底栏四 tab（项目 / 会话 / 帮助 / 设置）+ ViewPager2 分页。
--- 作为应用的根页面（根 main.lua import 本文件），权限门禁与首次目录准备
--- 在此完成；打开工程跳转编辑器页（activities/main/MainActivity.lua）。
require "mods.bootstrap"
import "java.io.File"
import "com.google.android.material.snackbar.Snackbar"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"

local AppInit = require "mods.utils.AppInit"
local ActivityUtil = require "mods.utils.ActivityUtil"

local ColorUtil = this.themeUtil
local res = res

-- 页面模块必须在 dynamicColor() 之后才首次加载：模块顶层会立即解析主题色，
-- 而 main.lua 模块体先于 Lua onCreate 执行（此时 dynamicColor 尚未生效），
-- 提前 require 会把基线紫色冻结进页面背景。home_layout 在 setContentView
-- 阶段首次 require 各页，此后 require 命中缓存拿到同一实例。
local pages
local function getPages()
  if not pages then
    pages = {
      require "activities.home.ProjectsPage",
      require "activities.home.ConversationsPage",
      require "activities.home.HelpPage",
      require "activities.home.SettingsPage",
    }
  end
  return pages
end

local ready = false

local function ensureReady()
  if ready then return true end
  AppInit.prepareDirs()
  ready = true
  return true
end

local function refreshAllPages()
  for _, page in ipairs(getPages()) do
    if page.refresh then pcall(page.refresh) end
  end
end

--- 只刷新当前可见 tab——全部四个 tab 每次 onResume 都扫盘是首帧卡顿的主因
local function refreshVisiblePage()
  if not _G.__homeUi then
    -- pager 尚未装配（首次 onCreate 时 home_layout 还没跑完）
    refreshAllPages()
    return
  end
  local current = tonumber(_G.__homeUi.pager.getCurrentItem()) or 0
  local all = getPages()
  if current >= 0 and current < #all then
    local page = all[current + 1]
    if page and page.refresh then pcall(page.refresh) end
  end
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
    refreshAllPages()
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
  if not isGranted then
    MaterialAlertDialogBuilder(activity)
      .setTitle(res.string.tip)
      .setMessage(res.string.need_manage_permission)
      .setPositiveButton(android.R.string.ok, function()
        this.requestStoragePermission()
      end)
      .setNegativeButton(android.R.string.cancel, nil)
      .setCancelable(false)
      .show()
    return
  end
  ensureReady()
  -- 授权完成后同样只刷当前 tab，延迟到布局完成避免阻塞
  activity.getWindow().getDecorView().post(function()
    refreshVisiblePage()
  end)
end

function onResume()
  -- 从编辑器/设置等子页返回时只刷新当前 tab；后台授权返回也在此就绪
  if this.checkStoragePermission() then
    ensureReady()
    -- 延迟到布局完成后执行，避免阻塞首帧渲染
    activity.getWindow().getDecorView().post(function()
      refreshVisiblePage()
    end)
  end
end

local _exit = 0
this.addOnBackPressedCallback(function()
  if _exit + 2 > os.time() then
    activity.finish(true)
    return
  end
  _exit = os.time()
  pcall(function()
    Snackbar.make(getPages()[1].build(), res.string.confirm_exit, Snackbar.LENGTH_SHORT)
      .setAction(res.string.exit, function()
        activity.finish(true)
      end)
      .show()
  end)
end)
