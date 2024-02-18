require "environment"
import "android.view.View"
import "android.view.WindowManager"
import "android.graphics.Color"
import "coil.Coil"
import "coil.request.ImageRequest"

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

local imageLoader = Coil.imageLoader(activity)

imageLoader.enqueue(
ImageRequest.Builder(this)
.data(DrawableUtil.getDrawable("sync", this.globalData.ColorUtil.getColorOnPrimaryContainer()))
.target(binding.switchBg).build()
)

imageLoader.enqueue(
ImageRequest.Builder(this)
.data(path)
.target(binding.mPhotoView).build()
)

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
