--- 首页「项目」tab：最近项目卡片行 + 完整项目列表（按修改时间排序）。
--- Commit 1 为占位实现，数据加载由后续提交填充。
local _M = {}

local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
local ColorUtil = this.themeUtil
local res = res

local built = nil

function _M.build()
  if built then return built end
  built = loadlayout({
    LinearLayout,
    layout_width = "match",
    layout_height = "match",
    orientation = "vertical",
    gravity = "center",
    {
      MaterialTextView,
      text = res.string.home_tab_projects,
      textSize = "18sp",
      textStyle = "bold",
      textColor = ColorUtil.getColorOnSurface(),
    },
  })
  return built
end

function _M.refresh()
end

return _M
