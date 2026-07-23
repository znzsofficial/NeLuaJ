---@diagnostic disable: undefined-global
--- 主界面装配：Actions + 平板 / 功能栏 / 符号栏 / 错误检查
local _M = {}

import "java.io.File"
import "androidx.appcompat.app.ActionBarDrawerToggle"
import "androidx.core.view.GravityCompat"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"

import "mods.functions.SearchCode"
import "mods.utils.EditorUtil"

local Actions = require "activities.main.Actions"
local TabletMode = require "activities.main.TabletMode"
local FunctionBar = require "activities.main.FunctionBar"
local SymbolBar = require "activities.main.SymbolBar"

local VISIBLE = 0
local INVISIBLE = 4
local GONE = 8

local errorTicker

_M.Actions = Actions
_M.VISIBLE = VISIBLE
_M.INVISIBLE = INVISIBLE
_M.GONE = GONE

_M.syncEditorEmptyState = function()
  TabletMode.syncEditorEmptyState()
  return _M
end

_M.applyTabletMode = function()
  TabletMode.apply()
  return _M
end

_M.isTabletMode = function()
  return TabletMode.isTabletMode()
end

_M.isLargeScreen = function()
  return TabletMode.isLargeScreen()
end

_M.initView = function()
  mSearch.setVisibility(GONE)
  mSearch.post(function()
    SearchCode()
  end)
  local drawerToggle = ActionBarDrawerToggle(activity, drawer, R.string.drawer_open, R.string.drawer_close)
  drawer.setDrawerListener(drawerToggle)
  drawerToggle.syncState()
  TabletMode.setDrawerToggle(drawerToggle)
  mLuaEditor.setVisibility(INVISIBLE)
  pcall(function()
    if open_drawer_btn then
      open_drawer_btn.onClick = function()
        if TabletMode.isTabletMode() then return end
        drawer.openDrawer(GravityCompat.START)
      end
    end
  end)
  filetab.setPath(Bean.Path.this_dir)
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
      .bindChrome()
      .update()
  end)
  swipeRefresh.onRefresh = function()
    MainActivity.RecyclerView.update()
  end
  return _M
end

_M.initFunctionTab = function()
  FunctionBar.render(mFunctionTab, Actions)
  return _M
end

_M.initBar = function()
  SymbolBar.init(ps_bar)
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
