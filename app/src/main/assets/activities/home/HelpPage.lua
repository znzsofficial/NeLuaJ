--- 首页「帮助」tab：文档分类入口列表（与帮助页共用目录）。
--- 点击条目经 help 路由直接打开对应文档阅读页。
local _M = {}

local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local ScrollView = luajava.bindClass("android.widget.ScrollView")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
local MaterialCardView = luajava.bindClass("com.google.android.material.card.MaterialCardView")

local ActivityUtil = require "mods.utils.ActivityUtil"
local catalog = require "mods.help.DocCatalog"

local ColorUtil = this.themeUtil
local res = res
local dp = function(n) return this.dpToPx(n) end

-- 主题色在 build() 时解析（理由同 ProjectsPage）
local background, onSurface, onSurfaceVar, primary, surfaceCard

local built = nil
local views = {}

local function buildDocRow(item)
  local row = loadlayout({
    MaterialCardView,
    radius = "14dp",
    CardElevation = 0,
    CardBackgroundColor = surfaceCard,
    layout_width = "match",
    layout_height = "wrap",
    clickable = true,
    focusable = true,
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      padding = "14dp",
      {
        MaterialTextView,
        text = item.title,
        textSize = "15sp",
        textStyle = "bold",
        textColor = onSurface,
        singleLine = true,
        ellipsize = "end",
      },
      {
        MaterialTextView,
        text = item.desc,
        textSize = "12sp",
        textColor = onSurfaceVar,
        maxLines = 1,
        ellipsize = "end",
        layout_marginTop = "2dp",
      },
    },
  })
  row.onClick = function()
    ActivityUtil.open("help", item.file)
  end
  return row
end

local function buildSection(section)
  local block = loadlayout({
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    {
      MaterialTextView,
      text = section.title,
      textSize = "13sp",
      textStyle = "bold",
      textColor = primary,
      paddingBottom = "8dp",
      paddingTop = "8dp",
    },
  })
  local container = block
  for _, item in ipairs(section.items) do
    local lp = LinearLayout.LayoutParams(-1, -2)
    lp.topMargin = dp(4)
    container.addView(buildDocRow(item), lp)
  end
  return block
end

function _M.refresh()
  -- 目录静态，无需动态刷新
end

function _M.build()
  if built then return built end
  background = ColorUtil.getColorSurface()
  onSurface = ColorUtil.getColorOnSurface()
  onSurfaceVar = ColorUtil.getColorOnSurfaceVariant()
  primary = ColorUtil.getColorPrimary()
  surfaceCard = ColorUtil.getColorSurfaceContainer()
  built = loadlayout({
    LinearLayout,
    layout_width = "match",
    layout_height = "match",
    orientation = "vertical",
    backgroundColor = background,
    {
      -- 顶栏
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      paddingLeft = "16dp",
      paddingRight = "16dp",
      paddingTop = "12dp",
      paddingBottom = "4dp",
      {
        MaterialTextView,
        text = res.string.home_tab_help,
        textSize = "22sp",
        textStyle = "bold",
        textColor = onSurface,
      },
    },
    {
      ScrollView,
      layout_width = "match",
      layout_height = "match",
      fillViewport = true,
      overScrollMode = 2,
      {
        LinearLayout,
        id = "docList",
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        paddingLeft = "16dp",
        paddingRight = "16dp",
        paddingBottom = "24dp",
      },
    },
  }, views)

  -- 分区块作为独立加载的根视图，间距经显式 LayoutParams 传入
  local list = views.docList
  for index, section in ipairs(catalog) do
    local lp = LinearLayout.LayoutParams(-1, -2)
    lp.topMargin = dp(index > 1 and 12 or 0)
    list.addView(buildSection(section), lp)
  end
  return built
end

return _M
