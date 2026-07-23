---@diagnostic disable: undefined-global
require "environment"
import "java.io.File"
import "android.view.View"
import "android.view.WindowManager"
import "androidx.core.view.GravityCompat"
import "androidx.appcompat.widget.PopupMenu"
import "com.google.android.material.snackbar.Snackbar"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"

local Init = require "activities.main.Init"
import "mods.utils.ActivityUtil"
import "mods.utils.EditorUtil"

local Actions = Init.Actions
local _exit = 0
local ColorUtil = this.themeUtil
local res = res

local SHOW_AS_ACTION_NEVER = 0
local SHOW_AS_ACTION_IF_ROOM = 1
local SHOW_AS_ACTION_ALWAYS = 2
local SHOW_AS_ACTION_WITH_TEXT = 4
local SHOW_AS_ACTION_IF_ROOM_TEXT = 5 -- IF_ROOM | WITH_TEXT
local SHOW_AS_ACTION_ALWAYS_TEXT = 6 -- ALWAYS | WITH_TEXT
local VISIBLE = Init.VISIBLE
local INVISIBLE = Init.INVISIBLE
local GONE = Init.GONE

local function initFiles()
  LuaFileUtil.checkDirectory(Bean.Path.app_root_pro_dir)
  checkBackup()
  Init.initView2().initBar().initFunctionTab().initCheck().restoreLastFile()
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

local function addAction(menu, title, icon, onClick, flags)
  local item = menu.add(title)
  -- 必须先 setIcon 再 showAsAction，否则 Toolbar 可能不显示 action
  if icon ~= nil then
    pcall(function() item.setIcon(icon) end)
  end
  pcall(function()
    item.setShowAsAction(flags or SHOW_AS_ACTION_ALWAYS)
  end)
  item.onMenuItemClick = onClick
  return item
end

local function addItem(menu, title, onClick, flags, icon)
  local item = menu.add(title)
  if icon ~= nil then
    pcall(function() item.setIcon(icon) end)
  end
  if flags then
    pcall(function() item.setShowAsAction(flags) end)
  end
  item.onMenuItemClick = onClick
  return item
end

local function isTabletUi()
  return Init.isTabletMode and Init.isTabletMode()
end

local RunKeyConfig = require "mods.utils.RunKeyConfig"

--- 工具栏运行键：按设置 run_key_mode（默认 menu）
local function showRunMenu()
  if not Actions.requireOpenFile() then return end

  local mode = RunKeyConfig.getMode(this)
  -- 无工程：无法「运行工程」；file/project 都退化为当前文件，menu 也无工程项
  if Bean.Project.this_project == "" then
    Actions.runCurrent()
    return
  end

  if mode == RunKeyConfig.MODE_FILE then
    Actions.runCurrent()
    return
  end
  if mode == RunKeyConfig.MODE_PROJECT then
    Actions.runProject()
    return
  end

  -- menu（默认）
  local pop = PopupMenu(activity, mToolBar.getChildAt(3))
  local menu = pop.Menu
  addItem(menu, res.string.run_code .. " " .. File(Bean.Path.this_file).getName(), Actions.runCurrent)
  addItem(menu, res.string.run_project, Actions.runProject)
  if this.getSharedData("debug_app", nil) then
    addItem(menu, res.string.run_on_debug_app, Actions.runOnDebugApp)
  end
  pop.show()
end

local function showAbout()
  local views = {}
  MaterialAlertDialogBuilder(this)
    .setTitle(res.string.about)
    .setMessage(res.string.about_this)
    .setView(loadlayout(res.layout.dialog_about, views))
    .setPositiveButton(android.R.string.ok, nil)
    .show()
  views.author.onClick = function()
    xpcall(function()
      import "android.content.Intent"
      import "android.net.Uri"
      local url = "mqqapi://card/show_pslcard?src_type=internal&source=sharecard&version=1&uin=1071723770"
      activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    end, function()
      Actions.snack(res.string.please_install_qq)
    end)
  end
end

local function requestCommonPermissions()
  local permission = android.Manifest.permission
  activity.requestPermissions({
    permission.WRITE_EXTERNAL_STORAGE,
    permission.READ_EXTERNAL_STORAGE,
    permission.INTERNET,
    permission.ACCESS_NETWORK_STATE,
    permission.ACCESS_WIFI_STATE,
    permission.READ_PHONE_STATE,
    permission.CAMERA,
    permission.RECORD_AUDIO,
    permission.MODIFY_AUDIO_SETTINGS,
    permission.WAKE_LOCK,
    permission.VIBRATE,
    permission.REQUEST_INSTALL_PACKAGES,
    permission.BLUETOOTH_SCAN,
    permission.BLUETOOTH_CONNECT,
    permission.BLUETOOTH_ADVERTISE,
  }, 0)
end

function onCreate()
  activity.setTheme(R.style.Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay)
  activity.dynamicColor()
  activity.setContentView(res.layout.main_layout)
    .setSupportActionBar(mToolBar)
    .getSupportActionBar() {
      DisplayHomeAsUpEnabled = true,
      Elevation = 0,
      Subtitle = res.string.no_file
    }

  setupWindow()
  Init.initView()

  if this.checkStoragePermission() then
    initFiles()
  else
    MaterialAlertDialogBuilder(activity)
      .setTitle(res.string.tip)
      .setMessage(res.string.need_manage_permission)
      .setPositiveButton(android.R.string.ok, function()
        this.requestStoragePermission()
      end)
      .setNegativeButton(android.R.string.cancel, function()
        this.finish()
      end)
      .setCancelable(false)
      .show()
  end
end

function onStorageRequestResult(isGranted)
  if not isGranted then
    Actions.snack(res.string.need_manage_permission)
    return
  end
  initFiles()
end

local function handleNavAction(action, path)
  if (action == "open_file" or action == "open_init") and type(path) == "string" and path ~= "" then
    if File(path).isFile() then
      EditorUtil.fromRecy = true
      EditorUtil.load(path)
      return true
    end
  end
  return false
end

function onResume()
  Init.initBar()
  Init.initFunctionTab()
  Init.applyTabletMode()
  EditorUtil.refreshMinimap(false)
  pcall(function() activity.invalidateOptionsMenu() end)
  -- 消费 ActivityUtil 兜底 pending（finishWith 同时写 SharedData）
  pcall(function()
    local ActivityUtil = require "mods.utils.ActivityUtil"
    local pending = ActivityUtil.takePending()
    if pending then
      handleNavAction(pending.action, pending.payload)
    end
  end)
end

-- 子页 this.result / ActivityUtil.finishWith 回传
function onResult(name, action, path)
  if handleNavAction(action, path) then
    -- 已由 result 消费，清掉兜底 pending，避免 onResume 再打开一次
    pcall(function()
      require("mods.utils.ActivityUtil").takePending()
    end)
    return true
  end
end

function onConfigurationChanged(config)
  -- 旋转/分屏后重新量侧栏与避让
  if Init.applyTabletMode then
    drawer.post(function()
      Init.applyTabletMode()
      EditorUtil.refreshMinimap(false)
      pcall(function() activity.invalidateOptionsMenu() end)
    end)
  end
end

function onDestroy()
  Init.stopCheck()
end

function onOptionsItemSelected(item)
  if item.getItemId() == android.R.id.home then
    -- 平板常驻侧栏时不切换抽屉
    if Init.isTabletMode and Init.isTabletMode() then
      return
    end
    if not drawer.isDrawerOpen(GravityCompat.START) then
      EditorUtil.save()
      drawer.openDrawer(GravityCompat.START)
    else
      drawer.closeDrawer(GravityCompat.START)
    end
  end
end

function onCreateOptionsMenu(menu)
  local colorTitle = ColorUtil.getColorOnBackground()
  local tablet = isTabletUi()
  local icon = function(name)
    local d = nil
    pcall(function()
      d = res.drawable(name, colorTitle)
    end)
    -- 失败时再试无着色 / ic_ 前缀
    if d == nil then
      pcall(function() d = res.drawable(name) end)
    end
    if d == nil then
      pcall(function() d = res.drawable("ic_" .. name, colorTitle) end)
    end
    return d
  end

  -- 核心：始终显示
  addAction(menu, res.string.run_code, icon("play"), showRunMenu, SHOW_AS_ACTION_ALWAYS)
  addAction(menu, res.string.undo, icon("undo"), function() mLuaEditor.undo() end, SHOW_AS_ACTION_ALWAYS)
  addAction(menu, res.string.redo, icon("redo"), function() mLuaEditor.redo() end, SHOW_AS_ACTION_ALWAYS)

  if tablet then
    -- 平板：常用项 ALWAYS 上顶栏（有图标才会显示）
    addAction(menu, res.string.save_file, icon("save"), Actions.saveCurrentFile, SHOW_AS_ACTION_ALWAYS)
    addAction(menu, res.string.search, icon("search"), Actions.showSearchBar, SHOW_AS_ACTION_ALWAYS)
    addAction(menu, res.string.format, icon("format"), Actions.formatCode, SHOW_AS_ACTION_IF_ROOM)
    addAction(menu, res.string.layout_helper, icon("layout_helper"), Actions.openLayoutHelper, SHOW_AS_ACTION_IF_ROOM)
    addAction(menu, res.string.setting, icon("settings"), Actions.openSetting, SHOW_AS_ACTION_IF_ROOM)
    addAction(menu, res.string.help, icon("help"), Actions.openHelp, SHOW_AS_ACTION_IF_ROOM)
  end

  -- 分组子菜单
  local fileMenu = menu.addSubMenu(res.string.file .. "…")
  if not tablet then
    addItem(fileMenu, res.string.save_file, Actions.saveCurrentFile, nil, icon("save"))
  end
  addItem(fileMenu, res.string.compile, Actions.compileCurrentFile, nil, icon("memory"))

  local codeMenu = menu.addSubMenu(res.string.code .. "…")
  if not tablet then
    addItem(codeMenu, res.string.format, Actions.formatCode, nil, icon("format"))
    addItem(codeMenu, res.string.search, Actions.showSearchBar, nil, icon("search"))
  end
  addItem(codeMenu, res.string.check_error, Actions.checkError, nil, icon("bug_report"))
  addItem(codeMenu, "Java" .. res.string.editor, Actions.openJavaEditor, nil, icon("java"))
  addItem(codeMenu, res.string.analysis_import, Actions.openJavaAnalysis, nil, icon("code"))

  local projectMenu = menu.addSubMenu(res.string.project .. "…")
  addItem(projectMenu, res.string.build, Actions.openBuild, nil, icon("build"))
  addItem(projectMenu, res.string.create_project, Actions.createProject, nil, icon("add_box"))
  addItem(projectMenu, res.string.project_settings, Actions.openProjectSettings, nil, icon("settings"))
  addItem(projectMenu, res.string.backup, Actions.backupCurrentProject, nil, icon("backup"))
  addItem(projectMenu, res.string.vconsole_inject, Actions.injectVConsole, nil, icon("bug_report"))

  local toolsMenu = menu.addSubMenu(res.string.tools .. "…")
  addItem(toolsMenu, res.string.logs, function() ActivityUtil.showLog(activity) end, nil, icon("article"))
  addItem(toolsMenu, res.string.media_browser, Actions.openMedia, nil, icon("folder"))
  addItem(toolsMenu, res.string.api_title, Actions.openApi, nil, icon("menu_book"))
  addItem(toolsMenu, res.string.resource_browser, Actions.openResource, nil, icon("inventory"))
  if not tablet then
    addItem(toolsMenu, res.string.layout_helper, Actions.openLayoutHelper, nil, icon("layout_helper"))
  end
  addItem(toolsMenu, res.string.request_permission, requestCommonPermissions, nil, icon("security"))

  local moreMenu = menu.addSubMenu(res.string.more .. "…")
  if not tablet then
    addItem(moreMenu, "NeLuaJ+ " .. res.string.help, Actions.openHelp, nil, icon("help"))
  end
  addItem(moreMenu, res.string.about, showAbout, nil, icon("info"))
  if not tablet then
    addItem(moreMenu, res.string.setting, Actions.openSetting, nil, icon("settings"))
  end

  addItem(menu, res.string.exit, function() activity.finish(true) end, nil, icon("exit"))

  return true
end

function onPause()
  if Bean.Path.this_file ~= "" then
    EditorUtil.save()
  end
end

this.addOnBackPressedCallback(function()
  if _exit + 2 > os.time() then
    activity.finish(true)
    return
  end

  if (not (Init.isTabletMode and Init.isTabletMode())) and drawer.isDrawerOpen(GravityCompat.START) then
    drawer.closeDrawer(GravityCompat.START)
    return
  end

  if mSearch.getVisibility() == VISIBLE then
    Actions.hideSearchBar()
    return
  end

  EditorUtil.save()
  Snackbar.make(coordinatorLayout, res.string.confirm_exit, Snackbar.LENGTH_SHORT)
    .setAnchorView(ps_bar)
    .setAction(res.string.exit, function()
      activity.finish(true)
    end)
    .show()
  _exit = os.time()
end)
