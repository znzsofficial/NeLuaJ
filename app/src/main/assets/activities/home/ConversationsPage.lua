--- 首页「会话」tab：全部工程的 AI 会话聚合列表（按更新时间排序）。
--- 点击经 pending 回传打开对应工程编辑器并定位会话。
--- 长按可直接删除。每次刷新都重新读盘，编辑器里的删除返回后能看见。
local _M = {}

local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local ScrollView = luajava.bindClass("android.widget.ScrollView")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")

local ConversationStore = require("mods.agent.ConversationStore")
local ConvList = require("mods.agent.ConvList")
local ActivityUtil = require("mods.utils.ActivityUtil")
local MaterialAlertDialogBuilder = luajava.bindClass("com.google.android.material.dialog.MaterialAlertDialogBuilder")
local Toast = luajava.bindClass("android.widget.Toast")

local ColorUtil = this.themeUtil
local res = res

-- 主题色在 build() 时解析（理由同 ProjectsPage）
local background, onSurface

local built = nil
local views = {}

local function normPath(p)
  return tostring(p or ""):gsub("/+$", "")
end

local function convName(conv)
  local name = tostring(conv.name or "")
  if name == "" then name = res.string.ai_unnamed_conv end
  return name
end

local function openConversation(conv, projectName)
  -- 首页没有工程上下文，所有会话都按跨工程处理：
  -- 打开编辑器并写入 pending，由编辑器 onResume 消费（切换工程 + 打开会话）
  local project = normPath(projectName or "")
  if project == "" then
    project = Bean.Path.app_root_pro_dir
  end
  ActivityUtil.setPending("open_agent_conv_switch", project .. "\n" .. conv.id)
  ActivityUtil.open("editor", project)
end

local function confirmDelete(conv)
  MaterialAlertDialogBuilder(activity)
    .setTitle(res.string.ai_delete_conv)
    .setMessage(res.string.ai_confirm_delete_conv:format(convName(conv)))
    .setPositiveButton(res.string.ai_delete, function()
      local ok = ConversationStore.delete(conv.id, conv.projectPath)
      if not ok then
        Toast.makeText(activity, res.string.ai_delete_failed, 0).show()
        return
      end
      Toast.makeText(activity, res.string.ai_deleted, 0).show()
      _M.refresh()
    end)
    .setNegativeButton(android.R.string.cancel, nil)
    .show()
end

local function showConversationMenu(conv, projectName)
  MaterialAlertDialogBuilder(activity)
    .setTitle(convName(conv))
    .setItems({ res.string.open, res.string.ai_delete }, function(_, which)
      which = tonumber(tostring(which)) or -1
      if which == 0 then
        openConversation(conv, projectName)
      elseif which == 1 then
        confirmDelete(conv)
      end
    end)
    .setNegativeButton(android.R.string.cancel, nil)
    .show()
end

function _M.refresh()
  if not built then return end
  if not views.convList then return end
  local rows = {}
  -- 编辑器和首页不是同一个 Lua 状态。每次刷新都重新读盘，否则删过的会话还会留在缓存里。
  for _, record in ipairs(ConversationStore.loadIndex(true)) do
    local project = normPath(record.projectPath)
    rows[#rows + 1] = {
      conv = record,
      projectName = project ~= "" and record.projectPath or nil,
    }
  end
  ConvList.renderList(views.convList, rows, openConversation, showConversationMenu)
end

function _M.build()
  if built then return built end
  background = ColorUtil.getColorSurface()
  onSurface = ColorUtil.getColorOnSurface()
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
  -- 片段视图创建即自刷：与 ProjectsPage 同理，保证数据首次出现与视图同步
  _M.refresh()
  return built
end

return _M
