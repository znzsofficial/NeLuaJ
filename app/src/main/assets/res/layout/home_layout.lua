--- 首页布局：ViewPager2（Fragment 承载四个 tab 页）+ BottomNavigationView。
--- 切换方式与帮助页一致：禁用左右滑动，由底栏点按驱动 pager 动画切换；
--- 底栏选中态由组件自身维护，无需页回调桥（OnPageChangeCallback 为抽象类，
--- 表式监听器无法生成）。
require "mods.bootstrap"
import "android.widget.LinearLayout"
import "androidx.viewpager2.widget.ViewPager2"
import "com.google.android.material.bottomnavigation.BottomNavigationView"
import "com.androlua.LuaFragment"
local LuaFragmentAdapter = luajava.bindClass "github.znzsofficial.adapter.LuaFragmentAdapter"
local ColorUtil = this.themeUtil
local res = res

-- 页面模块：require 缓存保证 HomeActivity 拿到的是同一实例
local ProjectsPage = require "activities.home.ProjectsPage"
local ConversationsPage = require "activities.home.ConversationsPage"
local HelpPage = require "activities.home.HelpPage"
local SettingsPage = require "activities.home.SettingsPage"

local pages = { ProjectsPage, ConversationsPage, HelpPage, SettingsPage }

local tabMeta = {
  { title = res.string.home_tab_projects, icon = "folder" },
  { title = res.string.home_tab_conversations, icon = "ic_comment" },
  { title = res.string.home_tab_help, icon = "ic_help" },
  { title = res.string.home_tab_settings, icon = "ic_settings" },
}

local background = ColorUtil.getColorBackground()

local shellViews = {}
local view = loadlayout({
  LinearLayout,
  layout_width = "match",
  layout_height = "match",
  orientation = "vertical",
  backgroundColor = background,
  {
    ViewPager2,
    id = "homePager",
    layout_width = "match",
    layout_height = "0dp",
    layout_weight = 1,
    UserInputEnabled = false,
    OffscreenPageLimit = 1,
  },
  {
    BottomNavigationView,
    id = "homeNav",
    layout_width = "match",
    layout_height = "wrap",
  },
}, shellViews)

local pager = shellViews.homePager
local bottomNav = shellViews.homeNav

local menu = bottomNav.getMenu()
for index, meta in ipairs(tabMeta) do
  local item = menu.add(0, index, index - 1, meta.title)
  pcall(function()
    item.setIcon(res.drawable(meta.icon))
  end)
end
pcall(function()
  -- 四个 tab 固定显示全部标签，避免小屏只显示选中项
  bottomNav.setLabelVisibilityMode(1)
end)

local fragments = {}
for index, page in ipairs(pages) do
  fragments[index] = LuaFragment(LuaFragment.Creator {
    onCreateView = function()
      return page.build()
    end,
  })
end

pager.setAdapter(LuaFragmentAdapter(activity, LuaFragmentAdapter.Creator {
  createFragment = function(i)
    return fragments[i + 1]
  end,
  getItemCount = function()
    return #fragments
  end,
}))

bottomNav.setOnItemSelectedListener({
  onNavigationItemSelected = function(item)
    pager.setCurrentItem(item.getItemId() - 1, true)
    return true
  end,
})

return view
