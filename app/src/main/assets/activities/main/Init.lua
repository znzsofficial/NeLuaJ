---@diagnostic disable: undefined-global
local _M = {}
local Bean = Bean
import "androidx.core.view.GravityCompat"
import "androidx.appcompat.app.ActionBarDrawerToggle"
--Material
import "com.google.android.material.snackbar.Snackbar"

import "mods.functions.SearchCode"
import "mods.utils.EditorUtil"
import "mods.utils.ActivityUtil"

local LinearLayout = luajava.bindClass "android.widget.LinearLayout"
local TextView = luajava.bindClass "android.widget.TextView"
local rippleRes = activity.obtainStyledAttributes({ android.R.attr.selectableItemBackground }).getResourceId(0, 0)

local loadlayout = loadlayout

_M.initView = function()
  local toggle = ActionBarDrawerToggle(activity, drawer, R.string.drawer_open, R.string.drawer_close)
  drawer.setDrawerListener(toggle)
  toggle.syncState()
  filetab.setPath(Bean.Path.this_dir)
  mSearch.setVisibility(8)
  mSearch.post(function()
    SearchCode()
  end)
  mLuaEditor.setVisibility(4)
  mLuaEditor.post(function()
    EditorUtil.init()
    bindClass "com.myopicmobile.textwarrior.common.PackageUtil".load(this)
  end)
  swipeRefresh.onRefresh = function()
    MainActivity.RecyclerView.update()
  end
  return _M
end

_M.initFunctionTab = function()
  local functions = {
    {
      res.string.save_file,
      function(v)
        if mLuaEditor.getVisibility() == 4 then
          MainActivity.Public.snack(res.string.no_file)
          return
        end
        switch
          EditorUtil.save()
          -- 目前只有使用okio保存时才能触发这个
         case "same"
          MainActivity.Public.snack(res.string.save_same)
         case
          true
          MainActivity.Public.snack(res.string.save_success)
         default
          MainActivity.Public.snack(res.string.save_fail)
        end
      end
    },
    {
      res.string.backup,
      function()
        if mLuaEditor.getVisibility() == 4 then
          MainActivity.Public.snack(res.string.no_file)
          return
         elseif Bean.Project.this_project == "" then
          MainActivity.Public.snack(res.string.noProject)
          return
        end
        local project_dir = Bean.Path.app_root_pro_dir .. "/" .. Bean.Project.this_project
        local init = LuaFileUtil.loadLua(project_dir .. "/init.lua")
        LuaFileUtil.compress(project_dir, Bean.Path.app_root_dir .. "/Backup", init.app_name .. "-" .. os.date("%Y-%m-%d-%H-%M-%S") .. ".zip")
      end,
    },
    {
      res.string.format,
      function(v)
        mLuaEditor.format()
      end
    },
    {
      res.string.analysis_import,
      function()
        if mLuaEditor.getVisibility() == 4 then
          MainActivity.Public.snack(res.string.no_file)
          return
        end
        ActivityUtil.new("fix", Bean.Path.this_file)
      end
    },
    {
      res.string.api_title,
      function()
        ActivityUtil.new("api")
      end,
    },
    {
      res.string.build,
      function()
        if not this.startPackage("com.nekolaska.Builder") then
          MainActivity.Public.snack(res.string.no_builder)
        end
      end,
    },
    {
      res.string.create_project,
      function()
        MainActivity.Public.createProject()
      end,
    },
  }
  for k, v in ipairs(functions) do
    mFunctionTab.addView(loadlayout{
      LinearLayout,
      {
        TextView,
        TextSize = "5sp",
        BackgroundResource = rippleRes,
        text = v[1],
        paddingLeft="8dp",
        paddingRight="8dp",
        paddingTop="6dp",
        paddingBottom="6dp",
        onClick=v[2]
      },
    })
  end
  return _M
end

_M.initBar = function()
  local t = {
    "fun", "(", ")", "[", "]", "{", "}",
    "\"", "=", ":", ".", ",", ";", "_",
    "+", "-", "*", "/", "\\", "%",
    "#", "^", "$", "?", "&", "|",
    "<", ">", "~", "'"
  }
  for k, v in ipairs(t) do
    ps_bar.addView(loadlayout{
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
        text = v,
        onClick = function()
          if v == "fun" then
            v = "function()"
          end
          mLuaEditor.paste(v)
        end,
      },
    })
  end
  return _M
end

_M.initCheck = function()
  local textView = error_Text
  local layout = textView.getParent()
  textView.onClick = function()
    textView.text = mLuaEditor.getError()
  end
  local ticker = luajava.newInstance "com.androlua.Ticker"
  ticker.Period = 250
  ticker.onTick = function()
    local error = mLuaEditor.getError()
    if error then
      layout.visibility = 0
      textView.text = error
     else
      layout.visibility = 8
    end
  end
  ticker.start()
  return _M
end

return _M