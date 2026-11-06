--- 首页「设置」tab：setting_layout 唯一宿主。
--- 布局表加载后视图 id 落在本环境全局，SettingsWiring.apply() 完成事件接线；
--- 「关于」在此覆写为拓展版（版本 + 作者卡片 QQ + 仓库/打包器主页）。
local _M = {}

local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")

local SettingsWiring = require "mods.settings.SettingsWiring"

local ColorUtil = this.themeUtil
local res = res

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

function _M.dispose()
  require("mods.mcp.ServerUi").dismiss()
  -- A restored/re-created fragment must inflate fresh controls and wire the new Views.
  built = nil
  wiringApplied = false
end

function _M.build()
  if built then return built end
  -- 根布局表（含 ScrollView）直接加载；id 落在本环境全局供接线使用
  local source, layout = res.layout.setting_layout, {}
  for key, value in pairs(source) do layout[key] = value end
  layout[2] = {}
  for key, value in pairs(source[2]) do layout[2][key] = value end
  local MaterialCardView = luajava.bindClass("com.google.android.material.card.MaterialCardView")
  local attrs = activity.obtainStyledAttributes({ android.R.attr.selectableItemBackground })
  local ripple = attrs.getResourceId(0, 0)
  attrs.recycle()
  -- Extend the existing settings composition without a separate Activity.
  table.insert(layout[2], 3, {
    MaterialCardView, layout_width = "match", layout_height = "wrap",
    layout_marginLeft = "20dp", layout_marginRight = "20dp", layout_marginTop = "16dp",
    radius = "16dp", CardElevation = 0, strokeWidth = 0,
    CardBackgroundColor = ColorUtil.getColorSurfaceContainer(),
    { LinearLayout, orientation = "vertical", layout_width = "match", layout_height = "wrap",
      minimumHeight = "64dp", padding = "16dp", clickable = true, focusable = true,
      backgroundResource = ripple,
      onClick = function() require("mods.mcp.ServerUi").show() end,
      { MaterialTextView, text = res.string.mcp_title, textSize = "16sp", textColor = ColorUtil.getColorOnSurface() },
      { MaterialTextView, text = res.string.mcp_summary, textSize = "13sp", layout_marginTop = "4dp",
        textColor = ColorUtil.getColorOnSurfaceVariant() },
    },
  })
  built = loadlayout(layout)
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
