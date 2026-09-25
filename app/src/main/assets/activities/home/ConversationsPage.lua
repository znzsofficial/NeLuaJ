--- 首页「会话」tab：跨工程 AI 会话列表（复用 AgentCenter 的渲染逻辑）。
--- Commit 1 为占位实现。
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
      text = res.string.home_tab_conversations,
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
