---@diagnostic disable: undefined-global
local _M = {}
local Bean = Bean
import "java.io.File"

import "android.widget.LinearLayout"
import "android.widget.TextView"
import "android.animation.AnimatorSet"
import "android.animation.ObjectAnimator"
import "androidx.appcompat.app.ActionBarDrawerToggle"
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

local function addChip(parent, text, onClick)
  parent.addView(loadlayout {
    LinearLayout,
    {
      TextView,
      TextSize = "5sp",
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

local function createSymbolButton(symbol)
  return loadlayout {
    LinearLayout,
    layout_width = "40dp",
    layout_height = "36dp",
    {
      TextView,
      layout_width = "40dp",
      layout_height = "36dp",
      gravity = "center",
      clickable = true,
      focusable = true,
      TextSize = "5sp",
      BackgroundResource = rippleRes,
      text = symbol,
      onClick = function()
        pasteSymbol(symbol)
      end,
    },
  }
end

local function createSymbolRow()
  return loadlayout {
    LinearLayout,
    orientation = "horizontal",
    layout_width = "wrap",
    layout_height = "36dp",
  }
end

local function fillSymbolRow(row, symbols, fromIndex, toIndex)
  for i = fromIndex, toIndex do
    row.addView(createSymbolButton(symbols[i]))
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
  searchAnim.setDuration(500).setInterpolator(DecelerateInterpolator).start()
end

function Actions.hideSearchBar(onEnd)
  local dismissAnim = AnimatorSet()
  dismissAnim.play(ObjectAnimator.ofFloat(mSearch, "translationY", { 0, -50 }))
    .with(ObjectAnimator.ofFloat(mSearch, "alpha", { 1, 0 }))
  dismissAnim.setDuration(500).setInterpolator(DecelerateInterpolator).start()
  this.delay(500, function()
    mSearch.setVisibility(GONE)
    if onEnd then onEnd() end
  end)
end

function Actions.openApi()
  ActivityUtil.new("api")
end

function Actions.openHelp()
  ActivityUtil.new("help")
end

function Actions.openResource()
  ActivityUtil.new("resource")
end

function Actions.openJavaAnalysis()
  if not requireOpenFile() then return end
  ActivityUtil.new("java", Bean.Path.this_file)
end

function Actions.openBuild()
  if not this.startPackage("com.nekolaska.Builder") then
    snack(res.string.no_builder)
  end
end

function Actions.createProject()
  MainActivity.Public.createProject()
end

function Actions.openJavaEditor()
  MaterialAlertDialogBuilder(this)
    .setTitle(res.string.file_to_open)
    .setView(loadlayout(res.layout.dialog_fileinput))
    .setPositiveButton(android.R.string.ok, function()
      ActivityUtil.new("java", file_name.getText())
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

function Actions.runCurrent()
  if not requireOpenFile() then return end
  EditorUtil.save()
  activity.newActivity(Bean.Path.this_file)
end

function Actions.runProject()
  if Bean.Project.this_project == "" then
    snack(res.string.noProject)
    return
  end
  EditorUtil.save()
  activity.newActivity(Bean.Path.app_root_pro_dir .. "/" .. Bean.Project.this_project .. "/main.lua")
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
  this.startActivity(intent)
end

local function buildFunctionActions()
  return {
    { title = res.string.save_file, onClick = Actions.saveCurrentFile },
    { title = res.string.backup, onClick = Actions.backupCurrentProject },
    { title = res.string.format, onClick = Actions.formatCode },
    { title = res.string.analysis_import, onClick = Actions.openJavaAnalysis },
    { title = res.string.api_title, onClick = Actions.openApi },
    { title = res.string.resource_browser, onClick = Actions.openResource },
    { title = res.string.search, onClick = Actions.showSearchBar },
    { title = res.string.build, onClick = Actions.openBuild },
    { title = res.string.create_project, onClick = Actions.createProject },
    { title = res.string.help, onClick = Actions.openHelp },
  }
end

_M.Actions = Actions
_M.VISIBLE = VISIBLE
_M.INVISIBLE = INVISIBLE
_M.GONE = GONE

_M.initView = function()
  mSearch.setVisibility(GONE)
  mSearch.post(function()
    SearchCode()
  end)
  local toggle = ActionBarDrawerToggle(activity, drawer, R.string.drawer_open, R.string.drawer_close)
  drawer.setDrawerListener(toggle)
  toggle.syncState()
  mLuaEditor.setVisibility(INVISIBLE)
  filetab.setPath(Bean.Path.this_dir)
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
  local count = #symbols

  ps_bar.removeAllViews()

  if twoRows and count > 0 then
    ps_bar.orientation = ORIENTATION_VERTICAL
    local mid = math.ceil(count / 2)
    ps_bar.addView(fillSymbolRow(createSymbolRow(), symbols, 1, mid))
    if mid < count then
      ps_bar.addView(fillSymbolRow(createSymbolRow(), symbols, mid + 1, count))
    end
  else
    ps_bar.orientation = ORIENTATION_HORIZONTAL
    fillSymbolRow(ps_bar, symbols, 1, count)
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
