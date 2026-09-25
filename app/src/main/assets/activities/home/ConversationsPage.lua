--- 首页「会话」tab：全部工程的 AI 会话聚合列表（按更新时间排序）。
--- 点击经 pending 回传打开对应工程编辑器并定位会话——会话数据在首页只读，
--- 打开动作（切换工程上下文 + 唤起 AI 面板）由编辑器环境执行。
local _M = {}

local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local ScrollView = luajava.bindClass("android.widget.ScrollView")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")

local ConversationStore = require("mods.agent.ConversationStore")
local ConvList = require("mods.agent.ConvList")
local ActivityUtil = require("mods.utils.ActivityUtil")

local ColorUtil = this.themeUtil
local res = res

local background = ColorUtil.getColorBackground()
local onSurface = ColorUtil.getColorOnSurface()

local built = nil
local views = {}

local function normPath(p)
  return tostring(p or ""):gsub("/+$", "")
end

function _M.refresh()
  if not built then return end
  if not views.convList then return end
  local rows = {}
  for _, record in ipairs(ConversationStore.load()) do
    local project = normPath(record.projectPath)
    rows[#rows + 1] = {
      conv = record,
      projectName = project ~= "" and record.projectPath or nil,
    }
  end
  ConvList.renderList(views.convList, rows, function(conv, projectName)
    -- 首页没有工程上下文，所有会话都按跨工程处理：
    -- 打开编辑器并写入 pending，由编辑器 onResume 消费（切换工程 + 打开会话）
    local project = normPath(projectName or "")
    if project == "" then
      project = Bean.Path.app_root_pro_dir
    end
    ActivityUtil.setPending("open_agent_conv_switch", project .. "\n" .. conv.id)
    ActivityUtil.open("editor", project)
  end)
end

function _M.build()
  if built then return built end
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
        text = res.string.home_tab_conversations,
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
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        paddingLeft = "16dp",
        paddingRight = "16dp",
        paddingTop = "4dp",
        paddingBottom = "24dp",
        {
          LinearLayout,
          id = "convList",
          orientation = "vertical",
          layout_width = "match",
          layout_height = "wrap",
        },
      },
    },
  }, views)
  return built
end

return _M
