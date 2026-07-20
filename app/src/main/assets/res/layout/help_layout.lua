require "environment"
import "android.widget.LinearLayout"
import "android.widget.ScrollView"
import "android.widget.FrameLayout"
import "androidx.viewpager2.widget.ViewPager2"
import "androidx.appcompat.widget.AppCompatEditText"
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.card.MaterialCardView"
import "com.androlua.LuaWebView"

local LuaFragmentAdapter = luajava.bindClass "github.znzsofficial.adapter.LuaFragmentAdapter"
local LuaFragment = luajava.bindClass "com.androlua.LuaFragment"
local ColorUtil = this.themeUtil

local surfaceColor = ColorUtil.getColorSurface()
local surfaceContainer = ColorUtil.getColorSurfaceContainer()
local surfaceContainerLow = surfaceContainer
local surfaceVariant = ColorUtil.getColorSurfaceVariant()
local onSurface = ColorUtil.getColorOnSurface()
local onSurfaceVar = ColorUtil.getColorOnSurfaceVariant()
local primary = ColorUtil.getColorPrimary()
local primaryContainer = ColorUtil.getColorPrimaryContainer()
local onPrimaryContainer = ColorUtil.getColorOnPrimaryContainer()
local outline = ColorUtil.getColorOutlineVariant()
local background = ColorUtil.getColorBackground()
local rippleRes = activity.obtainStyledAttributes({ android.R.attr.selectableItemBackground }).getResourceId(0, 0)

pcall(function()
  surfaceContainerLow = ColorUtil.getColorSurfaceContainerLow()
end)

local view = loadlayout {
  LinearLayout,
  layout_width = "match",
  layout_height = "match",
  orientation = "vertical",
  backgroundColor = background,
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
  LinearLayout,
  orientation = "vertical",
  layout_width = "match",
  layout_height = "match",
  backgroundColor = background,
  {
    -- 固定搜索区，不随列表滚走
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    paddingLeft = "16dp",
    paddingRight = "16dp",
    paddingTop = "8dp",
    paddingBottom = "4dp",
    id = "docHeader",
  },
  {
    ScrollView,
    layout_width = "match",
    layout_height = "match",
    layout_weight = 1,
    fillViewport = true,
    backgroundColor = background,
    overScrollMode = 2,
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      paddingLeft = "16dp",
      paddingRight = "16dp",
      paddingTop = "4dp",
      paddingBottom = "40dp",
      id = "docHome",
    },
  },
}

local webPage = loadlayout {
  FrameLayout,
  layout_width = "match",
  layout_height = "match",
  backgroundColor = surfaceColor,
  {
    LuaWebView,
    id = "webView",
    layout_width = "match",
    layout_height = "match",
    backgroundColor = surfaceColor,
  },
  {
    LinearLayout,
    id = "webLoading",
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
    gravity = "center",
    backgroundColor = surfaceColor,
    visibility = 8,
    clickable = true,
    {
      MaterialTextView,
      text = "加载中…",
      textSize = "14sp",
      textColor = onSurfaceVar,
    },
  },
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

_G.__helpUi = {
  background = background,
  surfaceColor = surfaceColor,
  surfaceContainer = surfaceContainer,
  surfaceContainerLow = surfaceContainerLow,
  surfaceVariant = surfaceVariant,
  onSurface = onSurface,
  onSurfaceVar = onSurfaceVar,
  primary = primary,
  primaryContainer = primaryContainer,
  onPrimaryContainer = onPrimaryContainer,
  outline = outline,
  rippleRes = rippleRes,
}

return view
