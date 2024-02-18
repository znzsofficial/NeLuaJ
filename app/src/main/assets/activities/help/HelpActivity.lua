require "environment"
import "com.androlua.adapter.LuaAdapter"
import "android.view.KeyEvent"
import "android.view.WindowManager"
import "android.view.View"
import "android.graphics.drawable.ColorDrawable"
import "com.youbenzi.mdtool.tool.MDTool"
import "mods.utils.LuaFileUtil"
import "mods.utils.UiUtil"
local ColorUtil = this.globalData.ColorUtil
local:res
activity.setTitle("NeLuaJ+"..res.string.help)
.setContentView(res.layout.help_layout)
.getSupportActionBar()
.setElevation(0)
.setBackgroundDrawable(ColorDrawable(ColorUtil.getColorBackground()))
.setDisplayShowHomeEnabled(true)
.setDisplayHomeAsUpEnabled(true)

local window = activity.getWindow()
.setNavigationBarColor(0)
.setStatusBarColor(ColorUtil.getColorBackground())
.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
if UiUtil.isNightMode()
  window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_VISIBLE)
 else
  window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR)
end

function onOptionsItemSelected(m)
  switch m.getItemId() do
   case android.R.id.home
    activity.finish()
  end
end

luajava.newInstance("me.zhanghai.android.fastscroll.FastScrollerBuilder", webView).useMd2Style().build()

local MaterialTextView = luajava.bindClass "com.google.android.material.textview.MaterialTextView"
local LinearLayout = luajava.bindClass "android.widget.LinearLayout"
local item={
  LinearLayout,
  layout_height="-2",
  layout_width="-1",
  paddingLeft="16dp",
  paddingRight="16dp",
  paddingTop="12dp",
  paddingBottom="12dp",
  {
    MaterialTextView,
    id="text",
    layout_height="-2",
    layout_width="-1",
    textColor=ColorUtil.getColorPrimary(),
    textSize="16dp",
  },
}

local data={
  {text="NeLuaJ+",file="overview.md"},
  {text="LuaJ++",file="LuaJ++.md"},
  {text="LuaActivity",file="LuaActivity.md"},
  {text="LuaCustRecyclerAdapter",file="LuaCustRecyclerAdapter.md"},
  {text="LuaFragmentAdapter",file="LuaFragmentAdapter.md"},
  {text="xTask",file="xTask.md"},
  {text="res",file="module_res.md"},
}

local adp=LuaAdapter(activity,data,item)
lv.setAdapter(adp)

lv.onItemClick=function(l,v,p,i)
  activity.setTitle(data[i].text)
  vpg.setCurrentItem(1)
  local md=LuaFileUtil.read(activity.getLuaDir().."/res/doc/"..data[i].file)
  webView.loadDataWithBaseURL("",MDTool.markdown2Html(md),"text/html","utf-8",nil)
end

if bindClass "android.os.Build".VERSION.SDK_INT >= 33 then
activity.onBackPressedDispatcher.addCallback(this,luajava.bindClass "androidx.activity.OnBackPressedCallback".override{
handleOnBackPressed=function()
    if vpg.getCurrentItem()~=0 then
        vpg.setCurrentItem(0)
        activity.setTitle("NeLuaJ+"..res.string.help)
    else
        activity.finish()
    end
end
}(true))
else
function onKeyDown(code,event)
    if code==KeyEvent.KEYCODE_BACK then
        if vpg.getCurrentItem()~=0 then
           vpg.setCurrentItem(0)
           activity.setTitle("NeLuaJ+"..res.string.help)
           return true
        end
    end
end
end
