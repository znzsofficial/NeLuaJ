--- 主界面菜单 / 功能栏动作
import "java.io.File"
import "android.content.Intent"
import "android.content.ComponentName"
import "android.animation.AnimatorSet"
import "android.animation.ObjectAnimator"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"
import "com.androlua.LuaUtil"

import "mods.utils.EditorUtil"
import "mods.utils.ActivityUtil"

local RunLauncher = require "mods.project.RunLauncher"
local DecelerateInterpolator = luajava.newInstance "android.view.animation.DecelerateInterpolator"
local loadlayout = loadlayout

local INVISIBLE = 4
local VISIBLE = 0
local GONE = 8

local Actions = {}

local BUILDER_PACKAGE = "com.nekolaska.Builder"
local BUILDER_ACTIVITY = "com.nekolaska.MainActivity"
local BUILDER_OPEN_PROJECT = "com.nekolaska.Builder.action.OPEN_PROJECT"
local BUILDER_PROJECT_PATH = "com.nekolaska.Builder.extra.PROJECT_PATH"

local function snack(msg)
  MainActivity.Public.snack(msg)
end

local function showCompileResult(title, message)
  MaterialAlertDialogBuilder(activity)
    .setTitle(title)
    .setMessage(message)
    .setPositiveButton(android.R.string.ok, nil)
    .show()
end

local function requireOpenFile()
  if mLuaEditor.getVisibility() == INVISIBLE then
    snack(res.string.no_file)
    return false
  end
  return true
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

--- 复制 vConsole.lua 到工程根，并将 require 行放入剪贴板（不改 main.lua）
function Actions.injectVConsole()
  if Bean.Project.this_project == "" then
    snack(res.string.noProject)
    return
  end
  local projectDir = Bean.Path.app_root_pro_dir .. "/" .. Bean.Project.this_project
  local dest = projectDir .. "/vConsole.lua"
  local src = this.getLuaDir("vConsole.lua")
  if not src or src == "" or not File(src).isFile() then
    snack(res.string.vconsole_inject_no_src)
    return
  end

  LuaUtil.copyFile(src, dest)
  if not File(dest).isFile() then
    snack(res.string.vconsole_inject_copy_fail)
    return
  end

  local requireLine = 'require "vConsole"'
  local ClipData = luajava.bindClass "android.content.ClipData"
  local Context = luajava.bindClass "android.content.Context"
  local cm = activity.getSystemService(Context.CLIPBOARD_SERVICE)
  cm.setPrimaryClip(ClipData.newPlainText("vConsole", requireLine))
  MainActivity.RecyclerView.update()

  snack(res.string.vconsole_inject_ok)
end

function Actions.formatCode()
  mLuaEditor.format()
end

--- 选中内容切换 --[[ ... ]] 多行注释
function Actions.toggleBlockComment()
  if not requireOpenFile() then return end
  EditorUtil.toggleBlockComment(mLuaEditor)
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
  local saved = EditorUtil.save()
  if saved ~= true and saved ~= "same" then
    showCompileResult(res.string.compile_failed, res.string.compile_save_failed)
    return
  end

  local output = path .. "c"
  local called, result = pcall(function() return this.dumpFile(path, output) end)
  if called and result and result.ok then
    MainActivity.RecyclerView.update()
    showCompileResult(res.string.compile_success, res.string.compile_output:format(output))
    return
  end

  local message = called and result and tostring(result.error or "") or ""
  if message == "" then message = res.string.compile_failed end
  local line = called and result and tonumber(result.line)
  if line and line > 0 then
    pcall(function() mLuaEditor.gotoLine(line) end)
    message = res.string.compile_error_line:format(line, message)
  end
  showCompileResult(res.string.compile_failed, message)
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

function Actions.openResource()
  ActivityUtil.open("resource")
end

function Actions.openMedia()
  ActivityUtil.open("media")
end

function Actions.openJavaAnalysis()
  if not requireOpenFile() then return end
  ActivityUtil.open("fix", Bean.Path.this_file)
end

function Actions.openBuild()
  if Bean.Project.this_project == "" then
    snack(res.string.noProject)
    return
  end

  local projectDir = Bean.Path.app_root_pro_dir .. "/" .. Bean.Project.this_project
  local project = File(projectDir)
  if not project.isDirectory() then
    snack(res.string.noProject)
    return
  end
  if not File(projectDir .. "/init.lua").isFile() then
    snack(res.string.project_no_init)
    return
  end

  if Bean.Path.this_file ~= "" then
    local saveCalled, saved = pcall(EditorUtil.save)
    if not saveCalled or (saved ~= true and saved ~= "same") then
      snack(res.string.save_fail)
      return
    end
  end
  local projectPath = projectDir
  pcall(function() projectPath = tostring(project.getCanonicalPath()) end)

  local intent = Intent()
  intent.setComponent(ComponentName(BUILDER_PACKAGE, BUILDER_ACTIVITY))
  intent.setAction(BUILDER_OPEN_PROJECT)
  intent.putExtra(BUILDER_PROJECT_PATH, projectPath)
  intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
  intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)

  local launched = pcall(function() this.startActivity(intent) end)
  if not launched then
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

function Actions.runCurrent()
  if not requireOpenFile() then return end
  EditorUtil.save()
  RunLauncher.launchScript(this, Bean.Path.this_file, { snack = snack })
end

function Actions.runProject()
  if Bean.Project.this_project == "" then
    snack(res.string.noProject)
    return
  end
  EditorUtil.save()
  RunLauncher.launchScript(
    this,
    Bean.Path.app_root_pro_dir .. "/" .. Bean.Project.this_project .. "/main.lua",
    { snack = snack }
  )
end

function Actions.runOnDebugApp()
  local debugApp = this.getSharedData("debug_app", nil)
  if not debugApp then return end
  if Bean.Project.this_project == "" then
    snack(res.string.noProject)
    return
  end
  EditorUtil.save()
  RunLauncher.launchDebugApp(
    this,
    debugApp,
    Bean.Path.app_root_pro_dir .. "/" .. Bean.Project.this_project .. "/main.lua"
  )
end

function Actions.openAiChat()
  local ChatUI = require("mods.agent.ChatUI")
  ChatUI.show()
end

return Actions
