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
local AppInit = require "mods.utils.AppInit"

local Actions = Init.Actions
local _exit = 0
local ColorUtil = this.themeUtil
local res = res

-- 作为编辑器路由页直接启动时的工程目录参数（首页打开工程时传入）
local launchProject = tostring(select(1, ...) or "")

local SHOW_AS_ACTION_NEVER = 0
local SHOW_AS_ACTION_IF_ROOM = 1
local SHOW_AS_ACTION_ALWAYS = 2
local SHOW_AS_ACTION_WITH_TEXT = 4
local SHOW_AS_ACTION_IF_ROOM_TEXT = 5 -- IF_ROOM | WITH_TEXT
local SHOW_AS_ACTION_ALWAYS_TEXT = 6 -- ALWAYS | WITH_TEXT
local VISIBLE = Init.VISIBLE
local INVISIBLE = Init.INVISIBLE
local GONE = Init.GONE

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

  -- 首页打开工程时传入目录：先切换工程上下文再装配视图，
  -- initView 会用 this_dir 初始化文件列表；restoreLastFile 检测到
  -- 上下文已被显式切换后会跳过「回退上次文件」，不再覆盖本次目标工程
  pcall(function()
    if launchProject ~= "" and File(launchProject).isDirectory()
        and tostring(Bean.Path.this_dir) ~= launchProject then
      local PathManager = require "mods.utils.PathManager"
      PathManager.updateDir(launchProject)
    end
  end)

  -- 首页壳重构（c5a4e90）时误把 initView 从装配链上删掉：搜索条默认可见、
  -- 抽屉开关无汉堡动画、文件列表初始路径未设置皆由此而来，此处恢复完整链
  Init.initView().initView2().initBar().initFunctionTab().initCheck().restoreLastFile()

  -- 带工程启动参数：恢复该工程上次的工作区（打开的文件标签/活动文件/光标）。
  -- 此时 this_dir 已是工程目录，restoreLastFile 的根目录守卫会自动跳过，
  -- 不会与工作区恢复互相干扰。
  pcall(function()
    if launchProject ~= "" then
      require("activities.main.Workspace").restoreCurrent()
    end
  end)

  -- 权限门禁已迁至首页；编辑器直达时仅做轻提示（文件操作会失败但不阻塞界面）
  if not this.checkStoragePermission() then
    Actions.snack(res.string.need_manage_permission)
  end
  AppInit.prepareDirs()
end

local function handleNavAction(action, path)
  if (action == "open_file" or action == "open_init") and type(path) == "string" and path ~= "" then
    if File(path).isFile() then
      EditorUtil.fromRecy = true
      EditorUtil.load(path)
      return true
    end
  end
  -- 会话中心回传：打开指定会话（必要时先切换工程）
  if action == "open_agent_conv" then
    pcall(function()
      require("mods.agent.ChatUI").openConversation(path)
    end)
    return true
  end
  if action == "open_agent_conv_switch" then
    local project, convId = tostring(path):match("^(.-)\n(.*)$")
    if project and project ~= "" and convId and convId ~= "" then
      pcall(function()
        local PathManager = require "mods.utils.PathManager"
        if tostring(Bean.Path.this_dir) ~= project then
          PathManager.updateDir(project)
          filetab.setPath(project)
          MainActivity.RecyclerView.update()
        end
        require("mods.agent.ChatUI").openConversation(convId)
      end)
      return true
    end
  end
  if action == "open_agent_new" then
    pcall(function()
      local PathManager = require "mods.utils.PathManager"
      if path ~= "" and tostring(Bean.Path.this_dir) ~= path then
        PathManager.updateDir(path)
        filetab.setPath(path)
        MainActivity.RecyclerView.update()
      end
      require("mods.agent.AgentChat").createConversation()
      require("mods.agent.ChatUI").show()
    end)
    return true
  end
  return false
end

--- 设置页改完编辑器偏好后即时应用（由 EditorUtil.notifyPrefsChanged 触发）
function onEditorPrefsChanged()
  EditorUtil.applyEditorPrefs()
end

function onResume()
  Init.initBar()
  Init.initFunctionTab()
  Init.applyTabletMode()
  EditorUtil.applyEditorPrefs()
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
  -- 旋转/分屏后重新量侧栏与避让；昼夜切换时重施光标色
  if Init.applyTabletMode then
    drawer.post(function()
      Init.applyTabletMode()
      EditorUtil.applyEditorPrefs()
      pcall(function() activity.invalidateOptionsMenu() end)
    end)
  end
end

function onDestroy()
  pcall(function()
    require("mods.agent.ChatUI").saveCurrentConversation()
  end)
  Init.stopCheck()
  pcall(function()
    local MagnifierManager = require "mods.utils.MagnifierManager"
    MagnifierManager.destroy()
  end)
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
  addAction(menu, res.string.ai_chat, icon("build"), Actions.openAiChat, SHOW_AS_ACTION_IF_ROOM)

  if tablet then
    -- 平板：常用项 ALWAYS 上顶栏（有图标才会显示）
    addAction(menu, res.string.save_file, icon("save"), Actions.saveCurrentFile, SHOW_AS_ACTION_ALWAYS)
    addAction(menu, res.string.search, icon("search"), Actions.showSearchBar, SHOW_AS_ACTION_ALWAYS)
    addAction(menu, res.string.format, icon("format"), Actions.formatCode, SHOW_AS_ACTION_IF_ROOM)
    addAction(menu, res.string.layout_helper, icon("layout_helper"), Actions.openLayoutHelper, SHOW_AS_ACTION_IF_ROOM)
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
  addItem(codeMenu, res.string.block_comment, Actions.toggleBlockComment, nil, icon("comment"))
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
  addItem(moreMenu, res.string.ai_center_title, function()
    local ActivityUtil = require "mods.utils.ActivityUtil"
    ActivityUtil.open("agent_center", Bean.Path.this_dir)
  end, nil, icon("ic_command"))

  addItem(menu, res.string.exit, function() activity.finish(true) end, nil, icon("exit"))

  return true
end

function onPause()
  -- 工程工作区（标签/活动文件/光标）随后台保存，供下次打开工程时恢复
  pcall(function()
    require("activities.main.Workspace").saveFor(Bean.Path.this_dir)
  end)
  if Bean.Path.this_file ~= "" then
    EditorUtil.save()
  end
  pcall(function()
    require("mods.agent.ChatUI").saveCurrentConversation()
  end)
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
