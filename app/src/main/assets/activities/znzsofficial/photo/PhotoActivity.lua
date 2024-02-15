require "environment"
import "android.view.View"
import "android.view.WindowManager"
import "android.graphics.Color"
import "com.bumptech.glide.Glide"

activity.getSupportActionBar().hide()

local path = ...

try
  local window = activity.getWindow()
  window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS);
  window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
  | View.SYSTEM_UI_FLAG_LAYOUT_STABLE |View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR);
  window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
  window.setStatusBarColor(Color.TRANSPARENT);
  window.addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS);
end

local binding = {}
activity.setContentView(loadlayout(res.layout.photo_layout,binding))

Glide.with(activity)
.load(DrawableUtil.getDrawable("sync", this.globalData.ColorUtil.getColorOnPrimaryContainer()))
.into(binding.switchBg)
Glide.with(activity)
.load(path)
.into(binding.mPhotoView)

local i = 1
local colors = {
  0xff888888,
  0xff363636,
  0xffcccccc,
  0xffffffff,
  0xff000000,
}

binding.switchBg.onClick = function()
  binding.bg.setBackgroundColor(colors[i])
  i = i % #colors + 1
end
