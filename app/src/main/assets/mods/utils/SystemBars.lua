--- 状态栏跟顶栏，导航栏跟页面最底部的颜色。浅色时用深色图标。
local View = bindClass "android.view.View"
local WindowManager = bindClass "android.view.WindowManager"
local _M = {}

function _M.apply(window, statusColor, navColor)
  if not window or statusColor == nil then return end
  navColor = navColor or statusColor
  window.setStatusBarColor(statusColor)
  window.setNavigationBarColor(navColor)
  window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
  window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
  pcall(function()
    window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION)
  end)
  -- 关掉系统对比度蒙层，否则浅色导航栏会被刮上一层灰，对不上底部界面。
  pcall(function()
    window.setNavigationBarContrastEnforced(false)
  end)
  local flags = 0
  if not this.isNightMode() then
    flags = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
    if View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR then
      flags = flags + View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
    end
  end
  window.getDecorView().setSystemUiVisibility(flags)
end

return _M
