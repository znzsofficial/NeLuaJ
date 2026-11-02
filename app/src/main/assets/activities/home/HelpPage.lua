--- 首页「帮助」tab：文档分类入口列表（与帮助页共用目录）。
--- 点击条目经 help 路由直接打开对应文档阅读页。
local _M = {}

local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local RecyclerView = luajava.bindClass("androidx.recyclerview.widget.RecyclerView")
local LinearLayoutManager = luajava.bindClass("androidx.recyclerview.widget.LinearLayoutManager")
local LuaRecyclerAdapter = luajava.bindClass("com.androlua.adapter.LuaRecyclerAdapter")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
local MaterialCardView = luajava.bindClass("com.google.android.material.card.MaterialCardView")

local ActivityUtil = require "mods.utils.ActivityUtil"
local catalog = require "mods.help.DocCatalog"
local Style = require "activities.home.HomeStyle"

local ColorUtil = this.themeUtil
local res = res
local built, adapter
local views = {}

function _M.refresh()
  -- 目录静态，无需动态刷新
end

function _M.dispose()
  -- Fragment view lifetimes are shorter than the Activity/Lua module lifetime.
  built = nil
  adapter = nil
  views = {}
end

function _M.build()
  if built then return built end
  local onSurface, secondary = ColorUtil.getColorOnSurface(), ColorUtil.getColorOnSurfaceVariant()
  built = loadlayout(Style.listPage({ LinearLayout, orientation = "vertical",
    layout_width = "match", layout_height = "wrap", paddingLeft = "20dp", paddingRight = "20dp",
    Style.header(res.string.home_tab_help),
  }, { RecyclerView, id = "docList", layout_width = "match", clipToPadding = false, paddingBottom = "24dp" }), views)
  views.pageHeader.setId(0x00d2f002)
  local data = {}
  for _, section in ipairs(catalog) do
    for index, item in ipairs(section.items) do
      data[#data + 1] = {
        section = { text = section.title, visibility = index == 1 and 0 or 8 },
        title = item.title, description = item.desc,
        docRow = { contentDescription = item.title .. "\n" .. item.desc,
          onClick = function() ActivityUtil.open("help", item.file) end },
      }
    end
  end
  -- Only visible document rows are inflated, including when ViewPager prefetches
  -- this page beside Chats. Do not eagerly create the whole catalog's Views.
  local row = { LinearLayout, orientation = "vertical", layout_width = "match", layout_height = "wrap", layout_marginBottom = "12dp",
    { MaterialTextView, id = "section", textSize = "14sp", textStyle = "bold", textColor = secondary,
      layout_width = "match", layout_height = "wrap", paddingTop = "12dp", paddingBottom = "12dp", visibility = 8 },
    { MaterialCardView, id = "docRow", radius = "16dp", cardElevation = 0, strokeWidth = 0,
      CardBackgroundColor = ColorUtil.getColorSurfaceContainer(), layout_width = "match", layout_height = "wrap",
      minHeight = "72dp", clickable = true, focusable = true,
      { LinearLayout, orientation = "vertical", layout_width = "match", layout_height = "wrap", padding = "16dp",
        { MaterialTextView, id = "title", textSize = "16sp", textStyle = "bold", textColor = onSurface,
          layout_width = "match", layout_height = "wrap", maxLines = 2, ellipsize = "end" },
        { MaterialTextView, id = "description", textSize = "13sp", textColor = secondary,
          layout_width = "match", layout_height = "wrap", maxLines = 2, ellipsize = "end", layout_marginTop = "6dp" },
      },
    },
  }
  adapter = LuaRecyclerAdapter(activity, data, row)
  views.docList.setLayoutManager(LinearLayoutManager(activity))
  views.docList.setAdapter(adapter)
  return built
end

return _M
