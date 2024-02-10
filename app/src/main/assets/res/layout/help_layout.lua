import "android.widget.LinearLayout"
import "android.widget.ListView"
import "androidx.viewpager2.widget.ViewPager2"
import "me.zhanghai.android.fastscroll.FastScrollWebView"
local LuaFragmentAdapter = luajava.bindClass "github.znzsofficial.adapter.LuaFragmentAdapter"
local LuaFragment = luajava.bindClass "com.androlua.LuaFragment"
require "environment"
local:loadlayout
local ColorUtil = this.globalData.ColorUtil

local view = loadlayout {
  LinearLayout,
  layout_width="-1",
  layout_height="-1",
  orientation="vertical",
  {
    ViewPager2,
    layout_width="-1",
    layout_height="-1",
    id="vpg",
    UserInputEnabled=false,
  },
}

local pages={
  -----
  loadlayout{
    ListView,
    id="lv",
    layout_width="-1",
    layout_height="-1",
    DividerHeight=1,
    backgroundColor=ColorUtil.getColorSurfaceVariant(),
  },
  -----
  loadlayout
  {
    FastScrollWebView,
    id="webView",
    layout_width="match",
    layout_height="match",
    backgroundColor=ColorUtil.getColorSurfaceVariant(),
  },
  -----
}

local list = {LuaFragment(pages[1]),LuaFragment(pages[2])}
local adapter = LuaFragmentAdapter(activity, LuaFragmentAdapter.Creator{
  createFragment = function(i)
    return list[i+1]
  end,
  getItemCount = function()
    return #list
  end,
})

vpg.setAdapter(adapter)

return view