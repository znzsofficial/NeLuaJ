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
local Switch = luajava.bindClass("com.google.android.material.materialswitch.MaterialSwitch")
local HtmlCompat = luajava.bindClass("androidx.core.text.HtmlCompat")
local LinkMovementMethod = luajava.bindClass("android.text.method.LinkMovementMethod")
local Typeface = luajava.bindClass("android.graphics.Typeface")
local WindowManager = luajava.bindClass("android.view.WindowManager")
local DialogInterface = luajava.bindClass("android.content.DialogInterface")

import "androidx.core.graphics.ColorUtils"

local AgentChat = require("mods.agent.AgentChat")
local MCPClient = require("mods.agent.MCPClient")
local ActivityUtil = require("mods.utils.ActivityUtil")
import "mods.utils.EditorUtil"
local ColorUtil = this.themeUtil
local ColorPrimary = ColorUtil.getColorPrimary()
local ColorOnPrimary = ColorUtil.getColorOnPrimary()
local ColorSecondaryContainer = ColorUtil.getColorSecondaryContainer()
local ColorOnSecondaryContainer = ColorUtil.getColorOnSecondaryContainer()
local ColorSurface = ColorUtil.getColorSurfaceContainer()
local ColorSurfaceContainerHigh = ColorUtil.getColorSurfaceContainerHigh()
local ColorOnSurface = ColorUtil.getColorOnSurface()
local ColorText = ColorUtil.getColorOnSurfaceVariant()
local ColorOutline = ColorUtil.getColorOutlineVariant()
local ColorError = ColorUtil.getColorError()
local ColorErrorContainer = ColorUtil.getColorErrorContainer()
local ColorOnErrorContainer = ColorUtil.getColorOnErrorContainer()
local ColorRipple = ColorUtils.blendARGB(ColorPrimary, 0x00ffffff, 0.4)
local ColorCodeBg = ColorUtils.blendARGB(ColorSurface, 0xff000000, 0.07)
local S = res.string
local GradientDrawable = luajava.bindClass("android.graphics.drawable.GradientDrawable")
local function dp(n) return this.dpToPx(n) end

local VISIBLE = 0
local GONE = 8

local messages = {}
local dialog = nil
local views = {}
local isLoading = false
local requestGeneration = 0
local stopRequested = false
local activeToolConfirm = nil
local activeToolStop = nil
local editingMessageIndex = nil
local undoTurns = {}
local redoTurns = {}
local activeConversationId = nil
local activeStream = nil
local conversationLoaded = false
local activeConversationProjectPath = nil
local activeConversationHadMessages = false
local requestRetryPayloads = setmetatable({}, { __mode = "k" })
local failedToolCalls = {}

-- 前向声明
local saveHistory, loadHistory, showModelManager, showModelPicker, showConvManager, showConvList, showSettings, addMessageBubble, addToolBubble, updateProjectLabel, sendMessage, sendToApi, sendWithCompressedContext, addRequestErrorBubble

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
  local bgColor = isUser and ColorPrimary or ColorSurface
  local textColor = isUser and ColorOnPrimary or ColorOnSurface

  -- 头像
  local avatar = MaterialTextView(activity)
  avatar.setText(isUser and S.ai_you or "AI")
  avatar.setTextSize(10)
  avatar.setTypeface(Typeface.DEFAULT, 1)
  avatar.setGravity(17)
  local ag = GradientDrawable()
  ag.setShape(GradientDrawable.OVAL)
  if isUser then
    ag.setColor(ColorUtils.blendARGB(ColorPrimary, 0xffffffff, 0.15))
    avatar.setTextColor(ColorOnPrimary)
  else
    ag.setColor(ColorCodeBg)
    avatar.setTextColor(ColorText)
  end
  avatar.setBackground(ag)
  local avatarLp = LinearLayout.LayoutParams(dp(28), dp(28))
  avatarLp.topMargin = dp(2)
  avatar.setLayoutParams(avatarLp)

  local row = LinearLayout(activity)
  row.setOrientation(0)
  local rowLp = LinearLayout.LayoutParams(-1, -2)
  rowLp.bottomMargin = dp(12)
  row.setLayoutParams(rowLp)

  local col = LinearLayout(activity)
  col.setOrientation(1)
  col.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))

  -- 内容气泡
  local inner = loadlayout({
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    padding = "12dp",
  })

  local parts = splitCodeBlocks(content or "")
  for _, part in ipairs(parts) do
    if part.type == "text" then
      local markdownView = loadlayout({
        MaterialTextView,
        text = renderMarkdown(part.text),
        textSize = "13sp",
        textColor = textColor,
        lineSpacingMultiplier = 1.35,
      })
      markdownView.setMovementMethod(LinkMovementMethod.getInstance())
      markdownView.setLinksClickable(true)
      inner.addView(markdownView)
    else
      -- 代码块：等宽 + 深色背景 + 复制/插入按钮
      local codeCard = loadlayout({
        MaterialCardView,
        radius = "8dp",
        CardElevation = 0,
        CardBackgroundColor = ColorCodeBg,
        layout_width = "match",
        layout_height = "wrap",
        layout_marginTop = "4dp",
        layout_marginBottom = "4dp",
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
            textColor = ColorOnSurface,
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
              textColor = ColorPrimary,
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
              textColor = ColorPrimary,
              RippleColor = ColorStateList.valueOf(ColorRipple),
              onClick = function() _M.insertCode(part.code) end,
            },
          },
        },
      })
      inner.addView(codeCard)
    end
  end

  local continuation = not isUser and stateMessage and continuationLabel(stateMessage.continuation_state)
  if continuation then
    local marker = MaterialTextView(activity)
    marker.setText(continuation)
    marker.setTextSize(12)
    marker.setTextColor(ColorText)
    marker.setPadding(0, dp(6), 0, 0)
    inner.addView(marker)
    local continueBtn = createContinueButton()
    continueBtn.setOnClickListener(function()
      if isLoading then return end
      clearContinuationState(stateMessage)
      local parent = continueBtn.getParent()
      if parent then parent.removeView(marker); parent.removeView(continueBtn) end
      stopRequested = false
      requestGeneration = requestGeneration + 1
      sendWithCompressedContext(true)
    end)
    inner.addView(continueBtn)
  end

  if not isUser and content and content ~= "" then
    local copyReply = MaterialButton(activity)
    copyReply.setText(S.ai_copy)
    copyReply.setTextSize(11)
    copyReply.setAllCaps(false)
    copyReply.setTextColor(ColorPrimary)
    copyReply.setBackgroundTintList(ColorStateList.valueOf(0))
    copyReply.setLayoutParams(LinearLayout.LayoutParams(-2, dp(30)))
    copyReply.setOnClickListener(function(v) copyText(content, v) end)
    inner.addView(copyReply)
  end

  local card = {
    MaterialCardView,
    radius = "12dp",
    CardElevation = 0,
    CardBackgroundColor = bgColor,
    layout_width = "match",
    layout_height = "wrap",
    inner,
  }
  if not isUser then
    card.strokeWidth = "1dp"
    card.strokeColor = ColorOutline
  end

  if isUser then
    avatarLp.leftMargin = dp(8)
    col.addView(loadlayout(card))
    row.addView(col)
    row.addView(avatar)
  else
    avatarLp.rightMargin = dp(8)
    row.addView(avatar)
    col.addView(loadlayout(card))
    row.addView(col)
  end
  container.addView(row)
  scrollDown()
end

--- 添加工具操作气泡（显示工具名和参数摘要）
addToolBubble = function(toolName, args, result)
  local container = views.msgContainer
  if not container then return end

  local isError = isToolError(toolName, result)
  local icon = "→"
  if toolName:match("create") then icon = "✚"
  elseif toolName:match("delete") then icon = "✕"
  elseif toolName == "apply_patch" then icon = "✎"
  elseif toolName == "append_file" then icon = "＋"
  elseif toolName == "rename_file" then icon = "⇄"
  elseif toolName == "get_env_info" then icon = "ℹ"
  elseif toolName == "fetch_url" then icon = "↗" end

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
    radius = "8dp",
    CardElevation = 0,
    strokeWidth = "1dp",
    strokeColor = isError and ColorError or ColorOutline,
    CardBackgroundColor = ColorSurface,
    layout_width = "match",
    layout_height = "wrap",
    layout_marginBottom = "8dp",
    layout_marginLeft = "48dp",
    layout_marginRight = "48dp",
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
        textColor = isError and ColorError or ColorOnSurface,
        padding = "10dp",
        clickable = detail ~= "",
        focusable = detail ~= "",
      },
      {
        MaterialTextView,
        text = resultPreview,
        textSize = "11sp",
        textColor = ColorText,
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
        textColor = isError and ColorError or ColorText,
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
  container.addView(bubble)
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

local function showLoading()
  isLoading = true
  if views.loadingText then views.loadingText.setText(S.ai_generating) end
  if views.loadingBar then views.loadingBar.setVisibility(VISIBLE) end
  if views.btnSend then views.btnSend.setEnabled(false) end
  if views.btnSend then views.btnSend.setVisibility(GONE) end
  if views.btnStop then views.btnStop.setVisibility(VISIBLE) end
  if views.btnStop then views.btnStop.setEnabled(true) end
end

local function setLoadingStatus(text)
  if views.loadingText and isLoading then views.loadingText.setText(tostring(text or S.ai_generating)) end
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
  views.ctxUsage.setText(label .. " · " .. used .. "/" .. budget)
end

-- 前台保活服务：回合进行中提升进程优先级并持有唤醒锁，息屏也能继续。
-- pcall 兜底：旧安装或类缺失时静默降级，绝不影响对话本身。
local function keepAliveAcquire()
  pcall(function()
    luajava.bindClass("com.nekolaska.ai.AgentKeepAliveService").acquire(activity)
  end)
end

local function keepAliveRelease()
  pcall(function()
    luajava.bindClass("com.nekolaska.ai.AgentKeepAliveService").release(activity)
  end)
end

local function hideLoading()
  isLoading = false
  keepAliveRelease()
  if views.loadingBar then views.loadingBar.setVisibility(GONE) end
  if views.btnSend then views.btnSend.setEnabled(true) end
  if views.btnSend then views.btnSend.setVisibility(VISIBLE) end
  if views.btnStop then views.btnStop.setVisibility(GONE) end
  if views.btnStop then views.btnStop.setEnabled(true) end
end

local function invalidateRequest()
  stopRequested = true
  if activeToolConfirm then activeToolConfirm.cancel() end
  requestGeneration = requestGeneration + 1
  stopRequested = false
  isLoading = false
  activeStream = nil
  AgentChat.cancelPendingRequest()
  if AgentChat.cancelPendingTools then AgentChat.cancelPendingTools() end
  local stopTool = activeToolStop
  activeToolStop = nil
  if stopTool then pcall(stopTool) end
  hideLoading()
  return requestGeneration
end

local function refreshMessageList()
  if not isPanelVisible() then return end
  if views.msgContainer then views.msgContainer.removeAllViews() end
  loadHistory(false)
end

local function undoLastTurn()
  if isLoading then return false end
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
  if isLoading or #redoTurns == 0 then return false end
  local restored = table.remove(redoTurns, 1)
  for _, message in ipairs(restored) do messages[#messages + 1] = message end
  undoTurns[#undoTurns + 1] = restored
  saveHistory()
  refreshMessageList()
  return true
end

local function applyFileChange(action)
  if isLoading then return false end
  requestGeneration = requestGeneration + 1
  local generation = requestGeneration
  showLoading()
  local okLaunch = pcall(function()
    xTask(function()
      local ok, result, err = pcall(action)
      return { ok = ok and result == true, error = ok and err or result }
    end, function(result)
      if generation ~= requestGeneration then return end
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
  if isLoading then return false end
  requestGeneration = requestGeneration + 1
  local generation = requestGeneration
  showLoading()
  AgentChat.buildCompressedApiMessages(messages, function(apiMessages, compressed)
    if generation ~= requestGeneration then return end
    hideLoading()
    if not compressed then
      print(S.ai_compress_unavailable)
      return
    end
    local compacted = {}
    for i = 2, #apiMessages do compacted[#compacted + 1] = apiMessages[i] end
    messages = compacted
    undoTurns = {}
    redoTurns = {}
    saveHistory()
    refreshMessageList()
    print(S.ai_compress_done:format(#messages))
    if onDone then pcall(onDone) end
  end, true)
  return true
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
  addAction(S.ai_compress_context, not isLoading and #messages > 0, compressCurrentContext)
  addAction(S.ai_undo_turn, not isLoading and hasTurn, undoLastTurn)
  addAction(S.ai_redo_turn, not isLoading and #redoTurns > 0, redoLastTurn)
  addSection(S.ai_command_files)
  addAction(S.ai_undo_file, not isLoading and AgentChat.hasFileUndo(), undoFileChange)
  addAction(S.ai_redo_file, not isLoading and AgentChat.hasFileRedo(), redoFileChange)
  addSection(S.ai_command_workspace)
  addAction(S.ai_switch_conv, true, showConvList)
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

-- ─── 执行工具调用链 ──

local function executeToolCalls(toolCalls, index, results, onAllDone, generation)
  if generation and generation ~= requestGeneration then return end
  if stopRequested then return end
  if index > #toolCalls then
    -- 文件操作后刷新编辑器
    pcall(function()
      if MainActivity and MainActivity.RecyclerView then
        MainActivity.RecyclerView.update()
      end
      -- 如果修改了当前打开的文件，刷新编辑器
      for _, r in ipairs(results) do
        if r.tool_call_id then
          for _, tc in ipairs(toolCalls) do
            if tc.id == r.tool_call_id and (tc.name == "create_file" or tc.name == "apply_patch" or tc.name == "append_file") then
              local args = {}
              pcall(function() args = json.decode(tc.arguments) end)
              if args.path then
                local thisFile = Bean and Bean.Path and Bean.Path.this_file
                local resolvedPath = args.path
                if resolvedPath:sub(1, 1) ~= "/" then
                  local base = Bean and Bean.Path and Bean.Path.this_dir or activity.getLuaDir()
                  resolvedPath = base .. "/" .. resolvedPath
                end
                if thisFile and thisFile == resolvedPath then
                  EditorUtil.load(resolvedPath)
                end
              end
            end
          end
        end
      end
    end)
    onAllDone(results)
    return
  end

  local tc = toolCalls[index]
  local args = {}
  local argsOk, argsError = pcall(function() args = json.decode(tc.arguments) end)
  if not argsOk or type(args) ~= "table" then
    args = {}
    argsError = argsOk and "工具参数必须是 JSON 对象" or tostring(argsError)
  end
  tc.name = AgentChat.normalizeToolName(tc.name, args)
  if tc.name == "run_lua" and (not args.code or args.code == "") and args.content then
    args.code = args.content
    args.content = nil
  end
  local argsEncoded, encodedArgs = pcall(json.encode, args)
  local toolCallKey = tc.name .. "\n" .. (argsEncoded and tostring(encodedArgs) or tostring(tc.arguments or ""))

  setLoadingStatus(S.ai_tool_pending .. " · " .. toolDisplayName(tc.name))
  local stopped = false
  local stopHandle

  local function finishStopped(firstRemaining)
    if stopped then return end
    stopped = true
    if activeToolStop == stopHandle then activeToolStop = nil end
    -- Return an output for this and all remaining calls. Responses APIs require
    -- every function_call to be paired with function_call_output, even on stop.
    for remaining = firstRemaining or index, #toolCalls do
      local call = toolCalls[remaining]
      local callArgs = args
      if remaining ~= index then
        callArgs = {}
        pcall(function() callArgs = json.decode(call.arguments) end)
        if type(callArgs) ~= "table" then callArgs = {} end
      end
      addToolBubble(call.name, callArgs, S.ai_stopped)
      messages[#messages + 1] = {
        role = "tool",
        tool_call_id = call.id,
        content = S.ai_stopped,
      }
    end
    local stateMessage = messages[#messages]
    if stateMessage and stateMessage.role == "tool" then
      stateMessage.continuation_state = "stopped"
    end
    saveHistory()
    refreshMessageList()
    pcall(function()
      if MainActivity and MainActivity.RecyclerView then MainActivity.RecyclerView.update() end
    end)
  end

  local function proceedWithResult(resultStr, stopAfterResult)
    if activeToolStop == stopHandle then activeToolStop = nil end
    if generation and generation ~= requestGeneration then return end
    results[#results + 1] = {
      tool_call_id = tc.id,
      content = resultStr,
    }
    -- Persist each completed tool before proceeding. A later stop must not
    -- lose evidence of already-executed operations from the conversation.
    messages[#messages + 1] = {
      role = "tool",
      tool_call_id = tc.id,
      content = resultStr,
    }
    if isToolError(tc.name, resultStr) then
      failedToolCalls[toolCallKey] = tostring(resultStr):sub(1, 1000)
    else
      failedToolCalls[toolCallKey] = nil
    end
    saveHistory()
    refreshMessageList()
    if stopAfterResult then
      hideLoading()
      activeStream = nil
      messages[#messages + 1] = {
        role = "assistant",
        content = "工具调用已停止：相同的工具名和参数已失败，未继续重复执行。请检查上一次错误并修改请求。",
      }
      saveHistory()
      refreshMessageList()
      return
    end
    if stopRequested then
      finishStopped(index + 1)
      return
    end
    executeToolCalls(toolCalls, index + 1, results, onAllDone, generation)
  end

  local function executeCurrentTool()
    stopHandle = function() finishStopped() end
    activeToolStop = stopHandle
    AgentChat.executeToolAsync(tc.name, args, proceedWithResult)
  end

  if argsError then
    local errorText = "工具参数 JSON 无效，未执行 " .. tostring(tc.name) .. ": " .. tostring(argsError)
    failedToolCalls[toolCallKey] = errorText
    proceedWithResult(errorText)
    return
  end

  local previousFailure = failedToolCalls[toolCallKey]
  if previousFailure then
    proceedWithResult("为防止重复失败，未再次执行相同工具调用。\n前一次错误: " .. previousFailure, true)
    return
  end

  if AgentChat.shouldAutoApprove(tc.name, args) then
    executeCurrentTool()
  elseif (AgentChat.requiresConfirmation and AgentChat.requiresConfirmation(tc.name, args))
      or AgentChat.isDestructiveTool(tc.name) then
    showToolConfirm(tc.name, args, function()
      if (generation and generation ~= requestGeneration) or stopRequested then
        finishStopped()
        return
      end
      executeCurrentTool()
    end, function()
      if (generation and generation ~= requestGeneration) or stopRequested then
        finishStopped()
        return
      end
      proceedWithResult(S.ai_user_denied)
    end)
  else
    executeCurrentTool()
  end
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
  local saved = AgentChat.saveConversation(activeConversationId, messages, updates)
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
  conversationLoaded = conv ~= nil
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
  if activeStream and activeStream.generation == requestGeneration and activeStream.render then
    activeStream.render()
  end
  return #messages
end

-- ─── 发送消息核心 ──

sendToApi = function(apiMessages, isContinue)
  local generation = requestGeneration
  local requestUserIndex
  for index = #messages, 1, -1 do
    if messages[index].role == "user" then requestUserIndex = index; break end
  end
  stopRequested = false
  local function isCurrent()
    return generation == requestGeneration
  end
  if not isContinue then
    failedToolCalls = {}
  end
  showLoading()
  keepAliveAcquire()

  -- 上下文用量显示：估算本次将发送的 token 数
  updateContextUsage(AgentChat.estimateApiMessagesUsage(apiMessages))

  local fullResponse = ""
  local streamState = { generation = generation, text = "" }
  activeStream = streamState
  streamState.render = function()
    if activeStream ~= streamState or not isPanelVisible() or not views.msgContainer then return end
    if streamState.container ~= views.msgContainer or not streamState.bubble
        or not streamState.bubble.getParent() then
      local streamViews = {}
      local bubble = loadlayout({
        MaterialCardView,
        radius = "12dp",
        CardElevation = 0,
        strokeWidth = "1dp",
        strokeColor = ColorOutline,
        CardBackgroundColor = ColorSurface,
        layout_width = "match",
        layout_height = "wrap",
        layout_marginBottom = "8dp",
        layout_marginRight = "32dp",
        {
          LinearLayout,
          orientation = "vertical",
          padding = "12dp",
          {
            MaterialTextView,
            id = "aiStreamText",
            textSize = "13sp",
            textColor = ColorOnSurface,
            lineSpacingMultiplier = 1.35,
          },
        },
      }, streamViews)
      streamState.container = views.msgContainer
      streamState.bubble = bubble
      streamState.textView = streamViews.aiStreamText
      streamState.container.addView(bubble)
    end
    if streamState.textView then streamState.textView.setText(streamState.text) end
    scrollDown()
  end
  streamState.render()

  AgentChat.sendStream(apiMessages, {
    onPrepared = function(usage)
      if not isCurrent() or type(usage) ~= "table" then return end
      updateContextUsage(usage)
    end,
    onChunk = function(chunk)
      if not isCurrent() then return end
      setLoadingStatus(S.ai_generating)
      fullResponse = fullResponse .. chunk
      streamState.text = fullResponse
      streamState.render()
    end,
    -- 自动重试前清空已流出的内容，避免失败段落重复拼接
    onRetry = function()
      if not isCurrent() then return end
      fullResponse = ""
      streamState.text = ""
      setLoadingStatus(S.ai_retrying)
      streamState.render()
    end,
    onToolCalls = function(toolCalls, text, reasoningContent, responseOutput, responseOrigin)
      if not isCurrent() or stopRequested then return end
      -- 不调用 hideLoading，保持加载状态直到续请求完成
      if text and text ~= "" and text ~= fullResponse then
        fullResponse = text
        streamState.text = text
      end

      -- 保存 assistant 消息（含 tool_calls）
      local assistantMsg = { role = "assistant" }
      if text and text ~= "" then
        assistantMsg.content = text
      end
      if reasoningContent and tostring(reasoningContent) ~= "" then
        assistantMsg.reasoning_content = tostring(reasoningContent)
      end
      if type(responseOutput) == "table" and #responseOutput > 0 and responseOrigin and responseOrigin ~= "" then
        assistantMsg.response_output = responseOutput
        assistantMsg.response_origin = responseOrigin
      end
      assistantMsg.tool_calls = {}
      for _, tc in ipairs(toolCalls) do
        assistantMsg.tool_calls[#assistantMsg.tool_calls + 1] = {
          id = tc.id,
          item_id = tc.item_id,
          type = "function",
          ["function"] = {
            name = tc.name,
            arguments = tc.arguments,
          },
        }
        if tc.legacy_function_call then assistantMsg.legacy_function_call = true end
      end
      messages[#messages + 1] = assistantMsg
      saveHistory()
      activeStream = nil
      refreshMessageList()

      -- 执行工具调用
      executeToolCalls(toolCalls, 1, {}, function(results)
        if not isCurrent() or stopRequested then return end
        sendWithCompressedContext(true)
      end, generation)
    end,
    onEmptyAfterTools = function()
      if not isCurrent() then return end
      hideLoading()
      activeStream = nil
      -- The tool result is already in history. Do not add a blank assistant
      -- message, otherwise the next continuation may lose the tool context.
      local stateMessage = messages[#messages]
      if stateMessage and stateMessage.role == "tool" then
        stateMessage.continuation_state = "empty_after_tools"
        saveHistory()
      end
      refreshMessageList()
    end,
    onDone = function(text, incomplete, responseOutput, responseOrigin, reasoningContent)
      if not isCurrent() then return end
      hideLoading()
      activeStream = nil
      local assistantMsg = { role = "assistant", content = text }
      if type(responseOutput) == "table" and #responseOutput > 0 and responseOrigin and responseOrigin ~= "" then
        assistantMsg.response_output = responseOutput
        assistantMsg.response_origin = responseOrigin
      end
      if reasoningContent and tostring(reasoningContent) ~= "" then
        assistantMsg.reasoning_content = tostring(reasoningContent)
      end
      if incomplete == true then assistantMsg.continuation_state = "incomplete" end
      messages[#messages + 1] = assistantMsg
      saveHistory()
      refreshMessageList()
    end,
    onError = function(err)
      if not isCurrent() then return end
      hideLoading()
      activeStream = nil
      -- 用户主动停止：保留已生成部分，不显示错误
      if tostring(err):lower():match("cancel") then
        local stateMessage = { role = "assistant", content = fullResponse, continuation_state = "stopped" }
        messages[#messages + 1] = stateMessage
        saveHistory()
        refreshMessageList()
        requestGeneration = requestGeneration + 1
        stopRequested = false
        return
      end
      local requestMessage = requestUserIndex and messages[requestUserIndex]
      if requestMessage and requestMessage.role == "user" then
        requestMessage.request_error = tostring(err)
        requestRetryPayloads[requestMessage] = apiMessages
      end
      saveHistory()
      refreshMessageList()
    end,
  })
end

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
  views.msgContainer.addView(loadlayout({
    MaterialCardView,
    radius = "8dp",
    CardElevation = 0,
    strokeWidth = "1dp",
    strokeColor = ColorError,
    CardBackgroundColor = ColorSurface,
    layout_width = "match",
    layout_height = "wrap",
    layout_marginBottom = "8dp",
    layout_marginLeft = "48dp",
    layout_marginRight = "48dp",
    {
      LinearLayout,
      orientation = "vertical",
      padding = "12dp",
      {
        MaterialTextView,
        text = tostring(err),
        textSize = "13sp",
        textColor = ColorError,
        lineSpacingMultiplier = 1.3,
        textIsSelectable = true,
      },
      {
        LinearLayout,
        orientation = "horizontal",
        layout_marginTop = "6dp",
        {
          MaterialButton,
          id = "recoverButton",
          text = action,
          layout_width = "wrap",
        },
        {
          MaterialButton,
          id = "editButton",
          text = S.ai_edit_request,
          layout_width = "wrap",
        },
      },
    },
  }, errorViews))

  errorViews.recoverButton.onClick = function()
    if isLoading then return end
    local message = messages[messageIndex]
    if not message or message.role ~= "user" or not message.request_error then
      print(S.ai_request_expired)
      return
    end
    if opensSettings then
      showSettings()
      return
    end
    local retryPayload = requestRetryPayloads[message]
    message.request_error = nil
    saveHistory()
    refreshMessageList()
    if compresses then
      compressCurrentContext(function() sendWithCompressedContext(false) end)
    else
      requestGeneration = requestGeneration + 1
      if retryPayload then sendToApi(retryPayload, false)
      else sendWithCompressedContext(false) end
    end
  end

  errorViews.editButton.onClick = function()
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

sendWithCompressedContext = function(isContinue, userMsg)
  local generation = requestGeneration
  showLoading()
  local requestHistory = messages
  if userMsg and userMsg ~= "" then
    requestHistory = {}
    for i, message in ipairs(messages) do
      requestHistory[i] = message
    end
    local last = requestHistory[#requestHistory]
    if last and last.role == "user" then
      requestHistory[#requestHistory] = {}
      for key, value in pairs(last) do
        requestHistory[#requestHistory][key] = value
      end
      requestHistory[#requestHistory].content = userMsg
    end
  end
  AgentChat.buildCompressedApiMessages(requestHistory, function(apiMessages, compressed, compressedHistory)
    if generation ~= requestGeneration or stopRequested then return end
    -- 自动压缩结果持久化到会话：后续发送不再重复摘要，直到再次超出预算。
    if compressed and compressedHistory and #compressedHistory > 0 and #messages > #compressedHistory then
      messages = compressedHistory
      undoTurns = {}
      redoTurns = {}
      saveHistory()
      refreshMessageList()
      print(S.ai_compress_auto_done:format(#messages))
    end
    sendToApi(apiMessages, isContinue)
  end)
end

-- ─── 发送消息 ──

sendMessage = function()
  if isLoading then return end

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
  stopRequested = false
  requestGeneration = requestGeneration + 1
  sendWithCompressedContext(false, userMsg)
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
  local row = LinearLayout(activity)
  row.setOrientation(0)
  row.setGravity(16)
  row.setPadding(dp(12), dp(10), dp(12), dp(10))
  local lp = LinearLayout.LayoutParams(-1, -2)
  lp.bottomMargin = dp(8)
  row.setLayoutParams(lp)
  row.setClickable(true)
  local bg = GradientDrawable()
  if isCurrent then
    bg.setColor(ColorUtils.blendARGB(ColorPrimary, ColorSurface, 0.82))
  else
    bg.setColor(ColorSurface)
  end
  bg.setCornerRadius(dp(14))
  if isCurrent then bg.setStroke(math.floor(dp(1)), ColorPrimary) end
  row.setBackground(bg)
  row.setOnClickListener(function() if onClick then onClick() end end)

  row.addView(makeAvatar(name, 40))

  local col = LinearLayout(activity)
  col.setOrientation(1)
  col.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
  col.setPadding(dp(10), 0, dp(4), 0)
  local nameTv = MaterialTextView(activity)
  nameTv.setText(name)
  nameTv.setTextSize(15)
  nameTv.setTypeface(Typeface.DEFAULT, 1)
  nameTv.setTextColor(ColorOnSurface)
  nameTv.setSingleLine(true)
  col.addView(nameTv)
  local metaTv = MaterialTextView(activity)
  metaTv.setText(convMetaText(conv))
  metaTv.setTextSize(12)
  metaTv.setTextColor(ColorText)
  metaTv.setSingleLine(true)
  col.addView(metaTv)
  row.addView(col)

  if isCurrent then
    local badge = MaterialTextView(activity)
    badge.setText(S.ai_current)
    badge.setTextSize(11)
    badge.setGravity(17)
    badge.setTextColor(ColorOnPrimary)
    local bbg = GradientDrawable()
    bbg.setShape(GradientDrawable.OVAL)
    bbg.setColor(ColorPrimary)
    badge.setBackground(bbg)
    badge.setLayoutParams(LinearLayout.LayoutParams(dp(42), dp(24)))
    row.addView(badge)
  end
  return row
end

local function buildManagerRow(conv, render)
  local name = convName(conv)
  local convId = conv and conv.id
  local row = LinearLayout(activity)
  row.setOrientation(0)
  row.setGravity(16)
  row.setPadding(dp(12), dp(8), dp(12), dp(8))
  local lp = LinearLayout.LayoutParams(-1, -2)
  lp.bottomMargin = dp(8)
  row.setLayoutParams(lp)
  local bg = GradientDrawable()
  bg.setColor(ColorSurface)
  bg.setCornerRadius(dp(14))
  row.setBackground(bg)

  row.addView(makeAvatar(name, 36))

  local col = LinearLayout(activity)
  col.setOrientation(1)
  col.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
  col.setPadding(dp(10), 0, dp(4), 0)

  local nameTv = MaterialTextView(activity)
  nameTv.setText(name)
  nameTv.setTextSize(15)
  nameTv.setTextColor(ColorOnSurface)
  nameTv.setSingleLine(true)
  col.addView(nameTv)

  local metaTv = MaterialTextView(activity)
  metaTv.setText(convMetaText(conv))
  metaTv.setTextSize(12)
  metaTv.setTextColor(ColorText)
  metaTv.setSingleLine(true)
  col.addView(metaTv)

  local function smallButton(text, bgColor, textColor)
    local btn = MaterialButton(activity)
    btn.setText(text)
    btn.setTextSize(12)
    btn.setAllCaps(false)
    btn.setMinWidth(0)
    btn.setMinHeight(0)
    btn.setPadding(dp(12), 0, dp(12), 0)
    btn.setBackgroundTintList(ColorStateList.valueOf(bgColor))
    btn.setTextColor(textColor)
    btn.setLayoutParams(LinearLayout.LayoutParams(-2, -2))
    return btn
  end

  local btnRow = LinearLayout(activity)
  btnRow.setOrientation(0)
  btnRow.setGravity(android.view.Gravity.END)
  local btnRowParams = LinearLayout.LayoutParams(-1, -2)
  btnRowParams.topMargin = dp(6)
  btnRow.setLayoutParams(btnRowParams)

  local renBtn = smallButton(S.ai_rename_btn, ColorSecondaryContainer, ColorOnSecondaryContainer)
  renBtn.setOnClickListener(function() showRenameDialog(convId, name) end)
  btnRow.addView(renBtn)

  local delBtn = smallButton(S.ai_delete, ColorErrorContainer, ColorOnErrorContainer)
  local delBtnParams = LinearLayout.LayoutParams(-2, -2)
  delBtnParams.leftMargin = dp(8)
  delBtn.setLayoutParams(delBtnParams)
  delBtn.setOnClickListener(function()
    MaterialAlertDialogBuilder(activity)
      .setTitle(S.ai_delete_conv)
      .setMessage(S.ai_confirm_delete_conv:format(name))
      .setPositiveButton(S.ai_delete, function()
        invalidateRequest()
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
  end)
  btnRow.addView(delBtn)

  col.addView(btnRow)
  row.addView(col)

  return row
end

local function showConvList()
  local list = AgentChat.listConversations()
  local currentConv = AgentChat.getCurrentConv()
  local currentId = currentConv and currentConv.id or nil

  if #list == 0 then
    local created = AgentChat.createConversation()
    activeConversationId = created and created.id or nil
    activeConversationProjectPath = created and AgentChat.getCurrentProjectPath() or nil
    conversationLoaded = created ~= nil
    activeConversationHadMessages = false
    messages = created and created.messages or {}
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
      saveHistory()
      invalidateRequest()
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
    invalidateRequest()
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
    invalidateRequest()
    local created = AgentChat.createConversation()
    activeConversationId = created and created.id or nil
    activeConversationProjectPath = created and AgentChat.getCurrentProjectPath() or nil
    conversationLoaded = created ~= nil
    activeConversationHadMessages = false
    messages = {}
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
    radius = "12dp", CardElevation = 0,
    CardBackgroundColor = ColorSurface,
    layout_marginBottom = "8dp",
    {
      LinearLayout,
      orientation = "vertical",
      padding = "14dp",
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
  views.msgContainer.addView(loadlayout(welcome, welcomeViews))
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
  invalidateRequest()
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
      stopRequested = true
      if activeToolConfirm then activeToolConfirm.cancel() end
      AgentChat.cancelPendingRequest()
      if AgentChat.cancelPendingTools then AgentChat.cancelPendingTools() end
      local stopTool = activeToolStop
      activeToolStop = nil
      if stopTool then pcall(stopTool) end
      isLoading = false
      hideLoading()
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
      invalidateRequest()
      saveHistory()
      local created = AgentChat.createConversation()
      activeConversationId = created and created.id or nil
      activeConversationProjectPath = created and AgentChat.getCurrentProjectPath() or nil
      conversationLoaded = created ~= nil
      activeConversationHadMessages = false
      messages = {}
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
    local historyCount = loadHistory(not isLoading)
    if historyCount == 0 then
      addWelcomeCard(S.ai_welcome_title, S.ai_welcome_body)
    end
  end

  dialog.setOnShowListener(function()
    expandSheet(dialog, content)
  end)
  dialog.show()
  expandSheet(dialog, content)
  if isLoading then showLoading() end
  if activeStream and activeStream.render then activeStream.render() end

  if not AgentChat.hasApiKey() then
    content.post(function()
      showModelPicker()
    end)
  end

  return dialog
end

function _M.onBeforeProjectChange()
  saveHistory()
  invalidateRequest()
  conversationLoaded = false
  activeConversationId = nil
  activeConversationProjectPath = nil
  activeConversationHadMessages = false
end

function _M.refreshProjectContext()
  invalidateRequest()
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

return _M
