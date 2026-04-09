require "environment"
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

-- 全屏沉浸
pcall(function()
    local window = activity.getWindow()
    window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
    window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
    window.setStatusBarColor(Color.TRANSPARENT)
    window.addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS)
    window.getDecorView().setSystemUiVisibility(
        View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
        | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        | View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
    )
end)

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
    binding.bg.setBackgroundColor(bgColors[bgIndex])
    bgIndex = bgIndex % #bgColors + 1
end
