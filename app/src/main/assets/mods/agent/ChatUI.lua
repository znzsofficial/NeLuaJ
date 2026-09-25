--- AI 聊天 UI 管理 — 支持工具调用（创建/删除文件需用户确认）
local _M = {}

local BottomSheetDialog = luajava.bindClass("com.google.android.material.bottomsheet.BottomSheetDialog")
local BottomSheetBehavior = luajava.bindClass("com.google.android.material.bottomsheet.BottomSheetBehavior")
local MaterialAlertDialogBuilder = luajava.bindClass("com.google.android.material.dialog.MaterialAlertDialogBuilder")
local ColorStateList = luajava.bindClass("android.content.res.ColorStateList")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
local MaterialButton = luajava.bindClass("com.google.android.material.button.MaterialButton")
local MaterialCardView = luajava.bindClass("com.google.android.material.card.MaterialCardView")
local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local EditText = luajava.bindClass("android.widget.EditText")
local ScrollView = luajava.bindClass("android.widget.ScrollView")
local HorizontalScrollView = luajava.bindClass("android.widget.HorizontalScrollView")
local Switch = luajava.bindClass("com.google.android.material.materialswitch.MaterialSwitch")
local HtmlCompat = luajava.bindClass("androidx.core.text.HtmlCompat")
local LinkMovementMethod = luajava.bindClass("android.text.method.LinkMovementMethod")
local Typeface = luajava.bindClass("android.graphics.Typeface")
local WindowManager = luajava.bindClass("android.view.WindowManager")
local DialogInterface = luajava.bindClass("android.content.DialogInterface")

import "androidx.core.graphics.ColorUtils"

local AgentChat = require("mods.agent.AgentChat")
local AgentTurn = require("mods.agent.AgentTurn")
local MCPClient = require("mods.agent.MCPClient")
local TodoManager = require("mods.agent.TodoManager")
local ActivityUtil = require("mods.utils.ActivityUtil")
import "mods.utils.EditorUtil"
local ColorUtil = this.themeUtil
local ColorPrimary = ColorUtil.primary.main
local ColorOnPrimary = ColorUtil.primary.on
local ColorPrimaryContainer = ColorUtil.primary.container
local ColorOnPrimaryContainer = ColorUtil.primary.onContainer
local ColorSecondaryContainer = ColorUtil.secondary.container
local ColorOnSecondaryContainer = ColorUtil.secondary.onContainer
local ColorSurface = ColorUtil.surface.container
local ColorSurfaceContainerLow = ColorUtil.surface.containerLow
local ColorSurfaceContainerHigh = ColorUtil.surface.containerHigh
local ColorOnSurface = ColorUtil.surface.on
local ColorText = ColorUtil.surface.onVariant
local ColorOutline = ColorUtil.outline.variant
local ColorError = ColorUtil.error.main
local ColorErrorContainer = ColorUtil.error.container
local ColorOnErrorContainer = ColorUtil.error.onContainer
local ColorRipple = ColorUtils.blendARGB(ColorPrimary, 0x00ffffff, 0.4)
local ColorCodeBg = ColorUtils.blendARGB(ColorSurfaceContainerLow, 0xff000000, 0.08)
local S = res.string
local GradientDrawable = luajava.bindClass("android.graphics.drawable.GradientDrawable")
local function dp(n) return this.dpToPx(n) end

local VISIBLE = 0
local GONE = 8

local messages = {}
local dialog = nil
local views = {}
local activeToolConfirm = nil
local editingMessageIndex = nil
local undoTurns = {}
local redoTurns = {}
local activeConversationId = nil
local conversationLoaded = false
local activeConversationProjectPath = nil
local activeConversationHadMessages = false
-- 会话累计用量（主请求次数与估算输入 token），随会话记录持久化
local convUsage = { requests = 0, tokens = 0 }
local titleInFlight = false

-- 回合状态（loading/generation/stopRequested/activeStream/failedToolCalls/
-- retryPayloads/activeToolStop）已迁至 AgentTurn；此处仅保留会话与视图状态。

-- 前向声明
local saveHistory, loadHistory, showModelManager, showModelPicker, showConvManager, showConvList, showSettings, addMessageBubble, addToolBubble, updateProjectLabel, sendMessage, addRequestErrorBubble

-- 任务计划随会话记录的 todos 字段持久化：saveHistory 每次落盘都镜像
-- TodoManager 的当前状态，因此工具更新只需在主线程 commit 状态即可。
-- 状态注入与重置分别由 loadHistory / 各会话切换路径负责。

local function convName(conv)
  local n = conv and conv.name or ""
  if n == "" then return S.ai_unnamed_conv end
  return n
end

-- ─── UI 辅助 ──

local function isPanelVisible()
  return dialog and dialog.isShowing()
end

local function updateModelLabel()
  if not views.modelLabel then return end
  local name = AgentChat.getCurrentModelName()
  views.modelLabel.setText(name ~= "" and name or S.ai_add_model)
end

local function isToolError(toolName, result)
  if not result then return false end
  local r = tostring(result):lower()
  if toolName == "read_file" or toolName == "read_files"
      or toolName == "list_dir" or toolName == "search_in_files" then
    return result:find("读取文件失败", 1, true)
      or result:find("读取目录失败", 1, true)
      or result:find("搜索失败", 1, true)
      or result:find("文件不存在", 1, true)
      or result:find("目录不存在", 1, true)
      or result:find("offset 超出", 1, true)
      or result:find("工具参数 JSON 无效", 1, true)
      or r:match("^error[:：]") ~= nil
      or r:match("^exception[:：]") ~= nil
  end
  return result:find("读取文件失败", 1, true)
    or result:find("读取目录失败", 1, true)
    or result:find("搜索失败", 1, true)
    or result:find("失败", 1, true)
    or result:find("异常", 1, true)
    or result:find("语法错误", 1, true)
    or result:find("找不到", 1, true)
    or result:find("未找到", 1, true)
    or result:find("无法识别", 1, true)
    or result:find("offset 超出", 1, true)
    or r:find("error", 1, true)
    or r:find("exception", 1, true)
    or r:find("not found", 1, true)
end

local function toolDisplayName(name)
  local labels = {
    create_file = S.ai_create_file,
    create_folder = S.ai_create_folder,
    delete_file = S.ai_delete_file,
    delete_folder = S.ai_delete_folder,
    apply_patch = S.ai_apply_patch,
    replace_in_file = S.ai_replace_text,
    run_lua = S.ai_run_code,
    append_file = S.ai_append_file,
    rename_file = S.ai_rename_file,
    read_file = S.ai_tool_read_file,
    read_files = S.ai_tool_read_files,
    list_dir = S.ai_tool_list_dir,
    search_in_files = S.ai_tool_search,
    get_env_info = S.ai_tool_env,
    check_lua_syntax = S.ai_tool_check_syntax,
    fetch_url = S.ai_tool_fetch_url,
    run_project = S.run_project,
    build_project = S.build_project,
    update_todos = S.ai_tool_todo,
  }
  return labels[name] or tostring(name or "")
end

local function scrollDown()
  if views.msgScroll then
    views.msgScroll.post(function()
      views.msgScroll.fullScroll(130)
    end)
  end
end

local function showAgentHelp()
  ActivityUtil.open("help", "agent")
end

-- ─── Markdown 渲染辅助 ──

local function escapeHtml(text)
  text = text:gsub("&", "&amp;")
  text = text:gsub("<", "&lt;")
  text = text:gsub(">", "&gt;")
  return text
end

--- 把文本段渲染为 Spanned，支持标题、列表、粗体、斜体和行内代码。
local function renderMarkdown(text)
  local function inline(source)
    local html = escapeHtml(source)
    local codeSpans = {}
    html = html:gsub("`([^`]+)`", function(code)
      local token = "\001CODE" .. tostring(#codeSpans + 1) .. "\002"
      codeSpans[#codeSpans + 1] = "<font face='monospace'>" .. code .. "</font>"
      return token
    end)
    local links = {}
    html = html:gsub("%[([^%]]+)%]%((https?://[^%)%s]+)%)", function(label, url)
      local token = "\001LINK" .. tostring(#links + 1) .. "\002"
      links[#links + 1] = "<a href='" .. url:gsub("'", "&#39;") .. "'>" .. label .. "</a>"
      return token
    end)
    html = html:gsub("%*%*(.-)%*%*", "<b>%1</b>")
    html = html:gsub("__([^_]+)__", "<b>%1</b>")
    html = html:gsub("%*([^*]-)%*", "<i>%1</i>")
    html = html:gsub("_([^_]-)_", "<i>%1</i>")
    html = html:gsub("\001LINK(%d+)\002", function(index) return links[tonumber(index)] end)
    html = html:gsub("\001CODE(%d+)\002", function(index) return codeSpans[tonumber(index)] end)
    return html
  end

  text = tostring(text or ""):gsub("\r\n", "\n")
  local html = {}
  local inList = nil
  local function closeList()
    if inList then html[#html + 1] = "</" .. inList .. ">"; inList = nil end
  end
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local headingLevel, heading = line:match("^%s*(#+)%s+(.+)$")
    local bullet = line:match("^%s*[-*+]%s+(.+)$")
    local ordered = line:match("^%s*%d+[%.%)]%s+(.+)$")
    local quote = line:match("^%s*>%s?(.*)$")
    if heading and #headingLevel <= 3 then
      closeList()
      local level = #headingLevel
      if level == 1 then
        html[#html + 1] = "<big><big><b>" .. inline(heading) .. "</b></big></big><br><br>"
      elseif level == 2 then
        html[#html + 1] = "<big><b>" .. inline(heading) .. "</b></big><br>"
      else
        html[#html + 1] = "<b>" .. inline(heading) .. "</b><br>"
      end
    elseif line:match("^%s*[-*_]%s*[-*_]%s*[-*_]%s*[-*_]%s*[-*_]%s*$") then
      closeList(); html[#html + 1] = "<hr>"
    elseif bullet then
      if inList ~= "ul" then closeList(); html[#html + 1] = "<ul>"; inList = "ul" end
      html[#html + 1] = "<li>" .. inline(bullet) .. "</li>"
    elseif ordered then
      if inList ~= "ol" then closeList(); html[#html + 1] = "<ol>"; inList = "ol" end
      html[#html + 1] = "<li>" .. inline(ordered) .. "</li>"
    elseif quote then
      closeList(); html[#html + 1] = "<blockquote><i>" .. inline(quote) .. "</i></blockquote>"
    elseif line:match("^%s*$") then
      closeList(); html[#html + 1] = "<br>"
    else
      closeList(); html[#html + 1] = inline(line) .. "<br>"
    end
  end
  closeList()
  return HtmlCompat.fromHtml(table.concat(html), HtmlCompat.FROM_HTML_MODE_LEGACY)
end

--- 把内容拆分为文本段 + 代码块序列
local function splitCodeBlocks(content)
  local parts = {}
  local pos = 1
  while true do
    local s = content:find("```", pos, true)
    if not s then
      local t = content:sub(pos)
      if t ~= "" then parts[#parts + 1] = { type = "text", text = t } end
      break
    end
    local t = content:sub(pos, s - 1)
    if t ~= "" then parts[#parts + 1] = { type = "text", text = t } end
    local nl = content:find("\n", s + 3, true)
    if nl then
      local lang = content:sub(s + 3, nl - 1):gsub("^%s*(.-)%s*$", "%1")
      local e = content:find("```", nl + 1, true)
      if e then
        local code = content:sub(nl + 1, e - 1)
        code = code:gsub("\n$", "")
        parts[#parts + 1] = { type = "code", lang = lang, code = code }
        pos = e + 3
      else
        parts[#parts + 1] = { type = "text", text = content:sub(s) }
        break
      end
    else
      parts[#parts + 1] = { type = "text", text = "```" }
      pos = s + 3
    end
  end
  return parts
end

--- 复制文本到剪贴板
local function copyText(text, button)
  pcall(function()
    local ClipboardManager = luajava.bindClass("android.content.ClipboardManager")
    local ClipData = luajava.bindClass("android.content.ClipData")
    local cm = activity.getSystemService("clipboard")
    cm.setPrimaryClip(ClipData.newPlainText("agent_code", text))
    if button then
      button.setText(S.ai_copied)
      button.postDelayed(function() button.setText(S.ai_copy) end, 1200)
    else
      print(S.ai_copied)
    end
  end)
end

local function continuationLabel(state)
  if state == "incomplete" then return S.ai_incomplete_tag end
  if state == "stopped" then return S.ai_stopped_tag end
  if state == "empty_after_tools" then return S.ai_empty_after_tools end
end

local function createContinueButton()
  return loadlayout({
    MaterialButton,
    text = S.ai_continue,
    textSize = "12sp",
    textColor = ColorPrimary,
    BackgroundTintList = ColorStateList.valueOf(0),
    layout_width = "wrap",
    layout_height = "wrap",
  })
end

local function clearContinuationState(stateMessage)
  if not stateMessage then return end
  stateMessage.continuation_state = nil
  if stateMessage.role == "assistant" and tostring(stateMessage.content or "") == ""
      and not stateMessage.tool_calls then
    for index, message in ipairs(messages) do
      if message == stateMessage then table.remove(messages, index); break end
    end
  end
  saveHistory()
end

addMessageBubble = function(role, content, stateMessage)
  local container = views.msgContainer
  if not container then return end

  local isUser = (role == "user")
  local textColor = isUser and ColorOnPrimaryContainer or ColorOnSurface
  local actionColor = isUser and ColorOnPrimaryContainer or ColorPrimary

  -- 用户消息：主色容器气泡右缩进；AI 消息：无气泡平铺全宽（现代 AI 客户端范式）
  -- 边距不写入布局表：独立加载的根视图拿到的是基类 LayoutParams，margin 会被静默丢弃，
  -- 必须在 addView 时显式传 LinearLayout.LayoutParams。
  local rowViews = {}
  local row = loadlayout({
    LinearLayout,
    layout_width = "match",
    layout_height = "wrap",
    orientation = "vertical",
    {
      MaterialCardView,
      id = "bubbleCard",
      radius = "16dp",
      CardElevation = 0,
      strokeWidth = "0dp",
      CardBackgroundColor = ColorPrimaryContainer,
      layout_width = "match",
      layout_height = "wrap",
      visibility = isUser and VISIBLE or GONE,
      {
        LinearLayout,
        id = "bubbleInner",
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        padding = "12dp",
      },
    },
    {
      LinearLayout,
      id = "plainInner",
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      visibility = isUser and GONE or VISIBLE,
    },
    {
      LinearLayout,
      id = "actionRow",
      layout_width = "match",
      layout_height = "wrap",
      gravity = "center_vertical",
      layout_marginTop = "2dp",
      visibility = GONE,
    },
  }, rowViews)

  local inner = isUser and rowViews.bubbleInner or rowViews.plainInner

  local parts = splitCodeBlocks(content or "")
  for _, part in ipairs(parts) do
    if part.type == "text" then
      local markdownView = loadlayout({
        MaterialTextView,
        text = renderMarkdown(part.text),
        textSize = "14sp",
        textColor = textColor,
        lineSpacingMultiplier = 1.4,
        textIsSelectable = true,
      })
      if not isUser then
        markdownView.setMovementMethod(LinkMovementMethod.getInstance())
        markdownView.setLinksClickable(true)
      end
      inner.addView(markdownView)
    else
      -- 代码块：等宽 + 染色底 + 复制/插入按钮，代码正文也可选中
      local codeViews = {}
      local codeCard = loadlayout({
        MaterialCardView,
        radius = "8dp",
        CardElevation = 0,
        CardBackgroundColor = isUser and ColorUtils.blendARGB(ColorPrimaryContainer, ColorOnPrimaryContainer, 0.08) or ColorCodeBg,
        strokeWidth = "0dp",
        layout_width = "match",
        layout_height = "wrap",
        {
          LinearLayout,
          orientation = "vertical",
          padding = "8dp",
          {
            MaterialTextView,
            id = "codeText",
            text = part.code,
            typeface = Typeface.MONOSPACE,
            textSize = "12sp",
            textColor = isUser and ColorOnPrimaryContainer or ColorOnSurface,
            textIsSelectable = true,
          },
          {
            LinearLayout,
            orientation = "horizontal",
            layout_marginTop = "6dp",
            {
              MaterialButton,
              text = S.ai_copy,
              textSize = "11sp",
              layout_width = "wrap",
              layout_height = "30dp",
              BackgroundTintList = ColorStateList.valueOf(0),
              textColor = isUser and ColorOnPrimaryContainer or ColorPrimary,
              RippleColor = ColorStateList.valueOf(ColorRipple),
              layout_marginRight = "6dp",
              onClick = function(v) copyText(part.code, v) end,
            },
            {
              MaterialButton,
              text = S.ai_insert,
              textSize = "11sp",
              layout_width = "wrap",
              layout_height = "30dp",
              BackgroundTintList = ColorStateList.valueOf(0),
              textColor = isUser and ColorOnPrimaryContainer or ColorPrimary,
              RippleColor = ColorStateList.valueOf(ColorRipple),
              onClick = function() _M.insertCode(part.code) end,
            },
          },
        },
      }, codeViews)
      local codeLp = LinearLayout.LayoutParams(-1, -2)
      codeLp.topMargin = dp(4)
      codeLp.bottomMargin = dp(4)
      inner.addView(codeCard, codeLp)
    end
  end

  -- AI 消息的操作行：复制全文 / 续写标记与按钮
  local actionRow = rowViews.actionRow
  if not isUser then
    local continuation = stateMessage and continuationLabel(stateMessage.continuation_state)
    if (content and content ~= "") or continuation then
      actionRow.setVisibility(VISIBLE)
    end
    if content and content ~= "" then
      local copyReply = MaterialButton(activity)
      copyReply.setText(S.ai_copy)
      copyReply.setTextSize(12)
      copyReply.setAllCaps(false)
      copyReply.setTextColor(actionColor)
      copyReply.setBackgroundTintList(ColorStateList.valueOf(0))
      copyReply.setLayoutParams(LinearLayout.LayoutParams(-2, dp(30)))
      copyReply.setOnClickListener(function(v) copyText(content, v) end)
      actionRow.addView(copyReply)
    end
    if continuation then
      local marker = MaterialTextView(activity)
      marker.setText(continuation)
      marker.setTextSize(12)
      marker.setTextColor(ColorText)
      marker.setPadding(dp(8), 0, dp(8), 0)
      actionRow.addView(marker)
      local continueBtn = createContinueButton()
      continueBtn.setOnClickListener(function()
        if AgentTurn.isActive() then return end
        clearContinuationState(stateMessage)
        local parent = continueBtn.getParent()
        if parent then parent.removeView(marker); parent.removeView(continueBtn) end
        AgentTurn.bumpGeneration()
        AgentTurn.send(true)
      end)
      actionRow.addView(continueBtn)
    end
  end

  local rowLp = LinearLayout.LayoutParams(-1, -2)
  rowLp.leftMargin = isUser and dp(64) or 0
  rowLp.bottomMargin = dp(14)
  container.addView(row, rowLp)
  scrollDown()
end

--- 任务计划卡片：标题 + 进度 + 状态图标条目（完成项划线置灰）
local function addTodoBubble(list)
  local container = views.msgContainer
  if not container then return end
  local items = type(list) == "table" and list or {}
  local done = 0
  for _, item in ipairs(items) do
    if tostring(item.status or ""):lower() == "completed" then done = done + 1 end
  end

  local bubbleViews = {}
  local card = loadlayout({
    MaterialCardView,
    radius = "12dp",
    CardElevation = 0,
    strokeWidth = "0dp",
    CardBackgroundColor = ColorSurfaceContainerHigh,
    layout_width = "match",
    layout_height = "wrap",
    {
      LinearLayout,
      id = "todoInner",
      orientation = "vertical",
      padding = "10dp",
      {
        LinearLayout,
        orientation = "horizontal",
        gravity = "center_vertical",
        {
          MaterialTextView,
          text = S.ai_tool_todo,
          textSize = "12sp",
          textStyle = "bold",
          textColor = ColorOnSurface,
        },
        {
          MaterialTextView,
          text = done .. "/" .. #items,
          textSize = "12sp",
          textColor = ColorText,
          layout_marginLeft = "8dp",
        },
      },
    },
  }, bubbleViews)

  local inner = bubbleViews.todoInner
  for index, item in ipairs(items) do
    local status = tostring(item.status or ""):match("^%s*(.-)%s*$"):lower()
    if status ~= "completed" and status ~= "in_progress" then status = "pending" end
    local rowViews = {}
    local row = loadlayout({
      LinearLayout,
      orientation = "horizontal",
      layout_width = "match",
      layout_height = "wrap",
      gravity = "center_vertical",
      {
        MaterialTextView,
        text = status == "completed" and "✓" or (status == "in_progress" and "◐" or "○"),
        textSize = "12sp",
        textColor = status == "pending" and ColorText or ColorPrimary,
        layout_width = "18dp",
        gravity = "center",
      },
      {
        MaterialTextView,
        id = "todoContent",
        text = tostring(item.content or ""),
        textSize = "13sp",
        textColor = status == "in_progress" and ColorOnSurface or ColorText,
        textStyle = status == "in_progress" and "bold" or nil,
        layout_marginLeft = "2dp",
      },
    }, rowViews)
    if status == "completed" then
      rowViews.todoContent.setPaintFlags(rowViews.todoContent.getPaintFlags()
        + luajava.bindClass("android.graphics.Paint").STRIKE_THRU_TEXT_FLAG)
    end
    -- 独立加载的根视图 margin 会被加载器丢弃，间距在 addView 时显式传参
    local rowLp = LinearLayout.LayoutParams(-1, -2)
    rowLp.topMargin = dp(index > 1 and 4 or 8)
    inner.addView(row, rowLp)
  end

  local todoLp = LinearLayout.LayoutParams(-1, -2)
  todoLp.bottomMargin = dp(10)
  container.addView(card, todoLp)
  scrollDown()
end

--- 添加工具操作气泡（显示工具名和参数摘要）
addToolBubble = function(toolName, args, result)
  local container = views.msgContainer
  if not container then return end

  if AgentChat.normalizeToolName(toolName) == "update_todos" then
    local list = args and args.todos
    local failed = result and tostring(result):find("任务计划未更新", 1, true) ~= nil
    -- 列表合法且更新成功才渲染计划卡片；失败或清空走通用气泡展示结果文本
    if type(list) == "table" and #list > 0 and not failed then
      addTodoBubble(list)
      return
    end
  end

  local isError = isToolError(toolName, result)
  local icon = "→"
  if toolName:match("create") then icon = "✚"
  elseif toolName:match("delete") then icon = "✕"
  elseif toolName == "apply_patch" then icon = "✎"
  elseif toolName == "append_file" then icon = "＋"
  elseif toolName == "rename_file" then icon = "⇄"
  elseif toolName == "get_env_info" then icon = "ℹ"
  elseif toolName == "fetch_url" then icon = "↗"
  elseif toolName == "run_project" then icon = "▶"
  elseif toolName == "build_project" then icon = "📦" end

  local resultText = tostring(result or "")
  local resultLower = resultText:lower()
  local denied = resultText == tostring(S.ai_user_denied)
    or resultText:find("用户拒绝", 1, true) ~= nil
    or resultLower:find("user declined", 1, true) ~= nil
  local status = result == nil and S.ai_tool_pending
    or (denied and S.ai_tool_denied or (isError and S.ai_tool_failed or S.ai_tool_success))
  local summary = icon .. " " .. toolDisplayName(toolName) .. "  ·  " .. status
  local resultPreview = ""
  local detailParts = {}
  if toolName ~= "apply_patch" and args.path then
    detailParts[#detailParts + 1] = tostring(args.path)
  end
  if args.url then detailParts[#detailParts + 1] = tostring(args.url) end
  if toolName == "read_files" and result == nil then
    local files = args.paths
    if type(files) == "table" then
      for _, path in ipairs(files) do detailParts[#detailParts + 1] = tostring(path) end
    elseif type(files) == "string" and files ~= "" then
      detailParts[#detailParts + 1] = files
    end
  end

  if toolName == "rename_file" and args.new_path then
    detailParts[#detailParts + 1] = "→ " .. tostring(args.new_path)
  end
  if toolName == "apply_patch" and args.patch then
    local blockCount = select(2, args.patch:gsub("<<<<<<<%s*SEARCH", ""))
    local hunkCount = select(2, args.patch:gsub("@@", ""))
    if blockCount > 0 then
      detailParts[#detailParts + 1] = S.ai_search_replace_blocks:format(blockCount)
    elseif hunkCount > 0 then
      detailParts[#detailParts + 1] = "unified diff"
    end
  end
  if result then
    local display = result
    local firstLine, rest = tostring(result):match("^([^\r\n]*)[\r\n]+(.*)$")
    if not firstLine then
      firstLine = tostring(result)
      rest = ""
    end
    firstLine = firstLine:gsub("%s+$", "")
    rest = rest:gsub("^[\r\n]+", ""):gsub("%s+$", "")
    local function isOutcomeLine(line)
      return line:find("成功", 1, true)
        or line:find("失败", 1, true)
        or line:find("通过", 1, true)
        or line:find("语法错误", 1, true)
        or line:find("异常", 1, true)
        or line:find("已创建", 1, true)
        or line:find("已删除", 1, true)
        or line:find("已追加", 1, true)
        or line:find("已替换", 1, true)
        or line:find("已重命名", 1, true)
        or line:find("已应用", 1, true)
        or line:find("补丁", 1, true)
        or line:find("递归列表", 1, true)
        or line:find("搜索「", 1, true)
        or line:find("目录为空", 1, true)
        or line:find("未找到", 1, true)
        or line:find("需要 ", 1, true)
    end
    if toolName == "apply_patch" and not isError then
      local locText = tostring(result):match("位置:%s*(.+)$")
        or tostring(result):match("[Aa]t%s+([Ll%d%-%s,]+)$")
      if locText then
        locText = locText:gsub("%s+$", "")
        display = S.ai_patch_locations:format(locText)
        resultPreview = locText
      else
        display = ""
        resultPreview = firstLine:match("（(.+)）") or ""
      end
    elseif toolName == "read_files" and not isError then
      local files = args.paths
      local n = type(files) == "table" and #files or (type(files) == "string" and 1 or 0)
      display = S.ai_read_files_summary:format(n)
      local fileLines = {}
      if type(files) == "table" then
        for _, path in ipairs(files) do fileLines[#fileLines + 1] = tostring(path) end
      elseif type(files) == "string" and files ~= "" then
        fileLines[1] = files
      end
      if #fileLines > 0 then
        display = display .. "\n" .. table.concat(fileLines, "\n")
        resultPreview = table.concat(fileLines, " · ")
      end
    elseif not denied and isOutcomeLine(firstLine) then
      local elapsed = firstLine:match("耗时%s*([^）%)]+)")
      if elapsed then resultPreview = elapsed end
      display = rest
      if display == "" and resultPreview == "" then
        local extra = firstLine:match("（(.+)）") or firstLine:match(": (.+)$")
        if extra and extra ~= tostring(args.path or "") and extra ~= tostring(args.url or "") then
          resultPreview = extra
        end
      end
    end
    if #display > 12000 then
      display = display:sub(1, 12000) .. "\n\n" .. S.ai_tool_output_truncated
    end
    if not denied and display ~= "" and resultPreview == "" and not isOutcomeLine(firstLine) then
      resultPreview = tostring(display):gsub("[\r\n].*", "")
    end
    if #resultPreview > 240 then resultPreview = resultPreview:sub(1, 240) .. "…" end
    if display ~= "" then detailParts[#detailParts + 1] = tostring(display) end
  end

  local detail = table.concat(detailParts, "\n")
  local bubbleViews = {}
  local card = {
    MaterialCardView,
    radius = "12dp",
    CardElevation = 0,
    strokeWidth = isError and "1dp" or "0dp",
    strokeColor = isError and ColorError or 0,
    CardBackgroundColor = isError and ColorErrorContainer or ColorSurfaceContainerHigh,
    layout_width = "match",
    layout_height = "wrap",
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      {
        MaterialTextView,
        id = "toolHeader",
        text = summary .. (detail ~= "" and "  ›" or ""),
        contentDescription = summary .. (detail ~= "" and (". " .. S.ai_tool_tap_expand) or ""),
        textSize = "12sp",
        textStyle = "bold",
        textColor = isError and ColorOnErrorContainer or ColorOnSurface,
        padding = "10dp",
        clickable = detail ~= "",
        focusable = detail ~= "",
      },
      {
        MaterialTextView,
        text = resultPreview,
        textSize = "11sp",
        textColor = isError and ColorOnErrorContainer or ColorText,
        paddingLeft = "10dp",
        paddingRight = "10dp",
        paddingBottom = resultPreview ~= "" and "8dp" or "0dp",
        maxLines = 1,
        ellipsize = "end",
        visibility = resultPreview ~= "" and VISIBLE or GONE,
      },
      {
        MaterialTextView,
        id = "toolDetail",
        text = detail,
        textSize = "12sp",
        textColor = isError and ColorOnErrorContainer or ColorOnSurface,
        paddingLeft = "10dp",
        paddingRight = "10dp",
        paddingBottom = "10dp",
        lineSpacingMultiplier = 1.3,
        textIsSelectable = true,
        visibility = GONE,
      },
    },
  }
  local bubble = loadlayout(card, bubbleViews)
  local bubbleLp = LinearLayout.LayoutParams(-1, -2)
  bubbleLp.bottomMargin = dp(10)
  container.addView(bubble, bubbleLp)
  if detail ~= "" then
    local expanded = false
    bubbleViews.toolHeader.onClick = function()
      expanded = not expanded
      bubbleViews.toolDetail.setVisibility(expanded and VISIBLE or GONE)
      bubbleViews.toolHeader.setText(summary .. (expanded and "  ⌄" or "  ›"))
      bubbleViews.toolHeader.setContentDescription(summary .. ". "
        .. (expanded and S.ai_tool_tap_collapse or S.ai_tool_tap_expand))
    end
  end
  scrollDown()
  return bubble
end

-- ─── 加载状态 ──
-- 状态归 AgentTurn 所有；这里只负责控件更新（经钩子回调）。

local function showLoadingViews()
  if views.loadingText then views.loadingText.setText(S.ai_generating) end
  if views.loadingBar then views.loadingBar.setVisibility(VISIBLE) end
  if views.btnSend then views.btnSend.setEnabled(false) end
  if views.btnSend then views.btnSend.setVisibility(GONE) end
  if views.btnStop then views.btnStop.setVisibility(VISIBLE) end
  if views.btnStop then views.btnStop.setEnabled(true) end
end

local function setLoadingStatusView(text, active)
  if views.loadingText and active then views.loadingText.setText(tostring(text or S.ai_generating)) end
end

local function hideLoadingViews()
  if views.loadingBar then views.loadingBar.setVisibility(GONE) end
  if views.btnSend then views.btnSend.setEnabled(true) end
  if views.btnSend then views.btnSend.setVisibility(VISIBLE) end
  if views.btnStop then views.btnStop.setVisibility(GONE) end
  if views.btnStop then views.btnStop.setEnabled(true) end
end

local function showLoading() AgentTurn.showLoading() end

local function hideLoading() AgentTurn.hideLoading() end

local function fmtTokens(n)
  n = tonumber(n) or 0
  if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
  if n >= 1000 then return math.floor(n / 1000) .. "k" end
  return tostring(n)
end

local function updateContextUsage(usage)
  if type(usage) ~= "table" or not views.ctxUsage then return end
  local used = tonumber(usage.used) or 0
  local budget = tonumber(usage.budget) or 0
  local ratio = budget > 0 and used / budget or 0
  local color, label = ColorText, S.ai_ctx_ok
  if ratio >= 0.95 then
    color, label = ColorError, S.ai_ctx_full
  elseif ratio >= 0.8 then
    color, label = 0xffe6a23c, S.ai_ctx_near_limit
  end
  views.ctxUsage.setTextColor(color)
  local text = label .. " · " .. used .. "/" .. budget
  if convUsage.requests > 0 then
    text = text .. " · " .. S.ai_usage_total:format(convUsage.requests, fmtTokens(convUsage.tokens))
  end
  views.ctxUsage.setText(text)
end

--- 首轮问答完成后用辅助模型异步生成简短会话标题（替换“首条消息前 30 字”默认名）。
--- 生成成功后落盘 name 与 titled 标记；失败保持默认名，下个回合结束时重试。
local function maybeGenerateTitle()
  if titleInFlight or AgentTurn.isActive() or not conversationLoaded then return end
  local conv = AgentChat.getCurrentConv()
  if not conv or conv.titled then return end
  if #AgentChat.loadModels() == 0 then return end
  local convId = activeConversationId
  local firstUser, firstAssistant
  for _, msg in ipairs(messages) do
    if not firstUser and msg.role == "user" and not msg.compressed_summary
        and tostring(msg.content or "") ~= "" then
      firstUser = tostring(msg.content)
    elseif not firstAssistant and msg.role == "assistant"
        and tostring(msg.content or "") ~= "" then
      firstAssistant = tostring(msg.content)
    end
    if firstUser and firstAssistant then break end
  end
  if not firstUser or not firstAssistant then return end

  local function clip(text, limit)
    if #text > limit then return text:sub(1, limit) .. "…" end
    return text
  end
  local function settleTitle(raw)
    raw = tostring(raw or ""):gsub("[\r\n]+", " ")
    -- 去包裹符号与结尾标点：多字节字符逐个精确匹配，避免字节类误伤正文
    for _ = 1, 4 do
      local changed = false
      for _, lead in ipairs({ '"', "'", "“", "「", "『", "《" }) do
        if raw:sub(1, #lead) == lead then
          raw = raw:sub(#lead + 1); changed = true
        end
      end
      for _, tail in ipairs({ '"', "'", "”", "」", "』", "》", "。", ".", "！", "!", "？", "?" }) do
        if raw:sub(-#tail) == tail then
          raw = raw:sub(1, -#tail - 1); changed = true
        end
      end
      if not changed then break end
    end
    raw = raw:match("^%s*(.-)%s*$") or ""
    -- 与会话记录命名长度一致（30 字节），UTF-8 边界安全截断
    if #raw > 30 then
      raw = raw:sub(1, 30)
      while #raw > 0 and raw:byte(#raw) >= 0x80 and raw:byte(#raw) <= 0xBF do
        raw = raw:sub(1, -2)
      end
      if #raw > 0 and raw:byte(#raw) >= 0xC0 then raw = raw:sub(1, -2) end
    end
    return raw
  end

  titleInFlight = true
  AgentChat.sendStream({
    { role = "system", content = "为下面的对话生成一个简短标题。要求：不超过 16 个字；概括用户的核心诉求；只输出标题文本本身，不要引号、解释或结尾标点；使用与对话相同的语言。" },
    { role = "user", content = "用户: " .. clip(firstUser, 400) .. "\n\n助手: " .. clip(firstAssistant, 400) },
  }, {
    disableTools = true,
    maxTokens = 60,
    modelOverride = AgentChat.getAuxModelConfig and AgentChat.getAuxModelConfig() or nil,
    onDone = function(title)
      titleInFlight = false
      -- 会话已切换时不落盘，避免写错对象
      if not conversationLoaded or activeConversationId ~= convId then return end
      title = settleTitle(title)
      if title == "" then return end
      saveHistory({ name = title, titled = true })
      if views.aiTitle then views.aiTitle.setText(title) end
      print(S.ai_title_generated)
    end,
    onError = function()
      titleInFlight = false
    end,
  })
end

local function refreshMessageList()
  if not isPanelVisible() then return end
  if views.msgContainer then views.msgContainer.removeAllViews() end
  loadHistory(false)
end

local function undoLastTurn()
  if AgentTurn.isActive() then return false end
  local start
  for i = #messages, 1, -1 do
    if messages[i].role == "user" then start = i break end
  end
  if not start then return false end
  local removed = {}
  for i = start, #messages do removed[#removed + 1] = messages[i] end
  for i = #messages, start, -1 do table.remove(messages, i) end
  undoTurns[#undoTurns + 1] = removed
  table.insert(redoTurns, 1, removed)
  saveHistory(#messages == 0 and { __allow_empty = true } or nil)
  refreshMessageList()
  return true
end

local function redoLastTurn()
  if AgentTurn.isActive() or #redoTurns == 0 then return false end
  local restored = table.remove(redoTurns, 1)
  for _, message in ipairs(restored) do messages[#messages + 1] = message end
  undoTurns[#undoTurns + 1] = restored
  saveHistory()
  refreshMessageList()
  return true
end

local function applyFileChange(action)
  if AgentTurn.isActive() then return false end
  local generation = AgentTurn.bumpGeneration()
  showLoading()
  local okLaunch = pcall(function()
    xTask(function()
      local ok, result, err = pcall(action)
      return { ok = ok and result == true, error = ok and err or result }
    end, function(result)
      if generation ~= AgentTurn.generation() then return end
      hideLoading()
      if type(result) ~= "table" or not result.ok then
        print(tostring(result and result.error or "文件变更恢复失败"))
        return
      end
      if MainActivity and MainActivity.RecyclerView then MainActivity.RecyclerView.update() end
      if views.msgContainer then views.msgContainer.removeAllViews() end
      loadHistory()
      print(tostring(result.error or "文件变更已恢复"))
    end, "io")
  end)
  if not okLaunch then hideLoading() end
  return okLaunch
end

local function undoFileChange()
  if not AgentChat.hasFileUndo() then return false end
  return applyFileChange(AgentChat.undoFileChange)
end

local function redoFileChange()
  if not AgentChat.hasFileRedo() then return false end
  return applyFileChange(AgentChat.redoFileChange)
end

local function compressCurrentContext(onDone)
  return AgentTurn.compress(onDone)
end

local function showCommandMenu()
  local content = LinearLayout(activity)
  content.setOrientation(1)
  content.setPadding(dp(8), dp(4), dp(8), dp(4))
  local menuDialog

  local function addSection(label)
    local title = MaterialTextView(activity)
    title.setText(label)
    title.setTextSize(12)
    title.setTypeface(Typeface.DEFAULT, 1)
    title.setTextColor(ColorPrimary)
    title.setPadding(dp(16), dp(12), dp(16), dp(4))
    content.addView(title)
  end

  local function addAction(label, enabled, action)
    local row = MaterialTextView(activity)
    row.setText(label)
    row.setTextSize(15)
    row.setTextColor(ColorOnSurface)
    row.setGravity(16)
    row.setPadding(dp(16), 0, dp(16), 0)
    row.setMinHeight(dp(48))
    row.setEnabled(enabled)
    row.setAlpha(enabled and 1 or 0.42)
    if enabled then
      row.setClickable(true)
      row.setOnClickListener(function()
        if menuDialog then menuDialog.dismiss() end
        action()
      end)
    end
    content.addView(row)
  end

  local hasTurn = false
  for _, message in ipairs(messages) do
    if message.role == "user" then hasTurn = true break end
  end
  addSection(S.ai_command_conversation)
  addAction(S.ai_compress_context, not AgentTurn.isActive() and #messages > 0, compressCurrentContext)
  addAction(S.ai_undo_turn, not AgentTurn.isActive() and hasTurn, undoLastTurn)
  addAction(S.ai_redo_turn, not AgentTurn.isActive() and #redoTurns > 0, redoLastTurn)
  addSection(S.ai_command_files)
  addAction(S.ai_undo_file, not AgentTurn.isActive() and AgentChat.hasFileUndo(), undoFileChange)
  addAction(S.ai_redo_file, not AgentTurn.isActive() and AgentChat.hasFileRedo(), redoFileChange)
  addSection(S.ai_command_workspace)
  addAction(S.ai_switch_conv, true, showConvList)
  addAction(S.ai_center_title, true, function()
    ActivityUtil.open("agent_center", Bean and Bean.Path and Bean.Path.this_dir or "")
  end)
  addAction(S.ai_settings, true, showSettings)
  addAction(S.ai_agent_help, true, showAgentHelp)

  local scroll = ScrollView(activity)
  scroll.setFillViewport(true)
  scroll.addView(content)
  menuDialog = MaterialAlertDialogBuilder(activity)
    .setTitle(S.ai_commands)
    .setView(scroll)
    .setNegativeButton(S.ai_close, nil)
    .show()
end

-- ─── 确认对话框 ──

local function showToolConfirm(toolName, args, onAllow, onDeny)
  local title, message

  if toolName == "create_file" then
    title = S.ai_create_file
    local preview = args.content or ""
    if #preview > 500 then preview = preview:sub(1, 500) .. "\n…" end
    message = S.ai_confirm_create:format(args.path, preview)
  elseif toolName == "create_folder" then
    title = S.ai_create_folder
    message = S.ai_confirm_folder:format(args.path)
  elseif toolName == "delete_file" then
    title = S.ai_delete_file
    message = S.ai_confirm_delete:format(args.path) .. "\n\n" .. S.ai_confirm_undo_hint
  elseif toolName == "delete_folder" then
    title = S.ai_delete_folder
    message = S.ai_confirm_delete_folder:format(args.path) .. "\n\n" .. S.ai_confirm_undo_hint
  elseif toolName == "apply_patch" then
    title = S.ai_apply_patch
    local preview = args.patch or ""
    -- 格式化预览：限制行数和长度
    local lines = {}
    for line in (preview .. "\n"):gmatch("(.-)\n") do
      lines[#lines + 1] = line
    end
    if #lines > 40 then
      preview = table.concat({ unpack(lines, 1, 20) }, "\n")
        .. S.ai_lines_omitted:format(#lines - 40)
        .. table.concat({ unpack(lines, #lines - 19, #lines) }, "\n")
    elseif #preview > 2000 then
      preview = preview:sub(1, 2000) .. "\n…"
    end
    message = S.ai_confirm_patch:format(args.path, preview)
  elseif toolName == "replace_in_file" then
    title = S.ai_replace_text
    local oldPreview = args.old or ""
    local newPreview = args.new or ""
    if #oldPreview > 300 then oldPreview = oldPreview:sub(1, 300) .. "…" end
    if #newPreview > 300 then newPreview = newPreview:sub(1, 300) .. "…" end
    message = S.ai_replace_message:format(args.path, oldPreview, newPreview)
  elseif toolName == "run_lua" then
    title = S.ai_run_code
    local preview = args.code or args.content or ""
    message = S.ai_confirm_code:format(preview)
    local hosts = args.network_hosts or args.networkHosts
    if type(hosts) == "string" then hosts = { hosts } end
    if type(hosts) == "table" and #hosts > 0 then
      local hostLines = {}
      for _, host in ipairs(hosts) do
        host = tostring(host):gsub("\r", "\\r"):gsub("\n", "\\n")
        hostLines[#hostLines + 1] = "• " .. host
      end
      message = message .. S.ai_confirm_code_network:format(table.concat(hostLines, "\n"))
    end
  elseif toolName == "fetch_url" then
    title = S.ai_fetch_url
    local method = tostring(args.method or "GET"):upper():gsub("\r", "\\r"):gsub("\n", "\\n")
    local url = tostring(args.url or "?"):gsub("\r", "\\r"):gsub("\n", "\\n")
    message = S.ai_confirm_fetch_url:format(method, url)
  elseif toolName == "append_file" then
    title = S.ai_append_file
    local preview = args.content or ""
    if #preview > 500 then preview = preview:sub(1, 500) .. "\n…" end
    message = S.ai_confirm_append:format(args.path or "?", preview)
  elseif toolName == "rename_file" then
    title = S.ai_rename_file
    local srcPath = args.path or "?"
    local dstPath = args.new_path or args.newPath or "?"
    message = S.ai_confirm_rename:format(srcPath, dstPath)
  elseif toolName:match("^mcp::") or toolName:match("^mcp__") then
    title = S.ai_confirm_external_title
    local okArgs, encodedArgs = pcall(json.encode, args or {})
    local argsPreview = okArgs and tostring(encodedArgs) or tostring(args or "")
    if #argsPreview > 2000 then argsPreview = argsPreview:sub(1, 2000) .. "\n…" end
    message = S.ai_confirm_external_message:format(toolDisplayName(toolName), argsPreview)
      .. "\n\n" .. S.ai_confirm_external_hint
  elseif toolName == "read_file" or toolName == "read_files"
      or toolName == "list_dir" or toolName == "search_in_files" then
    title = S.ai_confirm_external_read_title
    local target = args.path or (type(args.paths) == "table" and table.concat(args.paths, "\n")) or args.paths or "?"
    message = S.ai_confirm_external_read_message:format(tostring(target))
  else
    title = S.ai_confirm_tool_title
    message = S.ai_confirm_tool_message:format(toolDisplayName(toolName))
  end

  local decided = false
  local function denyOnce()
    if decided then return end
    decided = true
    activeToolConfirm = nil
    if onDeny then onDeny() end
  end
  local confirm = MaterialAlertDialogBuilder(activity)
    .setTitle(title)
    .setMessage(message)
    .setPositiveButton(S.ai_allow, function()
      if decided then return end
      decided = true
      activeToolConfirm = nil
      if onAllow then onAllow() end
    end)
    .setNegativeButton(S.ai_deny, function()
      denyOnce()
    end)
    .show()
  activeToolConfirm = confirm
  confirm.setOnCancelListener(function() denyOnce() end)
end

-- ─── 会话持久化 ──

saveHistory = function(updates)
  if not conversationLoaded or not activeConversationId or activeConversationId == "" then
    return false
  end
  local projectPath = AgentChat.getCurrentProjectPath()
  if activeConversationProjectPath ~= projectPath then return false end
  local allowEmpty = type(updates) == "table" and updates.__allow_empty == true
  if #messages == 0 and activeConversationHadMessages and not allowEmpty then
    return false
  end
  -- 镜像同步会话级状态：任务计划与累计用量随每次落盘持久化，
  -- 与工具回合的状态提交合并为同一次写入
  local merged = updates
  if type(updates) ~= "table" or updates.todos == nil then
    merged = {}
    if type(updates) == "table" then
      for key, value in pairs(updates) do merged[key] = value end
    end
    merged.todos = TodoManager.get() or {}
    merged.usage = { requests = convUsage.requests, tokens = convUsage.tokens }
  end
  local saved = AgentChat.saveConversation(activeConversationId, messages, merged)
  if saved then activeConversationHadMessages = #messages > 0 end
  return saved
end

loadHistory = function(resetTurnHistory)
  if resetTurnHistory ~= false then
    undoTurns = {}
    redoTurns = {}
    if AgentChat.clearActiveSkill then AgentChat.clearActiveSkill() end
  end
  local conv = AgentChat.getCurrentConv()
  if not conv then
    local created = AgentChat.createConversation()
    conv = created or AgentChat.getCurrentConv()
  end
  activeConversationId = conv and conv.id or nil
  activeConversationProjectPath = conv and AgentChat.getCurrentProjectPath() or nil
  messages = conv and conv.messages or {}
  -- 会话的任务计划随会话切换整体注入（空/缺失即清空）
  TodoManager.set(conv and conv.todos or nil)
  -- 累计用量随会话载入
  local savedUsage = type(conv and conv.usage) == "table" and conv.usage or nil
  convUsage = {
    requests = tonumber(savedUsage and savedUsage.requests) or 0,
    tokens = tonumber(savedUsage and savedUsage.tokens) or 0,
  }
  conversationLoaded = conv ~= nil
  -- 上次会话的任务可能被应用退出打断：注入提示并清除标记
  -- （必须在 conversationLoaded 置位之后，saveHistory 才会真正落盘）
  if conv and conv.running and not AgentTurn.isActive() then
    conv.running = false
    messages[#messages + 1] = { role = "assistant", content = S.ai_task_interrupted }
    saveHistory({ running = false })
  end
  activeConversationHadMessages = #messages > 0
  if updateProjectLabel then updateProjectLabel() end
  if views.aiTitle and conv then views.aiTitle.setText(convName(conv)) end
  -- 重建气泡
  local container = views.msgContainer
  if container then
    local consumedTools = {}
    for messageIndex, msg in ipairs(messages) do
      if msg.role == "user" then
        addMessageBubble("user", msg.content or "")
      elseif msg.role == "assistant" then
        -- 跳过纯工具调用（无文本内容）的空 assistant 消息
        local content = msg.content or ""
        if content ~= "" or msg.continuation_state then
          addMessageBubble("assistant", content, msg)
        end
        -- 显示工具调用气泡，并记录 id 供 tool 结果回填
        if msg.tool_calls then
          local resultById, resultWithoutId = {}, {}
          local scanIndex = messageIndex + 1
          while scanIndex <= #messages and messages[scanIndex].role == "tool" do
            local candidate = messages[scanIndex]
            if candidate.tool_call_id and candidate.tool_call_id ~= "" then
              resultById[candidate.tool_call_id] = { index = scanIndex, content = candidate.content or "" }
            else
              resultWithoutId[#resultWithoutId + 1] = { index = scanIndex, content = candidate.content or "" }
            end
            scanIndex = scanIndex + 1
          end
          local missingIndex = 1
          for _, tc in ipairs(msg.tool_calls) do
            local fn = tc["function"]
            local toolName = fn and fn.name or tc.name or ""
            local args = {}
            pcall(function() args = json.decode(fn and fn.arguments or tc.arguments or "{}") end)
            local tid = tc.id or ""
            local matched = tid ~= "" and resultById[tid] or nil
            if not matched then
              matched = resultWithoutId[missingIndex]
              if matched then missingIndex = missingIndex + 1 end
            end
            local result = matched and matched.content or nil
            if matched then consumedTools[matched.index] = true end
            addToolBubble(toolName, args, result)
          end
        end
      elseif msg.role == "tool" then
        local result = msg.content or ""
        if not consumedTools[messageIndex] and result ~= "" then
          addToolBubble("tool_result", {}, result)
        end
        if msg.continuation_state then addMessageBubble("assistant", "", msg) end
      end
    end
    for messageIndex = #messages, 1, -1 do
      local message = messages[messageIndex]
      if message.role == "user" and message.request_error then
        addRequestErrorBubble(tostring(message.request_error), messageIndex)
        break
      end
    end
  end
  AgentTurn.rerenderStream()
  return #messages
end

-- ─── 发送消息核心 ──

addRequestErrorBubble = function(err, messageIndex)
  if not views.msgContainer then return end
  local lowerError = tostring(err):lower()
  local action = S.ai_retry
  local opensSettings = lowerError:find("http 401", 1, true) or lowerError:find("http 403", 1, true)
    or lowerError:find("api key", 1, true) or lowerError:find("unauthorized", 1, true)
  local compresses = lowerError:find("context", 1, true) or lowerError:find("token", 1, true)
    or lowerError:find("too large", 1, true)
  if opensSettings then action = S.ai_open_settings
  elseif compresses then action = S.ai_compress_retry end

  local errorViews = {}
  local errorCard = loadlayout({
    MaterialCardView,
    radius = "14dp",
    CardElevation = 0,
    strokeWidth = "0dp",
    CardBackgroundColor = ColorErrorContainer,
    layout_width = "match",
    layout_height = "wrap",
    {
      LinearLayout,
      orientation = "vertical",
      padding = "12dp",
      {
        MaterialTextView,
        text = tostring(err),
        textSize = "13sp",
        textColor = ColorOnErrorContainer,
        lineSpacingMultiplier = 1.3,
        textIsSelectable = true,
      },
      {
        LinearLayout,
        orientation = "horizontal",
        layout_marginTop = "8dp",
        {
          MaterialButton,
          id = "recoverButton",
          text = action,
          layout_width = "wrap",
          textSize = "12sp",
          BackgroundTintList = ColorStateList.valueOf(ColorError),
          textColor = ColorOnError,
        },
        {
          MaterialButton,
          id = "editButton",
          text = S.ai_edit_request,
          layout_width = "wrap",
          layout_marginLeft = "8dp",
          textSize = "12sp",
          BackgroundTintList = ColorStateList.valueOf(0),
          textColor = ColorOnErrorContainer,
        },
      },
    },
  }, errorViews)
  local errorLp = LinearLayout.LayoutParams(-1, -2)
  errorLp.bottomMargin = dp(10)
  views.msgContainer.addView(errorCard, errorLp)

  errorViews.recoverButton.onClick = function()
    if AgentTurn.isActive() then return end
    local message = messages[messageIndex]
    if not message or message.role ~= "user" or not message.request_error then
      print(S.ai_request_expired)
      return
    end
    if opensSettings then
      showSettings()
      return
    end
    local retryPayload = AgentTurn.retryPayloadFor(message)
    message.request_error = nil
    saveHistory()
    refreshMessageList()
    if compresses then
      AgentTurn.compress(function() AgentTurn.send(false) end)
    else
      AgentTurn.bumpGeneration()
      if retryPayload then AgentTurn.sendRaw(retryPayload, false)
      else AgentTurn.send(false) end
    end
  end

  errorViews.editButton.onClick = function()
    if AgentTurn.isActive() then return end
    local message = messages[messageIndex]
    if not message or message.role ~= "user" or not views.msgInput then
      print(S.ai_request_expired)
      return
    end
    editingMessageIndex = messageIndex
    views.msgInput.setText(tostring(message.content or ""))
    views.msgInput.requestFocus()
  end
end

-- ─── 发送消息 ──

sendMessage = function()
  if AgentTurn.isActive() then return end

  local input = views.msgInput
  if not input then return end

  local text = tostring(input.getText() or ""):match("^%s*(.-)%s*$")
  if text == "" then return end

  input.setText("")

  local skill = AgentChat.selectSkill(text)

  for _, message in ipairs(messages) do
    if message.role == "user" then message.request_error = nil end
  end

  local editedIndex = editingMessageIndex
  editingMessageIndex = nil
  if editedIndex and messages[editedIndex] and messages[editedIndex].role == "user" then
    messages[editedIndex].content = text
    messages[editedIndex].request_error = nil
    for index = #messages, editedIndex + 1, -1 do table.remove(messages, index) end
    if views.msgContainer then views.msgContainer.removeAllViews() end
    loadHistory(false)
  else
    addMessageBubble("user", text)
    messages[#messages + 1] = { role = "user", content = text }
  end
  if skill then
    local conv = AgentChat.getCurrentConv()
    local skills = conv and conv.skills or {}
    skills[skill.name] = true
    saveHistory({ skills = skills })
  else
    saveHistory()
  end
  redoTurns = {}

  if not AgentChat.hasApiKey() then
    addMessageBubble("assistant", S.ai_need_config)
    return
  end

  -- 构建上下文
  local context = AgentChat.buildContext()
  local userMsg = text
  if context ~= "" then
    userMsg = context .. "\n\n用户问题: " .. text
  end

  -- 编辑器上下文只加入请求副本，不写入持久化会话；超预算时先压缩历史。
  AgentTurn.bumpGeneration()
  AgentTurn.send(false, userMsg)
end

-- ─── 供应商与模型 ──

local showProviderEditor, showModelEditor, showFetchedModels, showProviderManager

local function fieldText(view)
  return tostring(view and view.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
end

local function fetchError(kind, detail)
  if kind == "need_key" then return S.ai_need_api_key end
  if kind == "need_url" then return S.ai_need_url end
  if kind == "empty" then return S.ai_fetch_models_empty end
  if kind == "unsupported" then return S.ai_balance_unsupported end
  return tostring(detail or kind or "")
end

local function formatBalance(parsed)
  if type(parsed) ~= "table" then return nil end
  if parsed.kind == "deepseek" then
    local lines = {}
    for _, info in ipairs(parsed.infos or {}) do
      lines[#lines + 1] = S.ai_balance_deepseek:format(info.currency, info.total, info.topped_up, info.granted)
    end
    if parsed.available == false then lines[#lines + 1] = S.ai_balance_unavailable end
    return #lines > 0 and table.concat(lines, "\n") or nil
  end
  if parsed.kind == "siliconflow" then
    return S.ai_balance_siliconflow:format(parsed.total, parsed.charge, parsed.gift)
  end
  if parsed.kind == "moonshot" then
    return S.ai_balance_moonshot:format(parsed.available, parsed.cash, parsed.voucher)
  end
  if parsed.kind == "openrouter" then
    return S.ai_balance_openrouter:format(parsed.remaining, parsed.total, parsed.used)
  end
  if parsed.kind == "subscription" then
    return S.ai_balance_subscription:format(parsed.amount)
  end
end

local function queryBalance(url, key, onDone)
  AgentChat.fetchBalance(url, key, function(ok, payload, detail)
    if onDone then onDone() end
    if not ok then
      print(fetchError(payload, detail))
      return
    end
    local text = formatBalance(payload)
    if not text then
      print(S.ai_balance_unsupported)
      return
    end
    MaterialAlertDialogBuilder(activity)
      .setTitle(S.ai_balance_title)
      .setMessage(text)
      .setPositiveButton(S.ai_ok, nil)
      .show()
  end)
end

local function fetchModels(url, key, onDone, onIds)
  AgentChat.fetchProviderModels(url, key, function(ok, payload, detail)
    if onDone then onDone() end
    if not ok then
      print(fetchError(payload, detail))
      return
    end
    onIds(payload)
  end)
end

local function providerLabel(provider)
  if not provider then return S.ai_missing_provider end
  local name = provider.name ~= "" and provider.name or provider.url
  return name
end

showFetchedModels = function(ids, ensureProvider)
  local rows = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    padding = "8dp",
  }
  for index, modelId in ipairs(ids) do
    rows[#rows + 1] = {
      MaterialCheckBox,
      id = "pick" .. index,
      text = modelId,
      layout_width = "match",
      layout_height = "wrap",
    }
  end
  local dialogViews = {}
  local content = loadlayout({
    ScrollView,
    layout_width = "match",
    layout_height = "360dp",
    rows,
  }, dialogViews)
  MaterialAlertDialogBuilder(activity)
    .setTitle(S.ai_pick_models)
    .setView(content)
    .setPositiveButton(S.ai_add, function()
      local provider = ensureProvider and ensureProvider() or nil
      if not provider then return end
      local selected = {}
      for index, modelId in ipairs(ids) do
        local box = dialogViews["pick" .. index]
        if box and box.isChecked() and not AgentChat.findModel(provider.id, modelId) then
          selected[#selected + 1] = modelId
        end
      end
      if #selected == 0 then
        print(S.ai_select_one)
        return
      end
      local indexes = AgentChat.addModels(provider.id, selected)
      if #indexes == 0 then
        print(S.ai_fetch_models_empty)
        return
      end
      if AgentChat.getCurrentModelIndex() == 0 then
        AgentChat.setCurrentModel(indexes[1])
      end
      updateModelLabel()
      print(S.ai_fetch_models_ok:format(#indexes))
      showModelPicker()
    end)
    .setNegativeButton(S.ai_cancel, nil)
    .show()
end

showProviderEditor = function(existing, onSaved)
  local providerId = existing and existing.id or nil
  local inputLayout = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    padding = "16dp",
    {
      MaterialTextView,
      text = S.ai_name,
      textSize = "14sp", textStyle = "bold", textColor = ColorOnSurface,
    },
    {
      EditText, id = "nameInput",
      layout_width = "match", layout_height = "wrap", minHeight = "48dp",
      textSize = "14sp", singleLine = true, hint = "DeepSeek",
      layout_marginTop = "8dp",
    },
    {
      MaterialTextView,
      text = S.ai_api_key,
      textSize = "14sp", textStyle = "bold", textColor = ColorOnSurface,
      layout_marginTop = "12dp",
    },
    {
      EditText, id = "keyInput",
      layout_width = "match", layout_height = "wrap", minHeight = "48dp",
      textSize = "14sp", singleLine = true, hint = "sk-...",
      layout_marginTop = "8dp",
    },
    {
      MaterialTextView,
      text = S.ai_api_url,
      textSize = "14sp", textStyle = "bold", textColor = ColorOnSurface,
      layout_marginTop = "12dp",
    },
    {
      EditText, id = "urlInput",
      layout_width = "match", layout_height = "wrap", minHeight = "48dp",
      textSize = "14sp", singleLine = true,
      hint = "https://api.deepseek.com/v1",
      layout_marginTop = "8dp",
    },
    {
      MaterialButton, id = "fetchButton",
      text = S.ai_fetch_models,
      textSize = "13sp",
      layout_width = "match", layout_marginTop = "12dp",
      includeFontPadding = false,
      BackgroundTintList = ColorStateList.valueOf(ColorPrimary),
      textColor = ColorOnPrimary,
    },
    {
      MaterialButton, id = "balanceButton",
      text = S.ai_fetch_balance,
      textSize = "13sp",
      layout_width = "match", layout_marginTop = "8dp",
      includeFontPadding = false,
      BackgroundTintList = ColorStateList.valueOf(ColorSecondaryContainer),
      textColor = ColorOnSecondaryContainer,
    },
  }
  local dialogViews = {}
  local content = loadlayout({
    ScrollView,
    layout_width = "match",
    layout_height = "wrap",
    fillViewport = true,
    inputLayout,
  }, dialogViews)
  local function ensureProvider()
    local name = fieldText(dialogViews.nameInput)
    local key = fieldText(dialogViews.keyInput)
    local url = fieldText(dialogViews.urlInput)
    if key == "" then print(S.ai_need_api_key) return nil end
    if url == "" then print(S.ai_need_url) return nil end
    if providerId then AgentChat.updateProvider(providerId, name, url, key)
    else
      local provider = AgentChat.addProvider(name, url, key)
      providerId = provider.id
    end
    return AgentChat.findProvider(providerId)
  end
  MaterialAlertDialogBuilder(activity)
    .setTitle(existing and S.ai_edit_provider or S.ai_add_provider)
    .setView(content)
    .setPositiveButton(S.ai_save, function()
      local provider = ensureProvider()
      if not provider then return end
      print(S.ai_saved)
      if onSaved then onSaved(provider) else showProviderManager() end
    end)
    .setNegativeButton(S.ai_cancel, nil)
    .show()
  dialogViews.nameInput.setText(existing and existing.name or "")
  dialogViews.keyInput.setText(existing and existing.key or "")
  dialogViews.urlInput.setText(existing and existing.url or "")
  dialogViews.fetchButton.onClick = function()
    local url = fieldText(dialogViews.urlInput)
    local key = fieldText(dialogViews.keyInput)
    local button = dialogViews.fetchButton
    local previous = tostring(button.getText())
    button.setEnabled(false)
    button.setText(S.ai_fetching)
    fetchModels(url, key, function()
      pcall(function()
        button.setEnabled(true)
        button.setText(previous)
      end)
    end, function(ids)
      showFetchedModels(ids, ensureProvider)
    end)
  end
  dialogViews.balanceButton.onClick = function()
    local url = fieldText(dialogViews.urlInput)
    local key = fieldText(dialogViews.keyInput)
    local button = dialogViews.balanceButton
    local previous = tostring(button.getText())
    button.setEnabled(false)
    button.setText(S.ai_fetching)
    queryBalance(url, key, function()
      pcall(function()
        button.setEnabled(true)
        button.setText(previous)
      end)
    end)
  end
end

showProviderManager = function()
  local providers = AgentChat.loadProviders()
  if #providers == 0 then
    showProviderEditor()
    return
  end
  local labels = {}
  for index, provider in ipairs(providers) do
    labels[index] = providerLabel(provider) .. "  (" .. S.ai_model_count:format(AgentChat.countModels(provider.id)) .. ")"
  end
  MaterialAlertDialogBuilder(activity)
    .setTitle(S.ai_providers)
    .setItems(labels, function(_, which)
      local provider = providers[which + 1]
      local extra = AgentChat.countModels(provider.id) > 0
        and ("\n" .. S.ai_provider_models:format(AgentChat.countModels(provider.id)))
        or ""
      MaterialAlertDialogBuilder(activity)
        .setTitle(providerLabel(provider))
        .setMessage(S.ai_api_url .. ": " .. provider.url .. extra)
        .setPositiveButton(S.ai_edit, function()
          showProviderEditor(provider)
        end)
        .setNegativeButton(S.ai_delete, function()
          MaterialAlertDialogBuilder(activity)
            .setTitle(S.ai_delete)
            .setMessage(S.ai_confirm_delete_provider:format(providerLabel(provider))
              .. (AgentChat.countModels(provider.id) > 0
                and ("\n" .. S.ai_provider_models:format(AgentChat.countModels(provider.id)))
                or ""))
            .setPositiveButton(S.ai_delete, function()
              AgentChat.removeProvider(provider.id)
              print(S.ai_deleted_name:format(providerLabel(provider)))
              updateModelLabel()
              showProviderManager()
            end)
            .setNegativeButton(S.ai_cancel, nil)
            .show()
        end)
        .setNeutralButton(S.ai_fetch_balance, function()
          queryBalance(provider.url, provider.key)
        end)
        .show()
    end)
    .setPositiveButton(S.ai_add, function()
      showProviderEditor()
    end)
    .setNegativeButton(S.ai_close, nil)
    .show()
end

showModelEditor = function(existingIndex)
  local existing = existingIndex and AgentChat.loadModels()[existingIndex] or nil
  local providers = AgentChat.loadProviders()
  if #providers == 0 then
    showProviderEditor(nil, function() showModelEditor(existingIndex) end)
    return
  end
  local selectedId = existing and existing.providerId or providers[1].id
  if not AgentChat.findProvider(selectedId) then selectedId = providers[1].id end
  local inputLayout = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    padding = "16dp",
    {
      MaterialTextView,
      text = S.ai_name,
      textSize = "14sp", textStyle = "bold", textColor = ColorOnSurface,
    },
    {
      EditText, id = "nameInput",
      layout_width = "match", layout_height = "wrap", minHeight = "48dp",
      textSize = "14sp", singleLine = true, hint = "DeepSeek V4 Flash",
      layout_marginTop = "8dp",
    },
    {
      MaterialTextView,
      text = S.ai_provider,
      textSize = "14sp", textStyle = "bold", textColor = ColorOnSurface,
      layout_marginTop = "12dp",
    },
    {
      MaterialButton, id = "providerButton",
      textSize = "13sp",
      layout_width = "match", layout_marginTop = "8dp",
      includeFontPadding = false,
      BackgroundTintList = ColorStateList.valueOf(ColorSecondaryContainer),
      textColor = ColorOnSecondaryContainer,
    },
    {
      MaterialTextView,
      text = S.ai_model_params,
      textSize = "14sp", textStyle = "bold", textColor = ColorOnSurface,
      layout_marginTop = "12dp",
    },
    {
      EditText, id = "modelInput",
      layout_width = "match", layout_height = "wrap", minHeight = "48dp",
      textSize = "14sp", singleLine = true, hint = "deepseek-v4-flash",
      layout_marginTop = "8dp",
    },
    {
      MaterialButton, id = "fetchButton",
      text = S.ai_fetch_models,
      textSize = "13sp",
      layout_width = "match", layout_marginTop = "8dp",
      includeFontPadding = false,
      BackgroundTintList = ColorStateList.valueOf(ColorPrimary),
      textColor = ColorOnPrimary,
    },
    {
      MaterialTextView,
      text = S.ai_context_len,
      textSize = "13sp", textColor = ColorText,
      layout_marginTop = "12dp",
    },
    {
      EditText, id = "contextInput",
      layout_width = "match", layout_height = "wrap", minHeight = "44dp",
      textSize = "14sp", singleLine = true, inputType = 0x0002,
      hint = S.ai_ctx_hint,
    },
    {
      MaterialTextView,
      text = S.ai_max_tokens,
      textSize = "13sp", textColor = ColorText,
      layout_marginTop = "8dp",
    },
    {
      EditText, id = "maxTokensInput",
      layout_width = "match", layout_height = "wrap", minHeight = "44dp",
      textSize = "14sp", singleLine = true, inputType = 0x0002,
    },
    {
      Switch, id = "responsesSwitch",
      text = S.ai_use_responses,
      layout_width = "match", layout_height = "wrap",
      layout_marginTop = "12dp",
    },
  }

  local dialogViews = {}
  local content = loadlayout({
    ScrollView,
    layout_width = "match",
    layout_height = "wrap",
    fillViewport = true,
    inputLayout,
  }, dialogViews)

  MaterialAlertDialogBuilder(activity)
    .setTitle(existingIndex and S.ai_edit_model or S.ai_add_model)
    .setView(content)
    .setPositiveButton(S.ai_save, function()
      local name = fieldText(dialogViews.nameInput)
      local model = fieldText(dialogViews.modelInput)
      local contextLength = fieldText(dialogViews.contextInput)
      local maxTokens = fieldText(dialogViews.maxTokensInput)
      local responses = dialogViews.responsesSwitch.isChecked()
      if model == "" then
        print(S.ai_need_model)
        return
      end
      if not AgentChat.findProvider(selectedId) then
        print(S.ai_need_provider)
        return
      end
      if name == "" then name = model end
      if existingIndex then
        AgentChat.updateModel(existingIndex, name, selectedId, model, responses, contextLength, maxTokens)
        AgentChat.setCurrentModel(existingIndex)
      else
        local newIndex = AgentChat.addModel(name, selectedId, model, responses, contextLength, maxTokens)
        AgentChat.setCurrentModel(newIndex)
      end
      updateModelLabel()
      print(S.ai_saved)
      showModelPicker()
    end)
    .setNegativeButton(S.ai_cancel, nil)
    .show()

  local function refreshProviderButton()
    dialogViews.providerButton.setText(providerLabel(AgentChat.findProvider(selectedId)))
  end
  dialogViews.providerButton.onClick = function()
    local labels = {}
    for index, provider in ipairs(providers) do
      labels[index] = providerLabel(provider)
    end
    MaterialAlertDialogBuilder(activity)
      .setTitle(S.ai_provider)
      .setItems(labels, function(_, which)
        selectedId = providers[which + 1].id
        refreshProviderButton()
      end)
      .setNeutralButton(S.ai_providers, function()
        showProviderManager()
      end)
      .setNegativeButton(S.ai_cancel, nil)
      .show()
  end
  dialogViews.fetchButton.onClick = function()
    local provider = AgentChat.findProvider(selectedId)
    if not provider then
      print(S.ai_need_provider)
      return
    end
    local button = dialogViews.fetchButton
    local previous = tostring(button.getText())
    button.setEnabled(false)
    button.setText(S.ai_fetching)
    fetchModels(provider.url, provider.key, function()
      pcall(function()
        button.setEnabled(true)
        button.setText(previous)
      end)
    end, function(ids)
      MaterialAlertDialogBuilder(activity)
        .setTitle(S.ai_pick_model)
        .setItems(ids, function(_, which)
          dialogViews.modelInput.setText(ids[which + 1])
          if fieldText(dialogViews.nameInput) == "" then
            dialogViews.nameInput.setText(ids[which + 1])
          end
        end)
        .setNegativeButton(S.ai_cancel, nil)
        .show()
    end)
  end
  dialogViews.nameInput.setText(existing and existing.name or "")
  dialogViews.modelInput.setText(existing and existing.model or "")
  dialogViews.contextInput.setText(tostring(existing and existing.contextLength or 30000))
  dialogViews.maxTokensInput.setText(tostring(existing and existing.maxTokens or 4096))
  dialogViews.responsesSwitch.setChecked(existing and existing.responses == true)
  refreshProviderButton()
end

showModelManager = function()
  local models = AgentChat.loadModels()
  if #models == 0 then
    showModelEditor()
    return
  end

  local labels = {}
  for i, m in ipairs(models) do
    labels[i] = m.name .. "  (" .. m.model .. ") · " .. providerLabel(AgentChat.findProvider(m.providerId))
  end

  MaterialAlertDialogBuilder(activity)
    .setTitle(S.ai_manage_model)
    .setItems(labels, function(_, which)
      local m = models[which + 1]
      local provider = AgentChat.findProvider(m.providerId)
      MaterialAlertDialogBuilder(activity)
        .setTitle(m.name)
        .setMessage(S.ai_provider .. ": " .. providerLabel(provider) .. "\n"
          .. S.ai_model .. ": " .. m.model .. "\n"
          .. S.ai_context_len .. ": " .. tostring(m.contextLength or 30000) .. "\n"
          .. S.ai_max_tokens .. ": " .. tostring(m.maxTokens or 4096))
        .setPositiveButton(S.ai_edit, function()
          showModelEditor(which + 1)
        end)
        .setNegativeButton(S.ai_delete, function()
          AgentChat.removeModel(which + 1)
          print(S.ai_deleted_name:format(m.name))
          updateModelLabel()
          showModelManager()
        end)
        .setNeutralButton(provider and S.ai_fetch_balance or S.ai_cancel, function()
          if provider then queryBalance(provider.url, provider.key) end
        end)
        .show()
    end)
    .setPositiveButton(S.ai_add, function()
      showModelEditor()
    end)
    .setNeutralButton(S.ai_providers, function()
      showProviderManager()
    end)
    .setNegativeButton(S.ai_close, nil)
    .show()
end

showModelPicker = function()
  local models = AgentChat.loadModels()
  local current = AgentChat.getCurrentModelIndex()

  if #models == 0 then
    showModelEditor()
    return
  end

  local labels = {}
  for i, m in ipairs(models) do
    local marker = (i == current) and " ✓ " or "    "
    labels[i] = marker .. m.name .. "  (" .. m.model .. ") · " .. providerLabel(AgentChat.findProvider(m.providerId))
  end
  labels[#labels + 1] = S.ai_add_model_item

  MaterialAlertDialogBuilder(activity)
    .setTitle(S.ai_switch_model)
    .setItems(labels, function(_, which)
      if which == #models then
        showModelEditor()
      else
        AgentChat.setCurrentModel(which + 1)
        updateModelLabel()
        print(S.ai_switched_to:format(models[which + 1].name))
      end
    end)
    .setNegativeButton(S.ai_manage, function()
      showModelManager()
    end)
    .setNeutralButton(S.ai_providers, function()
      showProviderManager()
    end)
    .setPositiveButton(S.ai_close, nil)
    .show()
end

showSettings = function()
  local autoApprove = this.getSharedData("ai_auto_approve", "0") == "1"

  local autoApproveNetwork = this.getSharedData("ai_auto_approve_network", "1") == "1"

  local projectPolicy = AgentChat.getProjectPolicy and AgentChat.getProjectPolicy() or nil
  local policyRestricted = type(projectPolicy) == "table" and projectPolicy.autoApprove == false
  local policyHosts = ""
  if type(projectPolicy) == "table" and type(projectPolicy.networkHosts) == "table" then
    policyHosts = table.concat(projectPolicy.networkHosts, " ")
  end
  local autoRunSandbox = this.getSharedData("ai_auto_run_sandbox", "1") == "1"
  local allowSelfSigned = this.getSharedData("ai_allow_selfsigned", "0") == "1"
  local temp = this.getSharedData("ai_temperature", "0.7")
  local retryCount = this.getSharedData("ai_retry_count", "2")
  local systemPrompt = this.getSharedData("ai_system_prompt", "")
  local dlgViews = {}
  local settingsDialog
  local mcpRenderGeneration = 0

  local function sectionTitle(text)
    return {
      MaterialTextView,
      text = text,
      textSize = "13sp", textStyle = "bold", textColor = ColorPrimary,
      layout_marginBottom = "8dp",
    }
  end

  local body = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    padding = "16dp",
    -- 生成参数
    {
      MaterialCardView,
      layout_width = "match",
      layout_height = "wrap",
      layout_marginBottom = "12dp",
      CardBackgroundColor = ColorSurface,
      CardElevation = 0,
      {
        LinearLayout,
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        padding = "16dp",
        sectionTitle(S.ai_gen_params),
        {
          MaterialTextView,
          text = S.ai_temperature,
          textSize = "13sp", textColor = ColorText,
        },
        {
          EditText,
          id = "tempInput",
          text = tostring(temp),
          layout_width = "match", layout_height = "wrap", minHeight = "40dp",
          textSize = "14sp", singleLine = true,
          inputType = 0x2002,
          layout_marginBottom = "8dp",
        },
        {
          MaterialTextView,
          text = S.ai_retry_count_label,
          textSize = "13sp", textColor = ColorText,
        },
        {
          EditText,
          id = "retryInput",
          text = tostring(retryCount),
          layout_width = "match", layout_height = "wrap", minHeight = "40dp",
          textSize = "14sp", singleLine = true,
          inputType = 0x0002,
          hint = S.ai_retry_hint,
        },
        {
          MaterialTextView,
          text = S.ai_aux_model,
          textSize = "13sp", textColor = ColorText,
          layout_marginTop = "12dp",
        },
        {
          MaterialTextView,
          text = S.ai_aux_model_desc,
          textSize = "11sp", textColor = ColorText,
        },
        {
          MaterialTextView,
          id = "auxModelValue",
          textSize = "14sp", textColor = ColorPrimary,
          padding = "8dp",
        },
      },
    },
    -- 行为
    {
      MaterialCardView,
      layout_width = "match",
      layout_height = "wrap",
      layout_marginBottom = "12dp",
      CardBackgroundColor = ColorSurface,
      CardElevation = 0,
      {
        LinearLayout,
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        padding = "16dp",
        sectionTitle(S.ai_security),
        {
          MaterialTextView,
          text = S.ai_security_desc,
          textSize = "12sp", textColor = ColorText,
          layout_marginBottom = "10dp",
        },
        {
          LinearLayout,
          orientation = "horizontal",
          gravity = "center_vertical",
          layout_width = "match",
          layout_height = "wrap",
          {
            LinearLayout,
            orientation = "vertical",
            layout_width = "0dp",
            layout_weight = 1,
            {
              MaterialTextView,
              text = S.ai_auto_run_sandbox,
              textSize = "14sp", textColor = ColorOnSurface,
            },
            {
              MaterialTextView,
              text = S.ai_auto_run_sandbox_desc,
              textSize = "12sp", textColor = ColorText,
              layout_marginTop = "2dp",
            },
          },
          {
            Switch,
            id = "autoRunSandboxSwitch",
            checked = autoRunSandbox,
            layout_marginLeft = "12dp",
          },
        },
        {
          LinearLayout,
          orientation = "horizontal",
          gravity = "center_vertical",
          layout_width = "match",
          layout_height = "wrap",
          layout_marginTop = "12dp",
          {
            LinearLayout,
            orientation = "vertical",
            layout_width = "0dp",
            layout_weight = 1,
            {
              MaterialTextView,
              text = S.ai_auto_approve_network,
              textSize = "14sp", textColor = ColorOnSurface,
            },
            {
              MaterialTextView,
              text = S.ai_auto_approve_network_desc,
              textSize = "12sp", textColor = ColorText,
              layout_marginTop = "2dp",
            },
          },
          {
            Switch,
            id = "autoApproveNetworkSwitch",
            checked = autoApproveNetwork,
            layout_marginLeft = "12dp",
          },
        },
        {
          LinearLayout,
          orientation = "horizontal",
          gravity = "center_vertical",
          layout_width = "match",
          layout_height = "wrap",
          layout_marginTop = "12dp",
          {
            LinearLayout,
            orientation = "vertical",
            layout_width = "0dp",
            layout_weight = 1,
            {
              MaterialTextView,
              text = S.ai_auto_approve,
              textSize = "14sp", textColor = ColorOnSurface,
            },
            {
              MaterialTextView,
              text = S.ai_auto_approve_desc,
              textSize = "12sp", textColor = ColorText,
              layout_marginTop = "2dp",
            },
          },
          {
            Switch,
            id = "autoApproveSwitch",
            checked = autoApprove,
            layout_marginLeft = "12dp",
          },
        },
        {
          LinearLayout,
          orientation = "horizontal",
          gravity = "center_vertical",
          layout_width = "match",
          layout_height = "wrap",
          layout_marginTop = "12dp",
          {
            LinearLayout,
            orientation = "vertical",
            layout_width = "0dp",
            layout_weight = 1,
            {
              MaterialTextView,
              text = S.ai_self_signed,
              textSize = "14sp", textColor = ColorOnSurface,
            },
            {
              MaterialTextView,
              text = S.ai_self_signed_desc,
              textSize = "12sp", textColor = ColorText,
              layout_marginTop = "2dp",
            },
          },
          {
            Switch,
            id = "selfSignedSwitch",
            checked = allowSelfSigned,
            layout_marginLeft = "12dp",
          },
        },
      },
    },
    -- 当前工程策略（只能收紧全局授权）
    {
      MaterialCardView,
      layout_width = "match",
      layout_height = "wrap",
      layout_marginBottom = "12dp",
      CardBackgroundColor = ColorSurface,
      CardElevation = 0,
      {
        LinearLayout,
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        padding = "16dp",
        sectionTitle(S.ai_policy_project),
        {
          LinearLayout,
          orientation = "horizontal",
          gravity = "center_vertical",
          layout_width = "match",
          layout_height = "wrap",
          {
            LinearLayout,
            orientation = "vertical",
            layout_width = "0dp",
            layout_weight = 1,
            {
              MaterialTextView,
              text = S.ai_policy_restrict,
              textSize = "14sp", textColor = ColorOnSurface,
            },
            {
              MaterialTextView,
              text = S.ai_policy_restrict_desc,
              textSize = "12sp", textColor = ColorText,
              layout_marginTop = "2dp",
            },
          },
          {
            Switch,
            id = "policyRestrictSwitch",
            checked = policyRestricted,
            layout_marginLeft = "12dp",
          },
        },
        {
          MaterialTextView,
          text = S.ai_policy_hosts,
          textSize = "14sp", textColor = ColorOnSurface,
          layout_marginTop = "12dp",
          layout_marginBottom = "2dp",
        },
        {
          MaterialTextView,
          text = S.ai_policy_hosts_desc,
          textSize = "12sp", textColor = ColorText,
          layout_marginBottom = "4dp",
        },
        {
          EditText,
          id = "policyHostsInput",
          text = policyHosts,
          layout_width = "match", layout_height = "wrap",
          textSize = "13sp", minLines = 1, maxLines = 4,
          hint = "api.example.com docs.example.org",
        },
      },
    },
    -- 系统提示词
    {
      MaterialCardView,
      layout_width = "match",
      layout_height = "wrap",
      layout_marginBottom = "12dp",
      CardBackgroundColor = ColorSurface,
      CardElevation = 0,
      {
        LinearLayout,
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        padding = "16dp",
        sectionTitle(S.ai_advanced),
        {
          MaterialTextView,
          text = S.ai_system_prompt,
          textSize = "14sp", textColor = ColorOnSurface,
          layout_marginBottom = "2dp",
        },
        {
          MaterialTextView,
          text = S.ai_sys_prompt_desc,
          textSize = "12sp", textColor = ColorText,
          layout_marginBottom = "4dp",
        },
        {
          EditText,
          id = "promptInput",
          text = systemPrompt,
          layout_width = "match", layout_height = "wrap",
          textSize = "13sp", minLines = 3, maxLines = 6,
          gravity = "top",
        },
      },
    },
    -- MCP 服务器
    {
      MaterialCardView,
      layout_width = "match",
      layout_height = "wrap",
      layout_marginBottom = "12dp",
      CardBackgroundColor = ColorSurface,
      CardElevation = 0,
      {
        LinearLayout,
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        padding = "16dp",
        sectionTitle(S.ai_mcp_servers),
        {
          MaterialTextView,
          text = S.ai_mcp_desc,
          textSize = "12sp", textColor = ColorText,
          layout_marginBottom = "6dp",
        },
        {
          LinearLayout,
          id = "mcpList",
          orientation = "vertical",
          layout_width = "match",
          layout_height = "wrap",
        },
        {
          MaterialButton,
          id = "btnAddMcp",
          text = S.ai_add_mcp,
          textSize = "13sp",
          layout_width = "match",
          layout_marginTop = "8dp",
          includeFontPadding = false,
          BackgroundTintList = ColorStateList.valueOf(ColorPrimary),
          textColor = ColorOnPrimary,
        },
        {
          LinearLayout,
          orientation = "horizontal",
          layout_width = "match",
          layout_height = "wrap",
          layout_marginTop = "8dp",
          {
            MaterialButton,
            id = "btnAddCtx7",
            text = S.ai_add_ctx7,
            textSize = "13sp",
            layout_width = "0dp", layout_weight = 1,
            layout_marginRight = "6dp",
            includeFontPadding = false,
            BackgroundTintList = ColorStateList.valueOf(ColorSecondaryContainer),
            textColor = ColorOnSecondaryContainer,
          },
          {
            MaterialButton,
            id = "btnAddDw",
            text = S.ai_add_dw,
            textSize = "13sp",
            layout_width = "0dp", layout_weight = 1,
            layout_marginLeft = "6dp",
            includeFontPadding = false,
            BackgroundTintList = ColorStateList.valueOf(ColorSecondaryContainer),
            textColor = ColorOnSecondaryContainer,
          },
        },
      },
    },
    {
      MaterialButton,
      id = "btnTestConn",
      text = S.ai_test_conn,
      textSize = "13sp",
      layout_width = "match",
      includeFontPadding = false,
      BackgroundTintList = ColorStateList.valueOf(ColorPrimary),
      textColor = ColorOnPrimary,
    },
  }

  local content = loadlayout({
    ScrollView,
    layout_width = "match",
    layout_height = "match",
    fillViewport = true,
    body,
  }, dlgViews)

  dlgViews.btnTestConn.onClick = function()
    AgentChat.testConnection(function(ok, msg)
      print(msg)
    end)
  end

  -- ─── MCP 服务器管理 ──

  local function renderMcpList()
    mcpRenderGeneration = mcpRenderGeneration + 1
    local renderGeneration = mcpRenderGeneration
    local mcpList = dlgViews.mcpList
    if not mcpList then return end
    mcpList.removeAllViews()
    local servers = MCPClient.getServers()
    for i, server in ipairs(servers) do
      local serverItem = server
      local sname = tostring(server.name or S.ai_unnamed)
      local surl = tostring(server.url or "")
      local row = LinearLayout(activity)
      row.setOrientation(1)
      row.setPadding(dp(12), dp(10), dp(12), dp(10))
      local lp = LinearLayout.LayoutParams(-1, -2)
      lp.bottomMargin = dp(8)
      row.setLayoutParams(lp)
      local bg = GradientDrawable()
      bg.setColor(ColorSurfaceContainerHigh)
      bg.setCornerRadius(dp(12))
      row.setBackground(bg)

      local txtCol = LinearLayout(activity)
      txtCol.setOrientation(1)
      txtCol.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
      local nameTv = MaterialTextView(activity)
      nameTv.setText(sname)
      nameTv.setTextSize(14)
      nameTv.setTypeface(Typeface.DEFAULT, 1)
      nameTv.setTextColor(ColorOnSurface)
      nameTv.setSingleLine(true)
      txtCol.addView(nameTv)
      local urlTv = MaterialTextView(activity)
      urlTv.setText(surl)
      urlTv.setTextSize(12)
      urlTv.setTextColor(ColorText)
      urlTv.setSingleLine(true)
      txtCol.addView(urlTv)
      local statusTv = MaterialTextView(activity)
      statusTv.setText("")
      statusTv.setTextSize(11)
      statusTv.setTextColor(ColorText)
      statusTv.setVisibility(GONE)
      txtCol.addView(statusTv)
      row.addView(txtCol)

      local function mcpBtn(text, bgColor, textColor)
        local btn = MaterialButton(activity)
        btn.setText(text)
        btn.setTextSize(12)
        btn.setAllCaps(false)
        btn.setMinWidth(0)
        btn.setMinHeight(0)
        btn.setPadding(dp(14), 0, dp(14), 0)
        btn.setBackgroundTintList(ColorStateList.valueOf(bgColor))
        btn.setTextColor(textColor)
        return btn
      end

      local actions = LinearLayout(activity)
      actions.setOrientation(0)
      actions.setGravity(5) -- Gravity.RIGHT
      local actionsLp = LinearLayout.LayoutParams(-1, -2)
      actionsLp.topMargin = dp(8)
      actions.setLayoutParams(actionsLp)

      local testBtn = mcpBtn(S.ai_test, ColorSecondaryContainer, ColorOnSecondaryContainer)
      local testLp = LinearLayout.LayoutParams(-2, dp(34))
      testLp.rightMargin = dp(8)
      testBtn.setLayoutParams(testLp)
      testBtn.setOnClickListener(function()
        testBtn.setEnabled(false)
        testBtn.setText(S.ai_mcp_testing)
        statusTv.setText(S.ai_mcp_testing)
        statusTv.setTextColor(ColorText)
        statusTv.setVisibility(VISIBLE)
        MCPClient.testServerAsync(serverItem, function(ok, msg)
          if renderGeneration ~= mcpRenderGeneration
              or not settingsDialog or not settingsDialog.isShowing() then return end
          pcall(function()
            testBtn.setEnabled(true)
            testBtn.setText(S.ai_test)
            statusTv.setText(ok and S.ai_mcp_connected or S.ai_mcp_failed)
            statusTv.setTextColor(ok and ColorPrimary or ColorError)
            local feedback = tostring(msg or (ok and S.ai_mcp_connected or S.ai_mcp_failed))
            print(sname .. ": " .. feedback)
          end)
        end)
      end)
      actions.addView(testBtn)

      local delBtn = mcpBtn(S.ai_delete, ColorErrorContainer, ColorOnErrorContainer)
      local delLp = LinearLayout.LayoutParams(-2, dp(34))
      delBtn.setLayoutParams(delLp)
      delBtn.setOnClickListener(function()
        local compact = {}
        for idx, s in ipairs(servers) do
          if idx ~= i then compact[#compact + 1] = s end
        end
        MCPClient.setServers(compact)
        MCPClient.refreshToolsAsync()
        renderMcpList()
      end)
      actions.addView(delBtn)
      row.addView(actions)
      mcpList.addView(row)
    end
  end

  dlgViews.btnAddMcp.onClick = function()
    local inViews = {}
    local form = {
      LinearLayout,
      orientation = "vertical",
      padding = "20dp",
      {
        EditText,
        id = "nameInput",
        hint = S.ai_name_hint,
        layout_width = "match", layout_height = "wrap", minHeight = "42dp",
        textSize = "14sp", singleLine = true,
      },
      {
        EditText,
        id = "urlInput",
        hint = S.ai_url_hint,
        layout_width = "match", layout_height = "wrap", minHeight = "42dp",
        textSize = "14sp", singleLine = true,
        layout_marginTop = "8dp",
      },
      {
        EditText,
        id = "headerInput",
        hint = S.ai_headers_hint,
        layout_width = "match", layout_height = "wrap",
        textSize = "13sp", minLines = 2, maxLines = 4,
        gravity = "top",
        layout_marginTop = "8dp",
      },
    }
    local formContent = loadlayout({
      ScrollView, layout_width = "match", layout_height = "wrap", fillViewport = true,
      form,
    }, inViews)
    local addDialog = MaterialAlertDialogBuilder(activity)
      .setTitle(S.ai_add_mcp)
      .setView(formContent)
      .setPositiveButton(S.ai_ok, nil)
      .setNegativeButton(S.ai_cancel, nil)
      .create()
    addDialog.setOnShowListener(function()
      local positive = addDialog.getButton(DialogInterface.BUTTON_POSITIVE)
      if not positive then return end
      positive.onClick = function()
        local sname = tostring(inViews.nameInput.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
        local surl = tostring(inViews.urlInput.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
        local sheaders = tostring(inViews.headerInput.getText() or "")
        if sname == "" or surl == "" then
          print(S.ai_name_url_required)
          return
        end
        local headers = {}
        for line in sheaders:gmatch("[^\r\n]+") do
          local k, v = line:match("^%s*([^:%s]+)%s*:%s*(.*)%s*$")
          if k then headers[k] = v end
        end
        local valid = MCPClient.validateServer({ url = surl, headers = headers })
        if not valid then
          print(S.ai_mcp_url_invalid)
          return
        end
        local servers = MCPClient.getServers()
        servers[#servers + 1] = { name = sname, url = surl, headers = headers }
        MCPClient.setServers(servers)
        MCPClient.refreshToolsAsync()
        renderMcpList()
        addDialog.dismiss()
      end
    end)
    addDialog.show()
  end

  local function addPresetServer(name, url)
    local servers = MCPClient.getServers()
    for _, s in ipairs(servers) do
      if tostring(s.name or "") == name then
        print(S.ai_exists:format(name))
        return
      end
    end
    servers[#servers + 1] = { name = name, url = url, headers = {} }
    MCPClient.setServers(servers)
    MCPClient.refreshToolsAsync()
    renderMcpList()
  end

  dlgViews.btnAddCtx7.onClick = function()
    addPresetServer("context7", "https://mcp.context7.com/mcp")
  end
  dlgViews.btnAddDw.onClick = function()
    addPresetServer("deepwiki", "https://mcp.deepwiki.com/mcp")
  end

  local function renderAuxModelValue()
    if not dlgViews.auxModelValue then return end
    local models = AgentChat.loadModels()
    local idx = AgentChat.getAuxModelIndex()
    if idx >= 1 and models[idx] then
      dlgViews.auxModelValue.setText(S.ai_aux_model_set:format(models[idx].name))
    else
      dlgViews.auxModelValue.setText(S.ai_aux_model_follow)
    end
  end
  renderAuxModelValue()

  dlgViews.auxModelValue.onClick = function()
    local models = AgentChat.loadModels()
    if #models == 0 then
      print(S.ai_need_config)
      return
    end
    local currentAux = AgentChat.getAuxModelIndex()
    local labels = {}
    for i, m in ipairs(models) do
      local marker = (i == currentAux) and " ✓ " or "    "
      labels[i] = marker .. m.name .. "  (" .. m.model .. ")"
    end
    labels[#labels + 1] = "    " .. S.ai_aux_model_clear
    MaterialAlertDialogBuilder(activity)
      .setTitle(S.ai_aux_model)
      .setItems(labels, function(_, which)
        if which == #models then
          AgentChat.setAuxModelIndex(0)
        else
          AgentChat.setAuxModelIndex(which + 1)
        end
        renderAuxModelValue()
      end)
      .setNegativeButton(S.ai_close, nil)
      .show()
  end

  renderMcpList()

  settingsDialog = MaterialAlertDialogBuilder(activity)
    .setTitle(S.ai_settings)
    .setView(content)
    .setPositiveButton(S.ai_ok, function()
      this.setSharedData("ai_auto_approve", dlgViews.autoApproveSwitch.isChecked() and "1" or "0")
      this.setSharedData("ai_auto_approve_network", dlgViews.autoApproveNetworkSwitch.isChecked() and "1" or "0")
      this.setSharedData("ai_auto_run_sandbox", dlgViews.autoRunSandboxSwitch.isChecked() and "1" or "0")
      this.setSharedData("ai_allow_selfsigned", dlgViews.selfSignedSwitch.isChecked() and "1" or "0")
      local tempVal = tostring(dlgViews.tempInput.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
      local retryVal = tostring(dlgViews.retryInput.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
      local promptVal = tostring(dlgViews.promptInput.getText() or "")
      if tempVal ~= "" then this.setSharedData("ai_temperature", tempVal) end
      if retryVal ~= "" then this.setSharedData("ai_retry_count", retryVal) end
      this.setSharedData("ai_system_prompt", promptVal)
      if dlgViews.policyRestrictSwitch and dlgViews.policyHostsInput then
        local hosts = {}
        local hostsRaw = tostring(dlgViews.policyHostsInput.getText() or "")
        for token in hostsRaw:gmatch("[^,;%s]+") do hosts[#hosts + 1] = token end
        pcall(function()
          AgentChat.saveProjectPolicy({
            autoApprove = not dlgViews.policyRestrictSwitch.isChecked(),
            networkHosts = hosts,
          })
        end)
      end
      print(S.ai_settings_saved)
    end)
    .setNegativeButton(S.ai_cancel, nil)
    .show()
  settingsDialog.setOnDismissListener(function()
    mcpRenderGeneration = mcpRenderGeneration + 1
  end)
end

-- ─── 会话管理 ──

local CONV_COLORS = {
  0xFF7C4DFF, 0xFF536DFE, 0xFF448AFF, 0xFF00BFA5,
  0xFF00C853, 0xFFFFB300, 0xFFFF6E40, 0xFFE040FB,
  0xFFF50057, 0xFF26A69A,
}

local function convColor(name)
  local s = tostring(name or "")
  local h = 0
  for i = 1, #s do h = (h * 31 + s:byte(i)) % 65536 end
  return CONV_COLORS[(h % #CONV_COLORS) + 1]
end

local function makeAvatar(name, sizeDp)
  local size = dp(sizeDp)
  local tv = MaterialTextView(activity)
  local s = tostring(name or "?")
  local ok, first = pcall(function() return utf8.sub(s, 1, 1) end)
  if not ok or first == nil or first == "" then
    first = s:sub(1, 1) or "?"
  end
  tv.setText(first)
  tv.setTextSize(16)
  tv.setTextColor(0xffffffff)
  tv.setGravity(17)
  tv.setTypeface(Typeface.DEFAULT, 1)
  local gd = GradientDrawable()
  gd.setShape(GradientDrawable.OVAL)
  gd.setColor(convColor(name))
  tv.setBackground(gd)
  tv.setLayoutParams(LinearLayout.LayoutParams(size, size))
  return tv
end

local function convMetaText(conv)
  local project = tostring(conv.projectPath or ""):match("([^/]+)$") or S.ai_project_unknown
  return S.ai_conv_meta:format(tostring(conv.createdAt or ""), #(conv.messages or {})) .. "  ·  " .. project
end

updateProjectLabel = function()
  if not views.aiProject then return end
  local path = AgentChat.getCurrentProjectPath()
  local project = tostring(path or ""):match("([^/]+)$") or S.ai_project_unknown
  views.aiProject.setText(S.ai_project:format(project))
end

local function showRenameDialog(convId, oldName)
  local dlgViews = {}
  local inputLayout = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    padding = "16dp",
    {
      EditText,
      id = "nameInput",
      layout_width = "match", layout_height = "wrap", minHeight = "48dp",
      textSize = "14sp", singleLine = true,
      text = oldName,
    },
  }
  local content = loadlayout(inputLayout, dlgViews)

  MaterialAlertDialogBuilder(activity)
    .setTitle(S.ai_rename)
    .setView(content)
    .setPositiveButton(S.ai_ok, function()
      local name = tostring(dlgViews.nameInput.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
      if name ~= "" and convId then
        AgentChat.renameConversation(convId, name)
        local c = AgentChat.getCurrentConv()
        if views.aiTitle and c and c.id == convId then
          views.aiTitle.setText(convName(c))
        end
      end
    end)
    .setNegativeButton(S.ai_cancel, nil)
    .show()
end

local function buildConvRow(conv, isCurrent, onClick)
  local name = convName(conv)
  local rowViews = {}
  local row = loadlayout({
    LinearLayout,
    layout_width = "match",
    layout_height = "wrap",
    orientation = "horizontal",
    gravity = "center_vertical",
    clickable = true,
    focusable = true,
    layout_marginBottom = "8dp",
    paddingLeft = "14dp",
    paddingRight = "14dp",
    paddingTop = "10dp",
    paddingBottom = "10dp",
    {
      LinearLayout,
      id = "avatarSlot",
      layout_width = "wrap",
      layout_height = "wrap",
    },
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "0dp",
      layout_weight = 1,
      layout_height = "wrap",
      layout_marginLeft = "12dp",
      layout_marginRight = "6dp",
      {
        MaterialTextView,
        text = name,
        textSize = "15sp",
        textStyle = "bold",
        textColor = isCurrent and ColorOnPrimaryContainer or ColorOnSurface,
        singleLine = true,
        ellipsize = "end",
      },
      {
        MaterialTextView,
        text = convMetaText(conv),
        textSize = "12sp",
        textColor = isCurrent and ColorOnPrimaryContainer or ColorText,
        singleLine = true,
        ellipsize = "end",
        layout_marginTop = "2dp",
      },
    },
    {
      MaterialTextView,
      id = "badge",
      textSize = "11sp",
      gravity = "center",
      singleLine = true,
      visibility = (isCurrent or conv.running) and VISIBLE or GONE,
      layout_width = "wrap",
      layout_height = "24dp",
    },
  }, rowViews)

  local bg = GradientDrawable()
  bg.setCornerRadius(dp(16))
  bg.setColor(isCurrent and ColorPrimaryContainer or ColorSurfaceContainerLow)
  row.setBackground(bg)

  rowViews.avatarSlot.addView(makeAvatar(name, 40))

  local badge = rowViews.badge
  if isCurrent then
    badge.setText(S.ai_current)
    badge.setTextColor(ColorOnPrimary)
    local bbg = GradientDrawable()
    bbg.setShape(GradientDrawable.OVAL)
    bbg.setColor(ColorPrimary)
    badge.setBackground(bbg)
  elseif conv.running then
    -- 该会话有任务进行中（进程被杀后标记可能残留，仅作提示）
    badge.setText(S.ai_conv_running)
    badge.setTextColor(ColorOnErrorContainer)
    local rbg = GradientDrawable()
    rbg.setCornerRadius(dp(8))
    rbg.setColor(ColorErrorContainer)
    badge.setBackground(rbg)
    badge.setPadding(dp(8), 0, dp(8), 0)
  end

  row.setOnClickListener(function() if onClick then onClick() end end)
  return row
end

local function buildManagerRow(conv, render)
  local name = convName(conv)
  local convId = conv and conv.id
  local rowViews = {}
  local row = loadlayout({
    LinearLayout,
    layout_width = "match",
    layout_height = "wrap",
    orientation = "horizontal",
    gravity = "center_vertical",
    layout_marginBottom = "8dp",
    paddingLeft = "12dp",
    paddingRight = "12dp",
    paddingTop = "8dp",
    paddingBottom = "8dp",
    {
      LinearLayout,
      id = "avatarSlot",
      layout_width = "wrap",
      layout_height = "wrap",
    },
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "0dp",
      layout_weight = 1,
      layout_height = "wrap",
      layout_marginLeft = "10dp",
      layout_marginRight = "4dp",
      {
        MaterialTextView,
        text = name,
        textSize = "15sp",
        textColor = ColorOnSurface,
        singleLine = true,
        ellipsize = "end",
      },
      {
        MaterialTextView,
        text = convMetaText(conv),
        textSize = "12sp",
        textColor = ColorText,
        singleLine = true,
        ellipsize = "end",
        layout_marginTop = "2dp",
      },
      {
        LinearLayout,
        layout_width = "match",
        layout_height = "wrap",
        gravity = "end",
        layout_marginTop = "6dp",
        {
          MaterialButton,
          text = S.ai_rename_btn,
          textSize = "12sp",
          layout_width = "wrap",
          layout_height = "wrap",
          allCaps = false,
          minWidth = 0,
          minHeight = 0,
          paddingLeft = "12dp",
          paddingRight = "12dp",
          BackgroundTintList = ColorStateList.valueOf(ColorSecondaryContainer),
          textColor = ColorOnSecondaryContainer,
          onClick = function() showRenameDialog(convId, name) end,
        },
        {
          MaterialButton,
          text = S.ai_delete,
          textSize = "12sp",
          layout_width = "wrap",
          layout_height = "wrap",
          layout_marginLeft = "8dp",
          allCaps = false,
          minWidth = 0,
          minHeight = 0,
          paddingLeft = "12dp",
          paddingRight = "12dp",
          BackgroundTintList = ColorStateList.valueOf(ColorErrorContainer),
          textColor = ColorOnErrorContainer,
          onClick = function()
            MaterialAlertDialogBuilder(activity)
              .setTitle(S.ai_delete_conv)
              .setMessage(S.ai_confirm_delete_conv:format(name))
              .setPositiveButton(S.ai_delete, function()
                AgentTurn.invalidate()
                if not AgentChat.deleteConversation(convId) then
                  print(S.ai_delete_failed)
                  return
                end
                local current = AgentChat.getCurrentConv()
                if not current then
                  AgentChat.createConversation()
                end
                messages = {}
                if views.msgContainer then views.msgContainer.removeAllViews() end
                loadHistory()
                if views.aiTitle then
                  local c = AgentChat.getCurrentConv()
                  if c then views.aiTitle.setText(convName(c)) end
                end
                print(S.ai_deleted)
                render()
              end)
              .setNegativeButton(S.ai_cancel, nil)
              .show()
          end,
        },
      },
    },
  }, rowViews)

  rowViews.avatarSlot.addView(makeAvatar(name, 36))
  return row
end

-- 统一的会话切换序列（面板内列表、首屏 chips 与对外 openConversation 共用）
local function switchToConversation(conv)
  saveHistory()
  AgentTurn.invalidate()
  AgentChat.setCurrentConv(conv.id)
  activeConversationId = conv.id
  activeConversationProjectPath = AgentChat.getCurrentProjectPath()
  conversationLoaded = true
  activeConversationHadMessages = false
  messages = {}
  if views.msgContainer then views.msgContainer.removeAllViews() end
  loadHistory()
  if views.aiTitle then views.aiTitle.setText(convName(conv)) end
  if updateProjectLabel then updateProjectLabel() end
end

-- 赋值给前向声明的局部量：命令菜单捕获的是声明处的变量，
-- 若在此重新 local 声明，菜单入口会调用到 nil（历史 bug）
showConvList = function()
  local list = AgentChat.listConversations()
  local currentConv = AgentChat.getCurrentConv()
  local currentId = currentConv and currentConv.id or nil
  -- 会话中心按最近更新排序，进行中的任务自然靠前
  table.sort(list, function(a, b)
    return tostring(a.conversation.updatedAt or "") > tostring(b.conversation.updatedAt or "")
  end)

  if #list == 0 then
    local created = AgentChat.createConversation()
    activeConversationId = created and created.id or nil
    activeConversationProjectPath = created and AgentChat.getCurrentProjectPath() or nil
    conversationLoaded = created ~= nil
    activeConversationHadMessages = false
    messages = created and created.messages or {}
    TodoManager.set(nil)
    if views.msgContainer then views.msgContainer.removeAllViews() end
    if views.aiTitle then views.aiTitle.setText(S.ai_new_conv) end
    if updateProjectLabel then updateProjectLabel() end
    return
  end

  local dlgViews = {}
  local dlg = nil
  local content = loadlayout({
    ScrollView,
    layout_width = "match",
    layout_height = "match",
    fillViewport = true,
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      padding = "12dp",
      {
        LinearLayout,
        orientation = "horizontal",
        gravity = "center_vertical",
        layout_width = "match",
        layout_height = "wrap",
        padding = "8dp",
        paddingBottom = "2dp",
        {
          MaterialTextView,
          text = S.ai_switch_conv,
          textSize = "18sp", textStyle = "bold", textColor = ColorOnSurface,
          layout_width = "0dp", layout_weight = 1,
        },
        {
          MaterialTextView,
          id = "convCount",
          text = S.ai_conv_count:format(#list),
          textSize = "13sp", textColor = ColorText,
        },
      },
      {
        LinearLayout,
        id = "convList",
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        layout_marginTop = "2dp",
      },
      {
        LinearLayout,
        orientation = "horizontal",
        layout_width = "match",
        layout_height = "wrap",
        layout_marginTop = "4dp",
        {
          MaterialButton,
          id = "btnManage",
          text = S.ai_manage_convs,
          textSize = "14sp",
          layout_width = "0dp", layout_weight = 1,
          layout_marginRight = "6dp",
          BackgroundTintList = ColorStateList.valueOf(ColorSecondaryContainer),
          textColor = ColorOnSecondaryContainer,
        },
        {
          MaterialButton,
          id = "btnNew",
          text = S.ai_new_conv_btn,
          textSize = "14sp",
          layout_width = "0dp", layout_weight = 1,
          layout_marginLeft = "6dp",
          BackgroundTintList = ColorStateList.valueOf(ColorPrimary),
          textColor = ColorOnPrimary,
        },
      },
    },
  }, dlgViews)

  local container = dlgViews.convList
  container.removeAllViews()
  for _, item in ipairs(list) do
    local conv = item.conversation
    local row = buildConvRow(conv, conv.id == currentId, function()
      switchToConversation(conv)
      if dlg then dlg.dismiss() end
    end)
    container.addView(row)
  end

  dlgViews.btnManage.onClick = function()
    if dlg then dlg.dismiss() end
    showConvManager()
  end
  dlgViews.btnNew.onClick = function()
    saveHistory()
    AgentTurn.invalidate()
    local created = AgentChat.createConversation()
    activeConversationId = created and created.id or nil
    activeConversationProjectPath = created and AgentChat.getCurrentProjectPath() or nil
    conversationLoaded = created ~= nil
    activeConversationHadMessages = false
    messages = {}
    if views.msgContainer then views.msgContainer.removeAllViews() end
    if views.aiTitle then views.aiTitle.setText(S.ai_new_conv) end
    if updateProjectLabel then updateProjectLabel() end
    if dlg then dlg.dismiss() end
  end

  dlg = MaterialAlertDialogBuilder(activity)
    .setView(content)
    .setNegativeButton(S.ai_close, nil)
    .show()
end

showConvManager = function()
  local list = AgentChat.listConversations()
  if #list == 0 then return end

  local dlgViews = {}
  local content = loadlayout({
    ScrollView,
    layout_width = "match",
    layout_height = "match",
    fillViewport = true,
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      padding = "12dp",
      {
        LinearLayout,
        orientation = "horizontal",
        gravity = "center_vertical",
        layout_width = "match",
        layout_height = "wrap",
        padding = "8dp",
        paddingBottom = "2dp",
        {
          MaterialTextView,
          text = S.ai_manage_convs,
          textSize = "18sp", textStyle = "bold", textColor = ColorOnSurface,
          layout_width = "0dp", layout_weight = 1,
        },
        {
          MaterialTextView,
          id = "convCount",
          text = S.ai_conv_count:format(#list),
          textSize = "13sp", textColor = ColorText,
        },
      },
      {
        LinearLayout,
        id = "convList",
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        layout_marginTop = "2dp",
      },
      {
        MaterialButton,
        id = "btnNew",
        text = S.ai_new_conv_btn,
        textSize = "14sp",
        layout_width = "match",
        layout_marginTop = "4dp",
        BackgroundTintList = ColorStateList.valueOf(ColorPrimary),
        textColor = ColorOnPrimary,
      },
    },
  }, dlgViews)

  local container = dlgViews.convList
  local function render()
    local currentList = AgentChat.listConversations()
    container.removeAllViews()
    for _, item in ipairs(currentList) do
      container.addView(buildManagerRow(item.conversation, render))
    end
    if dlgViews.convCount then dlgViews.convCount.setText(S.ai_conv_count:format(#currentList)) end
  end

  dlgViews.btnNew.onClick = function()
    saveHistory()
    AgentTurn.invalidate()
    local created = AgentChat.createConversation()
    activeConversationId = created and created.id or nil
    activeConversationProjectPath = created and AgentChat.getCurrentProjectPath() or nil
    conversationLoaded = created ~= nil
    activeConversationHadMessages = false
    messages = {}
    TodoManager.set(nil)
    if views.msgContainer then views.msgContainer.removeAllViews() end
    if views.aiTitle then views.aiTitle.setText(S.ai_new_conv) end
    render()
  end

  render()
  MaterialAlertDialogBuilder(activity)
    .setView(content)
    .setNegativeButton(S.ai_close, nil)
    .show()
end

local function addWelcomeCard(title, body)
  if not views.msgContainer then return end
  local welcomeViews = {}
  local welcome = {
    MaterialCardView,
    radius = "16dp",
    CardElevation = 0,
    strokeWidth = "0dp",
    CardBackgroundColor = ColorSurfaceContainerLow,
    layout_width = "match",
    layout_height = "wrap",
    {
      LinearLayout,
      orientation = "vertical",
      padding = "16dp",
      {
        MaterialTextView,
        text = title,
        textSize = "14sp",
        textStyle = "bold",
        textColor = ColorOnSurface,
      },
      {
        MaterialTextView,
        text = body,
        textSize = "13sp",
        textColor = ColorText,
        layout_marginTop = "5dp",
        lineSpacingMultiplier = 1.3,
      },
      {
        MaterialButton,
        id = "btnWelcomeHelp",
        text = S.ai_agent_help,
        layout_width = "wrap",
        layout_marginTop = "8dp",
      },
      {
        LinearLayout,
        orientation = "horizontal",
        layout_width = "match",
        layout_marginTop = "4dp",
        {
          MaterialButton,
          id = "btnWelcomeExplain",
          text = S.ai_welcome_explain,
          layout_width = "0dp", layout_weight = 1,
          layout_marginRight = "4dp",
        },
        {
          MaterialButton,
          id = "btnWelcomeCheck",
          text = S.ai_welcome_check,
          layout_width = "0dp", layout_weight = 1,
          layout_marginLeft = "4dp",
        },
      },
    },
  }
  local welcomeCard = loadlayout(welcome, welcomeViews)
  local welcomeLp = LinearLayout.LayoutParams(-1, -2)
  welcomeLp.bottomMargin = dp(12)
  views.msgContainer.addView(welcomeCard, welcomeLp)
  welcomeViews.btnWelcomeHelp.onClick = function() showAgentHelp() end
  welcomeViews.btnWelcomeExplain.onClick = function()
    if not (Bean and Bean.Path and Bean.Path.this_file) then
      print(S.ai_need_open_file)
    elseif views.msgInput then
      views.msgInput.setText(S.ai_welcome_explain_prompt)
      sendMessage()
    end
  end
  welcomeViews.btnWelcomeCheck.onClick = function()
    if views.msgInput then
      views.msgInput.setText(S.ai_welcome_check_prompt)
      sendMessage()
    end
  end
end

local function clearChat()
  AgentTurn.invalidate()
  messages = {}
  activeConversationHadMessages = false
  if conversationLoaded and activeConversationId and activeConversationId ~= ""
      and activeConversationProjectPath == AgentChat.getCurrentProjectPath()
      and AgentChat.clearConversation then
    AgentChat.clearConversation(activeConversationId)
  end
  if views.msgContainer then
    views.msgContainer.removeAllViews()
    addWelcomeCard(S.ai_welcome_title, S.ai_welcome_body)
  end
end

-- ─── 展开 BottomSheet ──

local function expandSheet(dlg, content)
  if not dlg then return end
  pcall(function()
    local window = dlg.getWindow()
    if window then
      local wlp = window.getAttributes()
      wlp.height = -1  -- MATCH_PARENT 撑满到底部
      wlp.gravity = 80
      window.setAttributes(wlp)
    end

    local sheet
    local mid = activity.getResources().getIdentifier("design_bottom_sheet", "id", activity.getPackageName())
    if mid == 0 then
      mid = activity.getResources().getIdentifier("design_bottom_sheet", "id", "com.google.android.material")
    end
    if mid ~= 0 then sheet = dlg.findViewById(mid) end
    if not sheet and content then
      pcall(function() sheet = content.getParent() end)
    end
    if not sheet then return end

    local behavior = BottomSheetBehavior.from(sheet)
    if behavior then
      pcall(function() behavior.setSkipCollapsed(true) end)
      pcall(function() behavior.setDraggable(false) end)
      behavior.setState(BottomSheetBehavior.STATE_EXPANDED)
    end
  end)
end

local function hideEditorKeyboard()
  local focused = activity.getCurrentFocus()
  if not focused then return end
  pcall(function()
    local imm = activity.getSystemService("input_method")
    if imm then imm.hideSoftInputFromWindow(focused.getWindowToken(), 0) end
  end)
end

-- ─── 显示聊天面板 ──

function _M.show()
  if dialog and dialog.isShowing() then
    saveHistory()
    dialog.dismiss()
  end

  views = {}
  local content = loadlayout(res.layout.ai_chat_panel, views)
  -- The editor may still own the IME while its symbol bar is visible. Hide it
  -- before measuring the full-height sheet so the first expansion uses the
  -- activity height rather than the keyboard-reduced editor area.
  hideEditorKeyboard()

  -- 后台预取 MCP 工具缓存（避免主线程同步网络请求）
  pcall(function()
    if MCPClient and MCPClient.refreshToolsAsync then
      MCPClient.refreshToolsAsync()
    end
  end)

  dialog = BottomSheetDialog(activity)
  dialog.setContentView(content)

  -- 去掉底部间距
  pcall(function()
    local window = dialog.getWindow()
    if window then
      window.getAttributes().gravity = 80  -- Gravity.BOTTOM
      window.setBackgroundDrawableResource(android.R.color.transparent)
      window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN
        | WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    end
  end)

  -- 关闭面板只保存会话，不取消后台请求；停止按钮和上下文切换负责取消。
  dialog.setOnDismissListener(function()
    saveHistory()
  end)

  if views.btnSend then
    views.btnSend.onClick = function() sendMessage() end
  end

  if views.btnCommands then
    views.btnCommands.onClick = function() showCommandMenu() end
  end

  -- 停止按钮
  if views.btnStop then
    views.btnStop.onClick = function()
      views.btnStop.setEnabled(false)
      -- Keep this generation alive until the cancel callback stores partial text.
      AgentTurn.requestStop()
    end
  end

  -- 设置按钮
  if views.btnSettings then
    views.btnSettings.onClick = function() showSettings() end
  end

  -- 模型标签点击切换
  if views.modelChip then
    views.modelChip.onClick = function() showModelPicker() end
  end

  if views.btnClear then
    views.btnClear.onClick = function()
      AgentTurn.invalidate()
      saveHistory()
      local created = AgentChat.createConversation()
      activeConversationId = created and created.id or nil
      activeConversationProjectPath = created and AgentChat.getCurrentProjectPath() or nil
      conversationLoaded = created ~= nil
      activeConversationHadMessages = false
      messages = {}
      TodoManager.set(nil)
      if views.msgContainer then views.msgContainer.removeAllViews() end
      if views.aiTitle then views.aiTitle.setText(S.ai_new_conv) end
      addWelcomeCard(S.ai_new_conv, S.ai_start_chat)
    end
  end

  -- 标题点击切换会话
  if views.aiTitle then
    views.aiTitle.setContentDescription(S.ai_cd_switch_conv)
    views.aiTitle.onClick = function() showConvList() end
    local conv = AgentChat.getCurrentConv()
    if conv then views.aiTitle.setText(convName(conv)) end
  end
  if updateProjectLabel then updateProjectLabel() end

  -- 更新模型标签
  updateModelLabel()

  if views.msgInput then
    pcall(function()
      views.msgInput.setOnEditorActionListener({
        onEditorAction = function(v, actionId, event)
          if actionId == 0 or actionId == 5 or actionId == 6 then
            sendMessage()
            return true
          end
          return false
        end
      })
    end)
  end

  -- 恢复上次会话
  if views.msgContainer then
    views.msgContainer.removeAllViews()  -- 先移除默认欢迎消息
    local historyCount = loadHistory(not AgentTurn.isActive())
    if historyCount == 0 then
      addWelcomeCard(S.ai_welcome_title, S.ai_welcome_body)
    end
    -- 首屏最近会话快捷切换（不占用当前会话、回合空闲时显示）
    if not AgentTurn.isActive() then
      local others = {}
      for _, item in ipairs(AgentChat.listConversations()) do
        if item.id ~= activeConversationId then others[#others + 1] = item.conversation end
      end
      table.sort(others, function(a, b)
        return tostring(a.updatedAt or "") > tostring(b.updatedAt or "")
      end)
      if #others > 0 then
        local chipTables = {}
        for i = 1, math.min(5, #others) do
          local conv = others[i]
          local prefix = conv.running and "● " or ""
          local label = conv.name ~= "" and conv.name or S.ai_unnamed_conv
          chipTables[#chipTables + 1] = {
            MaterialButton,
            text = prefix .. label,
            textSize = "12sp",
            layout_width = "wrap",
            layout_height = "wrap",
            layout_marginRight = "8dp",
            allCaps = false,
            BackgroundTintList = ColorStateList.valueOf(conv.running and ColorErrorContainer or ColorSecondaryContainer),
            textColor = conv.running and ColorOnErrorContainer or ColorOnSecondaryContainer,
            onClick = function() switchToConversation(conv) end,
          }
        end
        local hScroll = loadlayout({
          HorizontalScrollView,
          layout_width = "match",
          layout_height = "wrap",
          horizontalScrollBarEnabled = false,
          layout_marginBottom = "8dp",
          clipToPadding = false,
          paddingTop = "2dp",
          paddingBottom = "4dp",
          {
            LinearLayout,
            layout_width = "wrap",
            layout_height = "wrap",
            orientation = "horizontal",
            gravity = "center_vertical",
            paddingLeft = "4dp",
            paddingRight = "4dp",
            {
              MaterialTextView,
              text = S.ai_recent_convs,
              textSize = "11sp",
              textStyle = "bold",
              textColor = ColorText,
              layout_marginRight = "8dp",
            },
            unpack(chipTables),
          },
        })
        views.msgContainer.addView(hScroll, 0)
      end
    end
  end

  dialog.setOnShowListener(function()
    expandSheet(dialog, content)
  end)
  dialog.show()
  expandSheet(dialog, content)
  if AgentTurn.isActive() then showLoading() end
  AgentTurn.rerenderStream()

  if not AgentChat.hasApiKey() then
    content.post(function()
      showModelPicker()
    end)
  end

  return dialog
end

function _M.onBeforeProjectChange()
  saveHistory()
  AgentTurn.invalidate()
  conversationLoaded = false
  activeConversationId = nil
  activeConversationProjectPath = nil
  activeConversationHadMessages = false
end

function _M.refreshProjectContext()
  AgentTurn.invalidate()
  messages = {}
  activeConversationId = nil
  activeConversationProjectPath = nil
  activeConversationHadMessages = false
  conversationLoaded = false
  if not dialog or not dialog.isShowing() then return end
  if views.msgContainer then views.msgContainer.removeAllViews() end
  loadHistory()
  local conv = AgentChat.getCurrentConv()
  if views.aiTitle then views.aiTitle.setText(conv and convName(conv) or S.ai_new_conv) end
  updateProjectLabel()
end

function _M.saveCurrentConversation()
  return saveHistory()
end

-- 对外入口：按 id 打开当前工程的某个会话（供外部入口/会话中心使用）。
-- 面板已开时原地切换；未开时先持久化选择再由 show() 加载目标会话。
-- 与面板内切换一致：进行中的回合会被取消（见文档“切换会话会取消当前任务”）。
function _M.openConversation(id)
  if type(id) ~= "string" or id == "" then return false end
  local target
  for _, item in ipairs(AgentChat.listConversations()) do
    if item.id == id then target = item.conversation break end
  end
  if not target then return false end
  if isPanelVisible() then
    switchToConversation(target)
  else
    AgentTurn.invalidate()
    AgentChat.setCurrentConv(target.id)
    activeConversationId = target.id
    activeConversationProjectPath = AgentChat.getCurrentProjectPath()
    conversationLoaded = true
    activeConversationHadMessages = false
    _M.show()
  end
  return true
end

-- ─── 插入代码到编辑器 ──

function _M.insertCode(code)
  if not mLuaEditor or mLuaEditor.getVisibility() ~= 0 then
    print(S.ai_need_open_file)
    return
  end

  local startPos = mLuaEditor.getSelectionStart()
  local text = tostring(mLuaEditor.getText() or "")
  local newText = text:sub(1, startPos) .. code .. text:sub(startPos + 1)
  mLuaEditor.setText(newText)
  mLuaEditor.setSelection(startPos + #code)

  print(S.ai_inserted)
end

-- ─── 回合状态机装配 ──
-- 编排逻辑全部位于 AgentTurn；此处注入视图钩子。

AgentTurn.configure({
  getMessages = function() return messages end,
  setMessages = function(nextMessages) messages = nextMessages end,
  resetTurnHistory = function()
    undoTurns = {}
    redoTurns = {}
  end,
  showViews = showLoadingViews,
  hideViews = hideLoadingViews,
  setLoadingStatusView = setLoadingStatusView,
  isPanelVisible = isPanelVisible,
  scrollDown = scrollDown,
  updateContextUsage = updateContextUsage,
  saveHistory = function(updates) saveHistory(updates) end,
  refreshMessageList = function() refreshMessageList() end,
  addToolBubble = function(name, args, result) addToolBubble(name, args, result) end,
  showToolConfirm = function(name, args, onAllow, onDeny) showToolConfirm(name, args, onAllow, onDeny) end,
  cancelToolConfirm = function()
    if activeToolConfirm then activeToolConfirm.cancel() end
  end,
  isToolError = function(name, result) return isToolError(name, result) end,
  toolDisplayName = function(name) return toolDisplayName(name) end,
  reportUsage = function(used)
    convUsage.requests = convUsage.requests + 1
    convUsage.tokens = convUsage.tokens + math.max(0, tonumber(used) or 0)
  end,
  onTurnSettled = function() maybeGenerateTitle() end,
  setConversationRunning = function(running)
    if conversationLoaded then saveHistory({ running = running == true }) end
  end,
  makeStreamRender = function(streamState)
    return function()
      if AgentTurn.activeStream() ~= streamState or not isPanelVisible() or not views.msgContainer then return end
      if streamState.container ~= views.msgContainer or not streamState.bubble
          or not streamState.bubble.getParent() then
        local streamViews = {}
        local bubble = loadlayout({
          LinearLayout,
          layout_width = "match",
          layout_height = "wrap",
          orientation = "vertical",
          {
            MaterialTextView,
            id = "aiStreamText",
            textSize = "14sp",
            textColor = ColorOnSurface,
            lineSpacingMultiplier = 1.4,
          },
        }, streamViews)
        streamState.container = views.msgContainer
        streamState.bubble = bubble
        streamState.textView = streamViews.aiStreamText
        local streamLp = LinearLayout.LayoutParams(-1, -2)
        streamLp.bottomMargin = dp(14)
        streamState.container.addView(bubble, streamLp)
      end
      if streamState.textView then streamState.textView.setText(streamState.text) end
      scrollDown()
    end
  end,
})

return _M
