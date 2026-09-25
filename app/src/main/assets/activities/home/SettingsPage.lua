--- 首页「设置」tab：setting_layout 唯一宿主。
--- 布局表加载后视图 id 落在本环境全局，SettingsWiring.apply() 完成事件接线；
--- 「关于」在此覆写为拓展版（版本 + 作者卡片 QQ + 仓库/打包器主页）。
local _M = {}

local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")

local SettingsWiring = require "mods.settings.SettingsWiring"

local ColorUtil = this.themeUtil
local res = res

local background = ColorUtil.getColorBackground()
local built = nil
local wiringApplied = false

local function openUrl(url)
  pcall(function()
    local Intent = luajava.bindClass("android.content.Intent")
    local Uri = luajava.bindClass("android.net.Uri")
    activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
  end)
end

--- 拓展版「关于」：作者卡片（QQ 跳转）+ 仓库与打包器主页 + 版本信息
local function showExpandedAbout()
  local MaterialAlertDialogBuilder = luajava.bindClass("com.google.android.material.dialog.MaterialAlertDialogBuilder")
  local views = {}
  local content = loadlayout(res.layout.dialog_about, views)
  MaterialAlertDialogBuilder(activity)
    .setTitle("NeLuaJ+")
    .setView(content)
    .setPositiveButton(android.R.string.ok, nil)
    .setNegativeButton(res.string.home_about_github, function()
      openUrl("https://github.com/znzsofficial/NeLuaJ")
    end)
    .setNeutralButton(res.string.home_about_builder, function()
      openUrl("https://github.com/znzsofficial/NeLuaJ-Builder")
    end)
    .show()
  -- 作者卡片：跳转 QQ 群名片（未安装 QQ 时提示）
  views.author.onClick = function()
    xpcall(function()
      local Intent = luajava.bindClass("android.content.Intent")
      local Uri = luajava.bindClass("android.net.Uri")
      activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(
        "mqqapi://card/show_pslcard?src_type=internal&source=sharecard&version=1&uin=1071723770")))
    end, function()
      local Toast = luajava.bindClass("android.widget.Toast")
      pcall(function()
        Toast.makeText(activity, res.string.please_install_qq, Toast.LENGTH_SHORT).show()
      end)
    end)
  end
end

function _M.refresh()
  -- 设置项静态，无需动态刷新
end

function _M.build()
  if built then return built end
  -- 根布局表（含 ScrollView）直接加载；id 落在本环境全局供接线使用
  built = loadlayout(res.layout.setting_layout)
  if not wiringApplied then
    SettingsWiring.apply()
    wiringApplied = true
  end
  -- 接线完成后再覆写「关于」行为（拓展版替换默认版本弹窗）
  pcall(function()
    if AboutItem then AboutItem.onClick = showExpandedAbout end
  end)
  return built
end

return _M
