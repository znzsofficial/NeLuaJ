--- 首页「设置」tab：复用 SettingsPage 共享内容 + 底部拓展版「关于」。
--- Commit 1 为占位实现；SettingActivity 的页面共享化由后续提交完成。
local _M = {}

local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
local ColorUtil = this.themeUtil
local res = res

local built = nil

function _M.build()
  if built then return built end
  built = loadlayout({
    LinearLayout,
    layout_width = "match",
    layout_height = "match",
    orientation = "vertical",
    gravity = "center",
    {
      MaterialTextView,
      text = res.string.home_tab_settings,
      textSize = "18sp",
      textStyle = "bold",
      textColor = ColorUtil.getColorOnSurface(),
    },
  })
  return built
end

function _M.refresh()
end

return _M
