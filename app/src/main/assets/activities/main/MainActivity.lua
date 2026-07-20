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

local SHOW_AS_ACTION_ALWAYS = 2
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

local function addAction(menu, title, icon, onClick)
  local item = menu.add(title).setShowAsAction(SHOW_AS_ACTION_ALWAYS)
  if icon then
    item.setIcon(icon)
  end
  item.onMenuItemClick = onClick
  return item
end

local function addItem(menu, title, onClick)
  menu.add(title).onMenuItemClick = onClick
end

local function showRunMenu()
  if not Actions.requireOpenFile() then return end

  if Bean.Project.this_project == "" then
    Actions.runCurrent()
    return
  end

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

function onResume()
  Init.initBar()
end

function onDestroy()
  Init.stopCheck()
end

function onOptionsItemSelected(item)
  if item.getItemId() == android.R.id.home then
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

  addAction(menu, res.string.run_code, res.drawable("play", colorTitle), showRunMenu)
  addAction(menu, res.string.undo, res.drawable("undo", colorTitle), function() mLuaEditor.undo() end)
  addAction(menu, res.string.redo, res.drawable("redo", colorTitle), function() mLuaEditor.redo() end)

  local fileMenu = menu.addSubMenu(res.string.file .. "…")
  addItem(fileMenu, res.string.save_file, Actions.saveCurrentFile)
  addItem(fileMenu, res.string.compile, Actions.compileCurrentFile)

  local codeMenu = menu.addSubMenu(res.string.code .. "…")
  addItem(codeMenu, res.string.format, Actions.formatCode)
  addItem(codeMenu, res.string.check_error, Actions.checkError)
  addItem(codeMenu, res.string.search, Actions.showSearchBar)
  addItem(codeMenu, "Java" .. res.string.editor, Actions.openJavaEditor)
  addItem(codeMenu, res.string.analysis_import, Actions.openJavaAnalysis)

  local projectMenu = menu.addSubMenu(res.string.project .. "…")
  addItem(projectMenu, res.string.build, Actions.openBuild)
  addItem(projectMenu, res.string.create_project, Actions.createProject)
  addItem(projectMenu, res.string.backup, Actions.backupCurrentProject)

  local toolsMenu = menu.addSubMenu(res.string.tools .. "…")
  addItem(toolsMenu, res.string.logs, function() ActivityUtil.showLog(activity) end)
  addItem(toolsMenu, res.string.api_title, Actions.openApi)
  addItem(toolsMenu, res.string.resource_browser, Actions.openResource)
  addAction(toolsMenu, res.string.layout_helper, nil, Actions.openLayoutHelper)
  addItem(toolsMenu, res.string.request_permission, requestCommonPermissions)

  local moreMenu = menu.addSubMenu(res.string.more .. "…")
  addItem(moreMenu, "NeLuaJ+ " .. res.string.help, Actions.openHelp)
  addItem(moreMenu, res.string.about, showAbout)
  addItem(moreMenu, res.string.setting, function() ActivityUtil.new("setting") end)

  addItem(menu, res.string.exit, function() activity.finish(true) end)
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

  if drawer.isDrawerOpen(GravityCompat.START) then
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
