---@diagnostic disable: undefined-global
local _M = {}
local Bean = Bean
import "java.io.File"

import "android.widget.LinearLayout"
import "android.widget.TextView"
import "android.animation.AnimatorSet"
import "android.animation.ObjectAnimator"
import "androidx.appcompat.app.ActionBarDrawerToggle"
import "androidx.core.view.GravityCompat"
import "androidx.drawerlayout.widget.DrawerLayout"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"

import "mods.functions.SearchCode"
import "mods.utils.EditorUtil"
import "mods.utils.ActivityUtil"

local DecelerateInterpolator = luajava.newInstance "android.view.animation.DecelerateInterpolator"
local rippleRes = activity.obtainStyledAttributes({ android.R.attr.selectableItemBackground }).getResourceId(0, 0)
local loadlayout = loadlayout

local ORIENTATION_HORIZONTAL = 0
local ORIENTATION_VERTICAL = 1
local VISIBLE = 0
local INVISIBLE = 4
local GONE = 8

local DEFAULT_SYMBOL_BAR = {
  "fun", "(", ")", "[", "]", "{", "}",
  "\"", "=", ":", ".", ",", ";", "_",
  "+", "-", "*", "/", "\\", "%",
  "#", "^", "$", "?", "&", "|",
  "<", ">", "~", "'"
}

local Actions = {}
local errorTicker

local function isSharedTruthy(value)
  return value == true or value == "true" or value == 1
end

local function snack(msg)
  MainActivity.Public.snack(msg)
end

local function requireOpenFile()
  if mLuaEditor.getVisibility() == INVISIBLE then
    snack(res.string.no_file)
    return false
  end
  return true
end

local DEFAULT_FUNCTION_TAB_TEXT_SIZE = 5
local DEFAULT_SYMBOL_BAR_TEXT_SIZE = 5
local MIN_BAR_TEXT_SIZE = 5
local MAX_BAR_TEXT_SIZE = 24

local function clampBarTextSize(value, defaultSize)
  local n = tonumber(value)
  if not n then return defaultSize end
  n = math.floor(n + 0.5)
  if n < MIN_BAR_TEXT_SIZE then return MIN_BAR_TEXT_SIZE end
  if n > MAX_BAR_TEXT_SIZE then return MAX_BAR_TEXT_SIZE end
  return n
end

local function getFunctionTabTextSize()
  return clampBarTextSize(this.getSharedData("function_tab_text_size", DEFAULT_FUNCTION_TAB_TEXT_SIZE), DEFAULT_FUNCTION_TAB_TEXT_SIZE)
end

local function getSymbolBarTextSize()
  return clampBarTextSize(this.getSharedData("symbol_bar_text_size", DEFAULT_SYMBOL_BAR_TEXT_SIZE), DEFAULT_SYMBOL_BAR_TEXT_SIZE)
end

local function addChip(parent, text, onClick)
  local textSize = getFunctionTabTextSize()
  parent.addView(loadlayout {
    LinearLayout,
    {
      TextView,
      TextSize = textSize .. "sp",
      BackgroundResource = rippleRes,
      text = text,
      paddingLeft = "8dp",
      paddingRight = "8dp",
      paddingTop = "6dp",
      paddingBottom = "6dp",
      onClick = onClick,
    },
  })
end

local function parseSymbolBar(raw)
  if type(raw) ~= "string" or raw == "" then
    return nil
  end
  local symbols = {}
  for line in (raw .. "\n"):gmatch("(.-)\n") do
    local symbol = line:match("^%s*(.-)%s*$")
    if symbol ~= "" then
      symbols[#symbols + 1] = symbol
    end
  end
  return #symbols > 0 and symbols or nil
end

local function pasteSymbol(symbol)
  if symbol == "fun" then
    mLuaEditor.paste("function()")
  else
    mLuaEditor.paste(symbol)
  end
end

local function createSymbolButton(symbol, textSize)
  textSize = textSize or getSymbolBarTextSize()
  -- 小字号保持原先 40×36；字号变大时再略放大
  local side = math.max(40, math.floor(textSize * 3.2 + 0.5))
  local height = math.max(36, math.floor(textSize * 2.8 + 0.5))
  if textSize <= 6 then
    side, height = 40, 36
  end
  local sideDp = side .. "dp"
  local heightDp = height .. "dp"
  return loadlayout {
    LinearLayout,
    layout_width = sideDp,
    layout_height = heightDp,
    {
      TextView,
      layout_width = sideDp,
      layout_height = heightDp,
      gravity = "center",
      clickable = true,
      focusable = true,
      TextSize = textSize .. "sp",
      BackgroundResource = rippleRes,
      text = symbol,
      onClick = function()
        pasteSymbol(symbol)
      end,
    },
  }
end

local function createSymbolRow(rowHeightDp)
  return loadlayout {
    LinearLayout,
    orientation = "horizontal",
    layout_width = "wrap",
    layout_height = (rowHeightDp or 36) .. "dp",
  }
end

local function fillSymbolRow(row, symbols, fromIndex, toIndex, textSize)
  for i = fromIndex, toIndex do
    row.addView(createSymbolButton(symbols[i], textSize))
  end
  return row
end

function Actions.snack(msg)
  snack(msg)
end

function Actions.requireOpenFile()
  return requireOpenFile()
end

function Actions.saveCurrentFile()
  if not requireOpenFile() then return end
  switch EditorUtil.save()
   case "same"
    snack(res.string.save_same)
   case true
    snack(res.string.save_success)
   default
    snack(res.string.save_fail)
  end
end

function Actions.backupCurrentProject()
  if not requireOpenFile() then return end
  if Bean.Project.this_project == "" then
    snack(res.string.noProject)
    return
  end
  local projectDir = Bean.Path.app_root_pro_dir .. "/" .. Bean.Project.this_project
  local init = LuaFileUtil.loadLua(projectDir .. "/init.lua")
  local zipName = (init.app_name or "Untitled") .. "-" .. os.date("%Y-%m-%d-%H-%M-%S") .. ".zip"
  LuaFileUtil.compress(projectDir, Bean.Path.app_root_dir .. "/Backup", zipName)
  snack(res.string.backup .. ": " .. zipName)
end

function Actions.formatCode()
  mLuaEditor.format()
end

function Actions.undo()
  mLuaEditor.undo()
end

function Actions.redo()
  mLuaEditor.redo()
end

function Actions.checkError()
  print(mLuaEditor.getError() or res.string.no_error)
end

function Actions.compileCurrentFile()
  if not requireOpenFile() then return end
  local path = Bean.Path.this_file
  this.dumpFile(path, path .. "c")
  MainActivity.RecyclerView.update()
end

function Actions.showSearchBar()
  mSearch.setVisibility(VISIBLE)
  local searchAnim = AnimatorSet()
  local translateY = ObjectAnimator.ofFloat(mSearch, "translationY", { -50, 0 })
  local alpha = ObjectAnimator.ofFloat(mSearch, "alpha", { 0, 1 })
  searchAnim.play(alpha).with(translateY)
  searchAnim.setDuration(320).setInterpolator(DecelerateInterpolator).start()
  pcall(function()
    mSearchEdit.requestFocus()
    local imm = activity.getSystemService(activity.INPUT_METHOD_SERVICE)
    if imm then imm.showSoftInput(mSearchEdit, 0) end
  end)
end

function Actions.hideSearchBar(onEnd)
  local dismissAnim = AnimatorSet()
  dismissAnim.play(ObjectAnimator.ofFloat(mSearch, "translationY", { 0, -50 }))
    .with(ObjectAnimator.ofFloat(mSearch, "alpha", { 1, 0 }))
  dismissAnim.setDuration(280).setInterpolator(DecelerateInterpolator).start()
  this.delay(280, function()
    mSearch.setVisibility(GONE)
    pcall(function()
      local imm = activity.getSystemService(activity.INPUT_METHOD_SERVICE)
      if imm and mSearchEdit then imm.hideSoftInputFromWindow(mSearchEdit.getWindowToken(), 0) end
    end)
    if onEnd then onEnd() end
  end)
end

function Actions.openApi()
  ActivityUtil.open("api")
end

function Actions.openHelp()
  ActivityUtil.open("help")
end

function Actions.openSetting()
  ActivityUtil.open("setting")
end

function Actions.openResource()
  ActivityUtil.open("resource")
end

function Actions.openJavaAnalysis()
  if not requireOpenFile() then return end
  -- 导入分析 → FixActivity；Java 编辑器走 openJavaEditor
  ActivityUtil.open("fix", Bean.Path.this_file)
end

function Actions.openBuild()
  if not this.startPackage("com.nekolaska.Builder") then
    snack(res.string.no_builder)
  end
end

function Actions.createProject()
  MainActivity.Public.createProject()
end

function Actions.openProjectSettings(projectDir)
  local dir = projectDir
  if type(dir) ~= "string" or dir == "" then
    if Bean.Project.this_project == "" then
      snack(res.string.noProject)
      return
    end
    dir = Bean.Path.app_root_pro_dir .. "/" .. Bean.Project.this_project
  end
  if not File(dir).isDirectory() then
    snack(res.string.noProject)
    return
  end
  ActivityUtil.open("project_settings", dir)
end

function Actions.openJavaEditor()
  MaterialAlertDialogBuilder(this)
    .setTitle(res.string.file_to_open)
    .setView(loadlayout(res.layout.dialog_fileinput))
    .setPositiveButton(android.R.string.ok, function()
      ActivityUtil.open("java", file_name.getText())
    end)
    .setNegativeButton(android.R.string.cancel, nil)
    .show()
  file_name.setHint(res.string.path)
  file_name.setText(Bean.Path.this_file).setSingleLine(false)
end

function Actions.openLayoutHelper()
  if not requireOpenFile() then return end
  EditorUtil.save()
  activity.newActivity(ActivityUtil.lua_path .. "/activities/layouthelper/LayoutHelperActivity.lua", {
    Bean.Path.this_file,
    Bean.Path.app_root_pro_dir .. "/" .. mToolBar.getTitle()
  })
end

local function isRunInWindow()
  return isSharedTruthy(this.getSharedData("run_in_window", false))
end

--- 是否真支持 freeform 小窗（手机多数只有分屏，不要用 LAUNCH_ADJACENT）
--- 注意：isInMultiWindowMode 在分屏时也为 true，不能当作 freeform 依据
local function supportsFreeformWindow()
  local ok, supported = pcall(function()
    local Build = luajava.bindClass "android.os.Build"
    if Build.VERSION.SDK_INT < 24 then return false end
    local pm = activity.getPackageManager()
    -- FEATURE_FREEFORM_WINDOW_MANAGEMENT = "android.software.freeform_window_management"
    return pm.hasSystemFeature("android.software.freeform_window_management")
  end)
  return ok and supported
end

--- 小窗运行：仅 freeform；绝不使用 LAUNCH_ADJACENT（手机会强制分屏卡死）
--- @return boolean 是否成功按小窗启动
local function launchScriptWindow(path)
  if not supportsFreeformWindow() then
    return false
  end
  local Intent = luajava.bindClass "android.content.Intent"
  local Uri = luajava.bindClass "android.net.Uri"
  local Rect = luajava.bindClass "android.graphics.Rect"
  local ActivityOptions = luajava.bindClass "android.app.ActivityOptions"
  local LuaActivityX = luajava.bindClass "com.androlua.LuaActivityX"

  local intent = Intent(activity, LuaActivityX)
  intent.setData(Uri.parse("file://" .. path))
  intent.putExtra("name", path)
  -- 独立任务栈，便于与编辑器并存；不要 LAUNCH_ADJACENT
  intent.addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT)
  intent.addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
  intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

  local dm = this.getResources().getDisplayMetrics()
  local w = math.floor(dm.widthPixels * 0.55 + 0.5)
  local h = math.floor(dm.heightPixels * 0.65 + 0.5)
  local minW = math.floor(this.dpToPx(300) + 0.5)
  local minH = math.floor(this.dpToPx(400) + 0.5)
  if w < minW then w = math.min(minW, dm.widthPixels) end
  if h < minH then h = math.min(minH, dm.heightPixels) end
  local left = math.floor((dm.widthPixels - w) * 0.55 + 0.5)
  local top = math.floor(dm.heightPixels * 0.15 + 0.5)
  local bounds = Rect(left, top, left + w, top + h)
  local opts = ActivityOptions.makeBasic()
  local okBounds = pcall(function()
    opts.setLaunchBounds(bounds)
  end)
  if okBounds then
    activity.startActivity(intent, opts.toBundle())
  else
    activity.startActivity(intent)
  end
  return true
end

local function launchScript(path)
  if isRunInWindow() then
    local ok, launched = pcall(launchScriptWindow, path)
    if ok and launched then
      return
    end
    -- 无 freeform / 失败：普通打开，避免分屏卡死
    if isRunInWindow() and not (ok and launched) then
      pcall(function()
        snack(res.string.run_in_window_fallback)
      end)
    end
  end
  activity.newActivity(path)
end

function Actions.runCurrent()
  if not requireOpenFile() then return end
  EditorUtil.save()
  launchScript(Bean.Path.this_file)
end

function Actions.runProject()
  if Bean.Project.this_project == "" then
    snack(res.string.noProject)
    return
  end
  EditorUtil.save()
  launchScript(Bean.Path.app_root_pro_dir .. "/" .. Bean.Project.this_project .. "/main.lua")
end

function Actions.runOnDebugApp()
  local debugApp = this.getSharedData("debug_app", nil)
  if not debugApp then return end
  if Bean.Project.this_project == "" then
    snack(res.string.noProject)
    return
  end
  EditorUtil.save()
  local Intent = luajava.bindClass "android.content.Intent"
  local ComponentName = luajava.bindClass "android.content.ComponentName"
  local Uri = luajava.bindClass "android.net.Uri"
  local intent = Intent()
  intent.setComponent(ComponentName(debugApp, "com.androlua.LuaActivity"))
  intent.setData(Uri.parse("file://" .. Bean.Path.app_root_pro_dir .. "/" .. Bean.Project.this_project .. "/main.lua"))
  -- 调试应用：不用 LAUNCH_ADJACENT；仅 freeform 时设 bounds
  if isRunInWindow() and supportsFreeformWindow() then
    local launched = false
    pcall(function()
      local Rect = luajava.bindClass "android.graphics.Rect"
      local ActivityOptions = luajava.bindClass "android.app.ActivityOptions"
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      intent.addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
      local dm = this.getResources().getDisplayMetrics()
      local w = math.floor(dm.widthPixels * 0.55 + 0.5)
      local h = math.floor(dm.heightPixels * 0.65 + 0.5)
      local left = math.floor((dm.widthPixels - w) * 0.55 + 0.5)
      local top = math.floor(dm.heightPixels * 0.15 + 0.5)
      local opts = ActivityOptions.makeBasic()
      opts.setLaunchBounds(Rect(left, top, left + w, top + h))
      this.startActivity(intent, opts.toBundle())
      launched = true
    end)
    if launched then return end
  end
  this.startActivity(intent)
end

local FunctionBarConfig = require "mods.utils.FunctionBarConfig"

-- id → Actions 回调（仅主界面构建 chips 时用）
local FUNCTION_BAR_CLICK = {
  save = function() Actions.saveCurrentFile() end,
  backup = function() Actions.backupCurrentProject() end,
  format = function() Actions.formatCode() end,
  undo = function() Actions.undo() end,
  redo = function() Actions.redo() end,
  search = function() Actions.showSearchBar() end,
  check_error = function() Actions.checkError() end,
  compile = function() Actions.compileCurrentFile() end,
  analysis_import = function() Actions.openJavaAnalysis() end,
  java_editor = function() Actions.openJavaEditor() end,
  layout_helper = function() Actions.openLayoutHelper() end,
  api = function() Actions.openApi() end,
  resource = function() Actions.openResource() end,
  build = function() Actions.openBuild() end,
  create_project = function() Actions.createProject() end,
  project_settings = function() Actions.openProjectSettings() end,
  run = function() Actions.runCurrent() end,
  logs = function() ActivityUtil.showLog(activity) end,
  setting = function() Actions.openSetting() end,
  help = function() Actions.openHelp() end,
}

local function buildFunctionActions()
  local ids = FunctionBarConfig.parseIds(this.getSharedData("function_bar", nil))
    or FunctionBarConfig.getDefaultIds()
  local actions = {}
  for _, id in ipairs(ids) do
    local item = FunctionBarConfig.getItem(id)
    local onClick = FUNCTION_BAR_CLICK[id]
    if item and onClick then
      actions[#actions + 1] = {
        id = id,
        title = FunctionBarConfig.resolveTitle(item),
        onClick = onClick,
      }
    end
  end
  if #actions == 0 then
    for _, id in ipairs(FunctionBarConfig.getDefaultIds()) do
      local item = FunctionBarConfig.getItem(id)
      local onClick = FUNCTION_BAR_CLICK[id]
      if item and onClick then
        actions[#actions + 1] = {
          id = id,
          title = FunctionBarConfig.resolveTitle(item),
          onClick = onClick,
        }
      end
    end
  end
  return actions
end

_M.Actions = Actions
_M.VISIBLE = VISIBLE
_M.INVISIBLE = INVISIBLE
_M.GONE = GONE

local TABLET_DRAWER_DP = 320
local PHONE_DRAWER_DP = 280
local TABLET_DRAWER_MAX_DP = 380
local TABLET_MINIMAP_DP = 72
local PHONE_MINIMAP_DP = 52
local drawerToggle
local lastTabletEnabled = nil

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
  -- 大屏按宽度比例取侧栏，夹在 320–380dp
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
  pcall(function()
    lp.rightMargin = px
  end)
  pcall(function()
    if lp.setMarginEnd then lp.setMarginEnd(px) end
  end)
  view.setLayoutParams(lp)
end

local MATCH_PARENT = -1
local LinearLayoutCls = luajava.bindClass "android.widget.LinearLayout"
local DrawerLayoutCls = luajava.bindClass "androidx.drawerlayout.widget.DrawerLayout"

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
  -- side_host 仅作布局占位，分栏时 head 直接挂在 workspace 上
  if not side_host then return end
  pcall(function()
    side_host.setVisibility(GONE)
    local lp = side_host.getLayoutParams()
    lp.width = 0
    pcall(function() lp.weight = 0 end)
    side_host.setLayoutParams(lp)
  end)
end

--- 平板：head 作为 workspace 左侧子 View（真分栏，不遮罩编辑器）
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

  local ok, err = pcall(function()
    local lp = LinearLayoutCls.LayoutParams(drawerW, MATCH_PARENT, 0)
    -- index 0：在 editor_content 左侧
    workspace.addView(head, 0, lp)
    head.setVisibility(VISIBLE)
    head.requestLayout()
    workspace.requestLayout()
  end)
  if not ok then
    -- 回退：不带 weight 的构造
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

--- 手机：把 head 挂回 Drawer 作为抽屉
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

--- 未打开文件时显示空状态按钮（平板常驻侧栏时隐藏）
_M.syncEditorEmptyState = function()
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
  return _M
end

--- 平板模式：真分栏侧栏 + 更宽缩略图/搜索（不用 LOCKED_OPEN，避免遮罩吞触摸）
_M.applyTabletMode = function()
  if not drawer or not head then return _M end
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

  -- 分栏后补一次列表刷新，避免 reparent 后空白
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
  return _M
end

_M.isTabletMode = isTabletModeOn
_M.isLargeScreen = isLargeScreen

_M.initView = function()
  mSearch.setVisibility(GONE)
  mSearch.post(function()
    SearchCode()
  end)
  drawerToggle = ActionBarDrawerToggle(activity, drawer, R.string.drawer_open, R.string.drawer_close)
  drawer.setDrawerListener(drawerToggle)
  drawerToggle.syncState()
  mLuaEditor.setVisibility(INVISIBLE)
  pcall(function()
    if open_drawer_btn then
      open_drawer_btn.onClick = function()
        if isTabletModeOn() then return end
        drawer.openDrawer(GravityCompat.START)
      end
    end
  end)
  filetab.setPath(Bean.Path.this_dir)
  -- 等布局完成再应用，避免 padding/宽度量错
  drawer.post(function()
    _M.applyTabletMode()
  end)
  return _M
end

_M.initView2 = function()
  mLuaEditor.post(function()
    EditorUtil.init()
    thread(function()
      luajava.bindClass "com.myopicmobile.textwarrior.common.PackageUtil".load(this)
    end)
  end)
  mRecycler.post(function()
    MainActivity.RecyclerView
      .init()
      .update()
  end)
  swipeRefresh.onRefresh = function()
    MainActivity.RecyclerView.update()
  end
  return _M
end

_M.initFunctionTab = function()
  mFunctionTab.removeAllViews()
  for _, action in ipairs(buildFunctionActions()) do
    addChip(mFunctionTab, action.title, action.onClick)
  end
  return _M
end

_M.initBar = function()
  local symbols = parseSymbolBar(this.getSharedData("symbol_bar", nil)) or DEFAULT_SYMBOL_BAR
  local twoRows = isSharedTruthy(this.getSharedData("symbol_bar_two_rows", false))
  local textSize = getSymbolBarTextSize()
  local rowHeight = (textSize <= 6) and 36 or math.max(36, math.floor(textSize * 2.8 + 0.5))
  local count = #symbols

  ps_bar.removeAllViews()

  if twoRows and count > 0 then
    ps_bar.orientation = ORIENTATION_VERTICAL
    local mid = math.ceil(count / 2)
    ps_bar.addView(fillSymbolRow(createSymbolRow(rowHeight), symbols, 1, mid, textSize))
    if mid < count then
      ps_bar.addView(fillSymbolRow(createSymbolRow(rowHeight), symbols, mid + 1, count, textSize))
    end
  else
    ps_bar.orientation = ORIENTATION_HORIZONTAL
    fillSymbolRow(ps_bar, symbols, 1, count, textSize)
  end

  return _M
end

_M.initCheck = function()
  local textView = error_Text
  local layout = textView.getParent()

  textView.onClick = function()
    MaterialAlertDialogBuilder(activity)
      .setTitle(res.string.check_error)
      .setMessage(textView.text)
      .show()
  end

  if errorTicker then
    pcall(function() errorTicker.stop() end)
    errorTicker = nil
  end

  errorTicker = luajava.newInstance "com.androlua.Ticker"
  errorTicker.Period = 250
  errorTicker.onTick = function()
    local error = mLuaEditor.getError()
    if error then
      layout.visibility = VISIBLE
      textView.text = error
    else
      layout.visibility = GONE
    end
  end
  errorTicker.start()
  return _M
end

_M.stopCheck = function()
  if errorTicker then
    pcall(function() errorTicker.stop() end)
    errorTicker = nil
  end
  return _M
end

_M.restoreLastFile = function()
  mLuaEditor.post(function()
    local lastPath = this.getSharedData("lastFile")
    local lastSelect = this.getSharedData("lastSelect")
    if not lastPath or not File(lastPath).exists() then
      return
    end

    EditorUtil.load(lastPath)
    EditorUtil.setSelection(lastSelect or 0)

    local proDir = Bean.Path.app_root_pro_dir
    if not lastPath:find(proDir, 1, true) then
      return
    end

    local afterPro = lastPath:sub(#proDir + 2)
    local projectName = afterPro:match("^([^/]+)")
    if not projectName then
      return
    end

    local projectDir = proDir .. "/" .. projectName
    if File(projectDir).isDirectory() then
      PathManager.updateDir(projectDir)
      filetab.setPath(projectDir)
      MainActivity.RecyclerView.update()
    end
  end)
  return _M
end

return _M
