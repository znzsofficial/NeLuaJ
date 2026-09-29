require "mods.bootstrap"
import "android.view.View"
import "android.view.WindowManager"
import "android.graphics.Color"
this.dynamicColor()

activity.getSupportActionBar().hide()

local path = ...
if not path or path == "" then
    print("PhotoActivity: no image path")
    activity.finish()
    return
end

local ColorUtils = luajava.bindClass("androidx.core.graphics.ColorUtils")

-- 图片铺满系统栏。导航栏透明，露出当前背景色。
local function applyPhotoBars(color)
    local window = activity.getWindow()
    window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
    window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION)
    window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
    window.addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS)
    window.setStatusBarColor(Color.TRANSPARENT)
    window.setNavigationBarColor(Color.TRANSPARENT)
    pcall(function() window.setNavigationBarContrastEnforced(false) end)
    local flags = View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
    if ColorUtils.calculateLuminance(color) > 0.5 then
        flags = flags | View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
    end
    window.getDecorView().setSystemUiVisibility(flags)
end

pcall(function() applyPhotoBars(0xff000000) end)

local binding = {}
activity.setContentView(loadlayout(res.layout.photo_layout, binding))

-- 直接用 res.drawable 获取着色图标，无需 Coil 异步加载
local iconColor = this.themeUtil.getColorOnPrimaryContainer()
binding.switchBg.setImageDrawable(res.drawable("sync", iconColor))

-- 加载图片（Coil 支持 file path / uri / url）
this.loadImageWithCrossFade(path, binding.mPhotoView)

-- 背景色循环切换
local bgColors = {
    0xff888888,
    0xff363636,
    0xffcccccc,
    0xffffffff,
    0xff000000,
}
local bgIndex = 1

binding.switchBg.onClick = function()
    local color = bgColors[bgIndex]
    binding.bg.setBackgroundColor(color)
    pcall(function() applyPhotoBars(color) end)
    bgIndex = bgIndex % #bgColors + 1
end
