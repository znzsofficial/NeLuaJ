--- Native Material navigation: bottom bar below 600dp actual window width, rail above.
--- HomePageFragment restores page identity from arguments, never a retained Lua creator.
require "mods.bootstrap"
local HomeShellView = luajava.bindClass "com.nekolaska.home.HomeShellView"
local ColorUtil = this.themeUtil
local res = res

local tabMeta = {
  { key = "projects", title = res.string.home_tab_projects, icon = "folder" },
  { key = "conversations", title = res.string.home_tab_conversations, icon = "ic_comment" },
  { key = "help", title = res.string.home_tab_help, icon = "ic_help" },
  { key = "settings", title = res.string.home_tab_settings, icon = "ic_settings" },
}

local view = HomeShellView(activity)
view.setBackgroundColor(ColorUtil.getColorSurface())
view.getBottomNav().setBackgroundColor(ColorUtil.getColorSurfaceContainer())
view.getRail().setBackgroundColor(ColorUtil.getColorSurfaceContainer())
for _, meta in ipairs(tabMeta) do
  view.addDestination(meta.key, meta.title, res.drawable(meta.icon))
end

-- Publish before attaching fragments: restored fragments bind through the current Lua host.
_G.__homeUi = {
  root = view,
  pager = view.getPager(),
  bottomNav = view.getBottomNav(),
  rail = view.getRail(),
  selectPage = function(key) view.selectPage(key) end,
  selectTab = function(index) view.selectTab(index) end,
  refreshVisiblePage = function() view.requestVisibleRefresh() end,
  requestStoragePermission = function() this.requestStoragePermission() end,
  pageContentReady = function(key) view.pageContentReady(key) end,
}
view.bindPages()

return view
