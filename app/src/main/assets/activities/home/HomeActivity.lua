---@diagnostic disable: undefined-global
--- IDE 首页：底栏四 tab（项目 / 会话 / 帮助 / 设置）+ ViewPager2 分页。
--- 作为应用的根页面（根 main.lua import 本文件），权限门禁与首次目录准备
--- 在此完成；打开工程跳转编辑器页（activities/main/MainActivity.lua）。
require "mods.bootstrap"
import "java.io.File"
import "android.view.View"
import "android.view.WindowManager"
import "com.google.android.material.snackbar.Snackbar"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"

local AppInit = require "mods.utils.AppInit"
local ActivityUtil = require "mods.utils.ActivityUtil"

local ColorUtil = this.themeUtil
local res = res

-- 与 home_layout require 的是同一批模块实例（require 缓存）
local pages = {
  require "activities.home.ProjectsPage",
  require "activities.home.ConversationsPage",
  require "activities.home.HelpPage",
  require "activities.home.SettingsPage",
}

local ready = false

local function ensureReady()
  if ready then return true end
  AppInit.prepareDirs()
  ready = true
  return true
end

local function refreshAllPages()
  for _, page in ipairs(pages) do
    if page.refresh then pcall(page.refresh) end
  end
end

local function setupWindow()
  local window = activity.getWindow() {
    SoftInputMode = 0x10,
    StatusBarColor = ColorUtil.getColorBackground()
  }
    .addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
    .clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)

  if this.isNightMode() then
    window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_VISIBLE)
  else
    window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR)
  end
end

--- 桌面动态快捷方式：AI 助手。目标仍是根 main.lua（即本页），
--- open_agent extra 由下方 consumeIntent 处理。纯 Lua 创建，不会进入用户打包的应用。
local function createAgentShortcut()
  pcall(function()
    local Intent = luajava.bindClass("android.content.Intent")
    local Uri = luajava.bindClass("android.net.Uri")
    local ShortcutInfo = luajava.bindClass("android.content.pm.ShortcutInfo")
    local ShortcutManager = luajava.bindClass("android.content.pm.ShortcutManager")
    local ArrayList = luajava.bindClass("java.util.ArrayList")
    local Icon = luajava.bindClass("android.graphics.drawable.Icon")
    local sm = activity.getSystemService("shortcut")
    if not sm then return end
    local mainPath = activity.getLuaDir() .. "/main.lua"
    local intent = Intent(Intent.ACTION_VIEW)
    intent.setClassName(activity, "com.androlua.LuaActivity")
    intent.setData(Uri.parse("file://" .. mainPath))
    intent.putExtra("name", mainPath)
    intent.putExtra("open_agent", true)
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    local builder = ShortcutInfo.Builder(activity, "agent")
      .setShortLabel(res.string.shortcut_agent_short)
      .setLongLabel(res.string.shortcut_agent_long)
      .setIntent(intent)
    pcall(function()
      local iconId = activity.getResources().getIdentifier("icon", "drawable", activity.getPackageName())
      if iconId ~= 0 then builder.setIcon(Icon.createWithResource(activity, iconId)) end
    end)
    local list = ArrayList()
    list.add(builder.build())
    sm.setDynamicShortcuts(list)
  end)
end

--- 桌面快捷方式/外部进入时的启动意图消费：直接唤起 AI 助手面板。
--- AI 面板不依赖编辑器视图，无工程上下文时也可打开。
local function consumeIntent()
  pcall(function()
    local intent = activity.getIntent()
    if intent and intent.getBooleanExtra("open_agent", false) then
      require("mods.agent.ChatUI").show()
    end
  end)
end

function onCreate()
  activity.setTheme(R.style.Theme_NeLuaJ_Material3_NoActionBar)
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

  createAgentShortcut()
  consumeIntent()
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
  refreshAllPages()
end

function onResume()
  -- 从编辑器/设置等子页返回时刷新各 tab；后台授权返回也在此就绪
  if this.checkStoragePermission() then
    ensureReady()
    refreshAllPages()
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
    Snackbar.make(pages[1].build(), res.string.confirm_exit, Snackbar.LENGTH_SHORT)
      .setAction(res.string.exit, function()
        activity.finish(true)
      end)
      .show()
  end)
end)
