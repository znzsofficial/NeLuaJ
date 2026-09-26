--- 气泡渲染层：消息气泡、任务计划卡片、子代理实时卡片与工具气泡的构建。
--- 从 ChatUI 原样抽出；容器/消息表/回调节点经 configure 注入，
--- 本模块不引用 ChatUI。AgentChat / AgentTurn / Markdown 直接 require。
local _M = {}

local AgentChat = require("mods.agent.AgentChat")
local AgentTurn = require("mods.agent.AgentTurn")
local Markdown = require("mods.agent.Markdown")

local renderMarkdown = Markdown.renderMarkdown
local splitCodeBlocks = Markdown.splitCodeBlocks

local ColorStateList = luajava.bindClass("android.content.res.ColorStateList")
local MaterialButton = luajava.bindClass("com.google.android.material.button.MaterialButton")
local MaterialCardView = luajava.bindClass("com.google.android.material.card.MaterialCardView")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local LinkMovementMethod = luajava.bindClass("android.text.method.LinkMovementMethod")
local Typeface = luajava.bindClass("android.graphics.Typeface")
local ProgressBar = luajava.bindClass("android.widget.ProgressBar")

import "androidx.core.graphics.ColorUtils"

local ColorUtil = this.themeUtil
local ColorPrimary = ColorUtil.primary.main
local ColorOnPrimaryContainer = ColorUtil.primary.onContainer
local ColorPrimaryContainer = ColorUtil.primary.container
local ColorOnSurface = ColorUtil.surface.on
local ColorText = ColorUtil.surface.onVariant
local ColorSurfaceContainerLow = ColorUtil.surface.containerLow
local ColorSurfaceContainerHigh = ColorUtil.surface.containerHigh
local ColorError = ColorUtil.error.main
local ColorErrorContainer = ColorUtil.error.container
local ColorOnErrorContainer = ColorUtil.error.onContainer

local ColorRipple = ColorUtils.blendARGB(ColorPrimary, 0x00ffffff, 0.4)
local ColorCodeBg = ColorUtils.blendARGB(ColorSurfaceContainerLow, 0xff000000, 0.08)

local res = res
local S = res.string
local dp = function(n) return this.dpToPx(n) end

local VISIBLE = 0
local GONE = 8

-- ─── 注入点（ChatUI 在 configure 时提供）──

local hooks = {}

function _M.configure(options)
  hooks = options or {}
end

local function scrollDown()
  if hooks.scrollDown then hooks.scrollDown() end
end

local function isPanelVisible()
  return hooks.isPanelVisible and hooks.isPanelVisible() or false
end

local function getContainer()
  return hooks.getContainer and hooks.getContainer() or nil
end

local function getMessages()
  return hooks.getMessages and hooks.getMessages() or {}
end

local function saveHistory(updates)
  if hooks.saveHistory then hooks.saveHistory(updates) end
end

local isToolError = function(name, result)
  if hooks.isToolError then return hooks.isToolError(name, result) end
  return false
end

local toolDisplayName = function(name)
  if hooks.toolDisplayName then return hooks.toolDisplayName(name) end
  return tostring(name or "")
end

local insertCode = function(code)
  if hooks.insertCode then hooks.insertCode(code) end
end

local onRegenerate = function()
  if hooks.onRegenerate then hooks.onRegenerate() end
end

local onEditRequest = function(stateMessage)
  if hooks.onEditRequest then hooks.onEditRequest(stateMessage) end
end

-- ─── 复制与续写辅助 ──

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
    local messages = getMessages()
    for index, message in ipairs(messages) do
      if message == stateMessage then table.remove(messages, index); break end
    end
  end
  saveHistory()
end

-- ─── 消息气泡 ──

function _M.renderMessage(role, content, stateMessage, opts)
  local container = getContainer()
  if not container then return end
  opts = opts or {}
  local canAct = not AgentTurn.isActive()

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

  -- 用户消息（最新一条）操作行：编辑重发
  if isUser and opts.isLastUser and canAct and stateMessage then
    local userRow = rowViews.actionRow
    userRow.setVisibility(VISIBLE)
    local editBtn = MaterialButton(activity)
    editBtn.setText(S.ai_edit_request)
    editBtn.setTextSize(12)
    editBtn.setAllCaps(false)
    editBtn.setTextColor(actionColor)
    editBtn.setBackgroundTintList(ColorStateList.valueOf(0))
    editBtn.setLayoutParams(LinearLayout.LayoutParams(-2, dp(30)))
    editBtn.setOnClickListener(function()
      onEditRequest(stateMessage)
    end)
    userRow.addView(editBtn)
  end

  -- 思考过程折叠块：推理模型存的 reasoning_content，默认收起
  local reasoning = stateMessage and tostring(stateMessage.reasoning_content or "") or ""
  if not isUser and reasoning ~= "" then
    local rViews = {}
    -- 加整块根布局。rToggle / rDetail 已经是它的子视图，再 addView 会抛
    -- “The specified child already has a parent”。
    local reasoningBlock = loadlayout({
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      {
        MaterialTextView,
        id = "rToggle",
        text = "🧠 " .. S.ai_thinking .. "  ▸",
        textSize = "12sp",
        textStyle = "bold",
        textColor = ColorText,
        clickable = true,
        focusable = true,
        padding = "4dp",
      },
      {
        MaterialTextView,
        id = "rDetail",
        textSize = "12sp",
        textColor = ColorText,
        lineSpacingMultiplier = 1.3,
        textIsSelectable = true,
        visibility = GONE,
        layout_marginTop = "4dp",
      },
    }, rViews)
    rViews.rDetail.setText(reasoning)
    local reasoningExpanded = false
    rViews.rToggle.onClick = function()
      reasoningExpanded = not reasoningExpanded
      rViews.rDetail.setVisibility(reasoningExpanded and VISIBLE or GONE)
      rViews.rToggle.setText("🧠 " .. S.ai_thinking .. (reasoningExpanded and "  ▾" or "  ▸"))
    end
    inner.addView(reasoningBlock)
  end

  local parts = splitCodeBlocks(content or "")
  for _, part in ipairs(parts) do
    if part.type == "text" then
      local markdownView = loadlayout({
        MaterialTextView,
        text = renderMarkdown(part.text, {
          codeColor = isUser and ColorOnPrimaryContainer or ColorPrimary,
          linkColor = isUser and ColorOnPrimaryContainer or ColorPrimary,
        }),
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
              onClick = function() insertCode(part.code) end,
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

  -- AI 消息的操作行：复制全文 / 重新生成 / 续写标记与按钮
  local actionRow = rowViews.actionRow
  if not isUser then
    local continuation = stateMessage and continuationLabel(stateMessage.continuation_state)
    if (content and content ~= "") or continuation or opts.isLastAssistant then
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
    -- 最新一条 AI 回复（且无进行中任务）：一键重新生成
    if opts.isLastAssistant and canAct and content and content ~= "" then
      local regenBtn = MaterialButton(activity)
      regenBtn.setText(S.ai_regenerate)
      regenBtn.setTextSize(12)
      regenBtn.setAllCaps(false)
      regenBtn.setTextColor(actionColor)
      regenBtn.setBackgroundTintList(ColorStateList.valueOf(0))
      regenBtn.setLayoutParams(LinearLayout.LayoutParams(-2, dp(30)))
      regenBtn.setOnClickListener(function(v)
        regenBtn.setEnabled(false)
        onRegenerate()
      end)
      actionRow.addView(regenBtn)
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
  return row
end

-- ─── 任务计划卡片 ──

function _M.renderTodo(list)
  local container = getContainer()
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

-- ─── 子代理实时卡片 ──
-- 消息列表重建（refreshMessageList）后由 syncSubtask + renderSubtaskCard 恢复。

local liveSubtask = nil
local subtaskCardView = nil

--- 同步运行快照：done 的清除，运行中的更新
function _M.syncSubtask(info)
  if liveSubtask and liveSubtask.done then liveSubtask = nil end
  if info then liveSubtask = info end
end

function _M.renderSubtaskCard()
  if subtaskCardView then
    local parent = subtaskCardView.getParent()
    if parent then parent.removeView(subtaskCardView) end
    subtaskCardView = nil
  end
  if not liveSubtask or liveSubtask.done then return end
  local container = getContainer()
  if not container or not isPanelVisible() then return end

  local statusText = S.ai_subtask_round:format(liveSubtask.rounds or 0)
  if liveSubtask.tool and liveSubtask.tool ~= "" then
    statusText = statusText .. " · " .. tostring(liveSubtask.tool)
  end
  local cardViews = {}
  local card = loadlayout({
    MaterialCardView,
    radius = "12dp",
    CardElevation = 0,
    CardBackgroundColor = ColorSurfaceContainerHigh,
    layout_width = "match",
    layout_height = "wrap",
    {
      LinearLayout,
      orientation = "vertical",
      padding = "12dp",
      {
        LinearLayout,
        orientation = "horizontal",
        gravity = "center_vertical",
        {
          MaterialTextView,
          text = "⚑",
          textSize = "14sp",
          textColor = ColorPrimary,
        },
        {
          MaterialTextView,
          text = S.ai_tool_subtask,
          textSize = "12sp",
          textStyle = "bold",
          textColor = ColorOnSurface,
          layout_marginLeft = "6dp",
          layout_width = "0dp",
          layout_weight = 1,
        },
        {
          ProgressBar,
          layout_width = "12dp",
          layout_height = "12dp",
          indeterminate = true,
          indeterminateTintList = ColorStateList.valueOf(ColorPrimary),
        },
      },
      {
        MaterialTextView,
        text = tostring(liveSubtask.task or ""),
        textSize = "12sp",
        textColor = ColorText,
        maxLines = 2,
        ellipsize = "end",
        layout_marginTop = "2dp",
      },
      {
        MaterialTextView,
        text = statusText,
        textSize = "11sp",
        textColor = ColorPrimary,
        layout_marginTop = "4dp",
      },
    },
  }, cardViews)
  subtaskCardView = card
  local cardLp = LinearLayout.LayoutParams(-1, -2)
  cardLp.bottomMargin = dp(10)
  container.addView(card, cardLp)
  scrollDown()
end

-- ─── 工具气泡 ──

function _M.renderTool(toolName, args, result)
  local container = getContainer()
  if not container then return end

  if AgentChat.normalizeToolName(toolName) == "update_todos" then
    local list = args and args.todos
    local failed = result and tostring(result):find("任务计划未更新", 1, true) ~= nil
    -- 列表合法且更新成功才渲染计划卡片；失败或清空走通用气泡展示结果文本
    if type(list) == "table" and #list > 0 and not failed then
      _M.renderTodo(list)
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
  elseif toolName == "build_project" then icon = "📦"
  elseif toolName == "run_subtask" then icon = "⚑" end

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

return _M
