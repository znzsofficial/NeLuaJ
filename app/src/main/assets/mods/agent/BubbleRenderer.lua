--- 复合卡片渲染器：支持直接构建独立 View，兼容传统模式与 RecyclerView ViewHolder 复用。
local _M = {}

local Markdown = require("mods.agent.Markdown")
local Contracts = require("mods.agent.Contracts")
local TextUtil = require("mods.utils.TextUtil")
local AgentChat = require("mods.agent.AgentChat")
local AgentTurn = require("mods.agent.AgentTurn")

local TableComponent = nil
pcall(function()
  TableComponent = require("mods.agent.markdown.TableComponent")
end)

local renderMarkdown = Markdown.renderMarkdown
local parseBlocks = Markdown.parseBlocks or Markdown.splitCodeBlocks

local ColorStateList = luajava.bindClass("android.content.res.ColorStateList")
local MaterialButton = luajava.bindClass("com.google.android.material.button.MaterialButton")
local MaterialCardView = luajava.bindClass("com.google.android.material.card.MaterialCardView")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local HorizontalScrollView = luajava.bindClass("android.widget.HorizontalScrollView")
local LinkMovementMethod = luajava.bindClass("android.text.method.LinkMovementMethod")
local Typeface = luajava.bindClass("android.graphics.Typeface")
local ProgressBar = luajava.bindClass("android.widget.ProgressBar")

import "androidx.core.graphics.ColorUtils"

local ColorUtil = this.themeUtil
local ColorPrimary = ColorUtil.primary.main
local ColorOnPrimary = ColorUtil.primary.on
local ColorOnPrimaryContainer = ColorUtil.primary.onContainer
local ColorPrimaryContainer = ColorUtil.primary.container
local ColorSurface = ColorUtil.surface.container
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

local hooks = {}

function _M.configure(options)
  hooks = Contracts.callbacks("BubbleRenderer", options, {
    "getContainer", "getMessages", "saveHistory", "isToolError",
    "toolDisplayName", "insertCode", "onRegenerate", "onEditRequest",
  }, { "scrollDown", "isPanelVisible" })
end

local function scrollDown()
  if hooks.scrollDown then hooks.scrollDown() end
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

--- 构建单条消息气泡 View
function _M.createMessageView(role, content, stateMessage, opts)
  opts = opts or {}
  local canAct = not AgentTurn.isActive()
  local isUser = (role == "user")
  local textColor = isUser and ColorOnPrimaryContainer or ColorOnSurface
  local actionColor = isUser and ColorOnPrimaryContainer or ColorPrimary

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

  if isUser and opts.isLastUser and canAct and stateMessage then
    local userRow = rowViews.actionRow
    userRow.setVisibility(VISIBLE)
    local editBtn = loadlayout({
      MaterialButton,
      text = S.ai_edit_request,
      textSize = "12sp",
      allCaps = false,
      textColor = actionColor,
      icon = res.drawable("rename"),
      iconSize = dp(14),
      iconTint = ColorStateList.valueOf(actionColor),
      iconPadding = dp(4),
      BackgroundTintList = ColorStateList.valueOf(0),
      layout_width = "wrap",
      layout_height = "30dp",
      minWidth = 0,
      minHeight = 0,
      paddingLeft = "8dp",
      paddingRight = "8dp",
      paddingTop = "0dp",
      paddingBottom = "0dp",
      insetTop = 0,
      insetBottom = 0,
      onClick = function()
        onEditRequest(stateMessage)
      end,
    })
    userRow.addView(editBtn)
  end

  local reasoning = stateMessage and tostring(stateMessage.reasoning_content or "") or ""
  if not isUser and reasoning ~= "" then
    local rViews = {}
    local reasoningBlock = loadlayout({
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      {
        MaterialTextView,
        id = "rToggle",
        text = S.ai_thinking .. "  ▾",
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
      rViews.rToggle.setText(S.ai_thinking .. (reasoningExpanded and "  ▴" or "  ▾"))
    end
    inner.addView(reasoningBlock)
  end

  local parts = parseBlocks(content or "")
  for _, part in ipairs(parts) do
    if part.type == "text" then
      local userCodeBg = ColorUtils.blendARGB(ColorPrimaryContainer, ColorOnPrimaryContainer, 0.12)
      local aiCodeBg = ColorUtils.blendARGB(ColorSurface, ColorOnSurface, 0.08)
      local userTableBg = ColorUtils.blendARGB(ColorPrimaryContainer, ColorOnPrimaryContainer, 0.08)
      local aiTableBg = ColorUtils.blendARGB(ColorSurface, ColorOnSurface, 0.06)
      local markdownView = loadlayout({
        MaterialTextView,
        text = renderMarkdown(part.text, {
          isUser = isUser,
          codeBg = isUser and userCodeBg or aiCodeBg,
          tableBg = isUser and userTableBg or aiTableBg,
          codeColor = isUser and ColorOnPrimaryContainer or ColorPrimary,
          linkColor = isUser and ColorOnPrimaryContainer or ColorPrimary,
          accentColor = isUser and ColorOnPrimaryContainer or ColorPrimary,
          quoteColor = isUser and ColorOnPrimaryContainer or ColorPrimary,
        }),
        textSize = "14sp",
        textColor = textColor,
        lineSpacingMultiplier = 1.4,
      })
      if not isUser then
        pcall(function()
          markdownView.setMovementMethod(LinkMovementMethod.getInstance())
          markdownView.setLinksClickable(true)
        end)
      end
      inner.addView(markdownView)
    elseif part.type == "table" then
      local ok, tableCard = pcall(function()
        return TableComponent and TableComponent.createTableView and TableComponent.createTableView(part, isUser)
      end)
      if not ok then tableCard = nil end
      if tableCard then
        local tableLp = LinearLayout.LayoutParams(-1, -2)
        tableLp.topMargin = dp(6)
        tableLp.bottomMargin = dp(6)
        inner.addView(tableCard, tableLp)
      else
        -- 降级容错：原生表格创建失败时回退为 Markdown 文本展示，绝不吞没表格内容
        local userTableBg = ColorUtils.blendARGB(ColorPrimaryContainer, ColorOnPrimaryContainer, 0.08)
        local aiTableBg = ColorUtils.blendARGB(ColorSurface, ColorOnSurface, 0.06)
        local fallbackView = loadlayout({
          MaterialTextView,
          text = renderMarkdown(part.raw or "", {
            isUser = isUser,
            tableBg = isUser and userTableBg or aiTableBg,
          }),
          textSize = "14sp",
          textColor = textColor,
          lineSpacingMultiplier = 1.4,
        })
        inner.addView(fallbackView)
      end
    elseif part.type == "code" then
      local langLabel = (part.lang and part.lang ~= "") and part.lang:upper() or "CODE"
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
          layout_width = "match",
          layout_height = "wrap",
          padding = "8dp",
          {
            LinearLayout,
            orientation = "horizontal",
            gravity = "center_vertical",
            layout_width = "match",
            layout_height = "wrap",
            paddingBottom = "4dp",
            {
              MaterialTextView,
              text = langLabel,
              textSize = "10sp",
              textStyle = "bold",
              textColor = isUser and ColorOnPrimaryContainer or ColorText,
              layout_width = "0dp",
              layout_weight = 1,
            },
            {
              MaterialButton,
              text = S.ai_copy,
              textSize = "11sp",
              icon = res.drawable("ic_copy"),
              iconSize = dp(13),
              iconTint = ColorStateList.valueOf(isUser and ColorOnPrimaryContainer or ColorPrimary),
              iconPadding = dp(4),
              layout_width = "wrap",
              layout_height = "28dp",
              minWidth = 0,
              minHeight = 0,
              paddingLeft = "6dp",
              paddingRight = "6dp",
              BackgroundTintList = ColorStateList.valueOf(0),
              textColor = isUser and ColorOnPrimaryContainer or ColorPrimary,
              RippleColor = ColorStateList.valueOf(ColorRipple),
              layout_marginRight = "4dp",
              onClick = function(v) copyText(part.code, v) end,
            },
            {
              MaterialButton,
              text = S.ai_insert,
              textSize = "11sp",
              icon = res.drawable("ic_paste"),
              iconSize = dp(13),
              iconTint = ColorStateList.valueOf(isUser and ColorOnPrimaryContainer or ColorPrimary),
              iconPadding = dp(4),
              layout_width = "wrap",
              layout_height = "28dp",
              minWidth = 0,
              minHeight = 0,
              paddingLeft = "6dp",
              paddingRight = "6dp",
              BackgroundTintList = ColorStateList.valueOf(0),
              textColor = isUser and ColorOnPrimaryContainer or ColorPrimary,
              RippleColor = ColorStateList.valueOf(ColorRipple),
              onClick = function() insertCode(part.code) end,
            },
          },
          {
            HorizontalScrollView,
            layout_width = "match",
            layout_height = "wrap",
            horizontalScrollBarEnabled = false,
            {
              MaterialTextView,
              id = "codeText",
              text = part.code,
              typeface = Typeface.MONOSPACE,
              textSize = "12sp",
              textColor = isUser and ColorOnPrimaryContainer or ColorOnSurface,
              layout_width = "wrap",
              layout_height = "wrap",
            },
          },
        },
      })
      local codeLp = LinearLayout.LayoutParams(-1, -2)
      codeLp.topMargin = dp(4)
      codeLp.bottomMargin = dp(4)
      inner.addView(codeCard, codeLp)
    end
  end

  local actionRow = rowViews.actionRow
  if not isUser then
    local continuation = stateMessage and continuationLabel(stateMessage.continuation_state)
    if (content and content ~= "") or continuation or opts.isLastAssistant then
      actionRow.setVisibility(VISIBLE)
    end
    if content and content ~= "" then
      local copyReply = loadlayout({
        MaterialButton,
        text = S.ai_copy,
        textSize = "12sp",
        allCaps = false,
        textColor = actionColor,
        icon = res.drawable("ic_copy"),
        iconSize = dp(14),
        iconTint = ColorStateList.valueOf(actionColor),
        iconPadding = dp(4),
        BackgroundTintList = ColorStateList.valueOf(0),
        layout_width = "wrap",
        layout_height = "30dp",
        minWidth = 0,
        minHeight = 0,
        paddingLeft = "8dp",
        paddingRight = "8dp",
        paddingTop = "0dp",
        paddingBottom = "0dp",
        insetTop = 0,
        insetBottom = 0,
        onClick = function(v) copyText(content, v) end,
      })
      actionRow.addView(copyReply)
    end
    if opts.isLastAssistant and canAct and content and content ~= "" then
      local regenBtn = loadlayout({
        MaterialButton,
        text = S.ai_regenerate,
        textSize = "12sp",
        allCaps = false,
        textColor = actionColor,
        icon = res.drawable("sync"),
        iconSize = dp(14),
        iconTint = ColorStateList.valueOf(actionColor),
        iconPadding = dp(4),
        BackgroundTintList = ColorStateList.valueOf(0),
        layout_width = "wrap",
        layout_height = "30dp",
        minWidth = 0,
        minHeight = 0,
        paddingLeft = "8dp",
        paddingRight = "8dp",
        paddingTop = "0dp",
        paddingBottom = "0dp",
        insetTop = 0,
        insetBottom = 0,
        onClick = function(v)
          v.setEnabled(false)
          onRegenerate()
        end,
      })
      actionRow.addView(regenBtn)
    end
    if continuation then
      local marker = loadlayout({
        MaterialTextView,
        text = continuation,
        textSize = "12sp",
        textColor = ColorText,
        paddingLeft = "8dp",
        paddingRight = "8dp",
        layout_width = "wrap",
        layout_height = "wrap",
      })
      actionRow.addView(marker)
      local continueBtn = createContinueButton()
      continueBtn.setOnClickListener(function()
        if AgentTurn.isActive() then return end
        local parent = continueBtn.getParent()
        if parent then parent.removeView(marker); parent.removeView(continueBtn) end
        AgentTurn.bumpGeneration()
        AgentTurn.send(true)
        clearContinuationState(stateMessage)
      end)
      actionRow.addView(continueBtn)
    end
  end

  local rowLp = LinearLayout.LayoutParams(-1, -2)
  rowLp.leftMargin = isUser and dp(64) or 0
  rowLp.bottomMargin = dp(14)
  row.setLayoutParams(rowLp)
  return row
end

function _M.renderMessage(role, content, stateMessage, opts)
  local container = getContainer()
  if not container then return end
  local view = _M.createMessageView(role, content, stateMessage, opts)
  container.addView(view)
  scrollDown()
  return view
end

--- 构建工具调用与结果气泡 View
function _M.createToolView(toolName, args, result, toolOk, fileResult)
  local isError
  if type(toolOk) == "boolean" then
    isError = not toolOk
  elseif type(fileResult) == "table" and fileResult.outcome then
    isError = fileResult.outcome ~= "committed" and fileResult.outcome ~= "unchanged"
  else
    isError = isToolError(toolName, result)
  end
  local icon = "→"
  if toolName:match("create") then icon = "+"
  elseif toolName:match("delete") then icon = "×"
  elseif toolName == "apply_patch" then icon = "✎"
  elseif toolName == "append_file" then icon = "+"
  elseif toolName == "rename_file" then icon = "⇄"
  elseif toolName == "get_env_info" then icon = "i"
  elseif toolName == "fetch_url" then icon = "↗"
  elseif toolName == "run_project" then icon = "▶"
  elseif toolName == "build_project" then icon = "⚙"
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
    end
    if isError then
      resultPreview = firstLine
    elseif toolName == "get_env_info" and not isError then
      if isOutcomeLine(firstLine) then
        resultPreview = firstLine
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
    if #resultPreview > 240 then resultPreview = TextUtil.utf8Cap(resultPreview, 240) .. "…" end
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
        text = summary .. (detail ~= "" and (isError and "  ⌄" or "  ›") or ""),
        contentDescription = summary .. (detail ~= "" and (". " .. (isError and S.ai_tool_tap_collapse or S.ai_tool_tap_expand)) or ""),
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
        visibility = isError and VISIBLE or GONE,
      },
    },
  }
  local bubble = loadlayout(card, bubbleViews)
  local bubbleLp = LinearLayout.LayoutParams(-1, -2)
  bubbleLp.bottomMargin = dp(10)
  bubble.setLayoutParams(bubbleLp)

  if detail ~= "" then
    local expanded = isError
    bubbleViews.toolHeader.onClick = function()
      expanded = not expanded
      bubbleViews.toolDetail.setVisibility(expanded and VISIBLE or GONE)
      bubbleViews.toolHeader.setText(summary .. (expanded and "  ⌄" or "  ›"))
      bubbleViews.toolHeader.setContentDescription(summary .. ". "
        .. (expanded and S.ai_tool_tap_collapse or S.ai_tool_tap_expand))
    end
  end
  return bubble
end

function _M.renderTool(toolName, args, result)
  local container = getContainer()
  if not container then return end
  local bubble = _M.createToolView(toolName, args, result)
  container.addView(bubble)
  scrollDown()
  return bubble
end

--- 构建任务计划卡片 View
function _M.createTodoView(list)
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
    local rowLp = LinearLayout.LayoutParams(-1, -2)
    rowLp.topMargin = dp(index > 1 and 4 or 8)
    inner.addView(row, rowLp)
  end

  local todoLp = LinearLayout.LayoutParams(-1, -2)
  todoLp.bottomMargin = dp(10)
  card.setLayoutParams(todoLp)
  return card
end

function _M.renderTodo(list)
  local container = getContainer()
  if not container then return end
  local card = _M.createTodoView(list)
  container.addView(card)
  scrollDown()
  return card
end

local liveSubtask = nil
local subtaskCardView = nil

function _M.syncSubtask(info)
  if liveSubtask and liveSubtask.done then liveSubtask = nil end
  if info then liveSubtask = info end
end

function _M.createSubtaskView(info)
  local taskInfo = info or liveSubtask
  if not taskInfo or taskInfo.done then return nil end

  local statusText = S.ai_subtask_round:format(taskInfo.rounds or 0)
  if taskInfo.tool and taskInfo.tool ~= "" then
    statusText = statusText .. " · " .. tostring(taskInfo.tool)
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
        text = tostring(taskInfo.task or ""),
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
  local cardLp = LinearLayout.LayoutParams(-1, -2)
  cardLp.bottomMargin = dp(10)
  card.setLayoutParams(cardLp)
  return card
end

function _M.renderSubtaskCard()
  if subtaskCardView then
    local parent = subtaskCardView.getParent()
    if parent then parent.removeView(subtaskCardView) end
    subtaskCardView = nil
  end
  if not liveSubtask or liveSubtask.done then return end
  local container = getContainer()
  if not container or not (hooks.isPanelVisible and hooks.isPanelVisible()) then return end

  local card = _M.createSubtaskView(liveSubtask)
  if not card then return end
  subtaskCardView = card
  container.addView(card)
  scrollDown()
  return card
end

return _M
