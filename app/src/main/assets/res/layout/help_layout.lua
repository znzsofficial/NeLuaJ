require "environment"
import "android.widget.LinearLayout"
import "android.widget.ScrollView"
import "androidx.viewpager2.widget.ViewPager2"
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.card.MaterialCardView"
import "com.androlua.LuaWebView"

local LuaFragmentAdapter = luajava.bindClass "github.znzsofficial.adapter.LuaFragmentAdapter"
local LuaFragment = luajava.bindClass "com.androlua.LuaFragment"
local ColorUtil = this.themeUtil

local surfaceColor = ColorUtil.getColorSurface()
local surfaceContainer = ColorUtil.getColorSurfaceContainer()
local onSurface = ColorUtil.getColorOnSurface()
local onSurfaceVar = ColorUtil.getColorOnSurfaceVariant()
local primary = ColorUtil.getColorPrimary()
local primaryContainer = ColorUtil.getColorPrimaryContainer()
local onPrimaryContainer = ColorUtil.getColorOnPrimaryContainer()
local outline = ColorUtil.getColorOutlineVariant()
local rippleRes = activity.obtainStyledAttributes({ android.R.attr.selectableItemBackground }).getResourceId(0, 0)

local view = loadlayout {
  LinearLayout,
  layout_width = "match",
  layout_height = "match",
  orientation = "vertical",
  backgroundColor = surfaceColor,
  {
    ViewPager2,
    layout_width = "match",
    layout_height = "match",
    id = "vpg",
    UserInputEnabled = false,
    OffscreenPageLimit = 1,
  },
}

local homePage = loadlayout {
  ScrollView,
  layout_width = "match",
  layout_height = "match",
  fillViewport = true,
  backgroundColor = surfaceColor,
  {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    paddingLeft = "16dp",
    paddingRight = "16dp",
    paddingTop = "12dp",
    paddingBottom = "28dp",
    id = "docHome",
  },
}

local webPage = loadlayout {
  LuaWebView,
  id = "webView",
  layout_width = "match",
  layout_height = "match",
  backgroundColor = surfaceColor,
}

local fragments = {
  LuaFragment(LuaFragment.Creator {
    onCreateView = function()
      return homePage
    end
  }),
  LuaFragment(LuaFragment.Creator {
    onCreateView = function()
      return webPage
    end
  }),
}

vpg.setAdapter(LuaFragmentAdapter(activity, LuaFragmentAdapter.Creator {
  createFragment = function(i)
    return fragments[i + 1]
  end,
  getItemCount = function()
    return #fragments
  end,
}))

-- export helpers for HelpActivity
_G.__helpUi = {
  surfaceColor = surfaceColor,
  surfaceContainer = surfaceContainer,
  onSurface = onSurface,
  onSurfaceVar = onSurfaceVar,
  primary = primary,
  primaryContainer = primaryContainer,
  onPrimaryContainer = onPrimaryContainer,
  outline = outline,
  rippleRes = rippleRes,
}

return view
