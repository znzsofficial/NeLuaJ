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
local undoTurns = {}
local redoTurns = {}

-- 前向声明
local saveHistory, loadHistory, showModelManager, showModelPicker, showConvManager, showConvList, showSettings, addMessageBubble, addToolBubble, updateProjectLabel

-- ─── UI 辅助 ──

local function isToolError(toolName, result)
  if not result then return false end
  local r = tostring(result):lower()
  if toolName == "read_file" or toolName == "read_files"
      or toolName == "list_dir" or toolName == "search_in_files" then
    return result:find("读取文件失败", 1, true)
      or result:find("读取目录失败", 1, true)
      or result:find("搜索失败", 1, true)
      or r:match("^error[:：]") ~= nil
      or r:match("^exception[:：]") ~= nil
  end
  return result:find("读取文件失败", 1, true)
    or result:find("读取目录失败", 1, true)
    or result:find("搜索失败", 1, true)
    or result:find("失败", 1, true)
    or result:find("异常", 1, true)
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

local function updateSafetyStatus()
  if not views.autoApproveStatus then return end
  local enabled = this.getSharedData("ai_auto_approve", "0") == "1"
  views.autoApproveStatus.setVisibility(enabled and VISIBLE or GONE)
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
local function copyText(text)
  pcall(function()
    local ClipboardManager = luajava.bindClass("android.content.ClipboardManager")
    local ClipData = luajava.bindClass("android.content.ClipData")
    local cm = activity.getSystemService("clipboard")
    cm.setPrimaryClip(ClipData.newPlainText("agent_code", text))
    if MainActivity and MainActivity.Public then
      MainActivity.Public.snack(S.ai_copied)
    end
  end)
end

addMessageBubble = function(role, content)
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
              onClick = function() copyText(part.code) end,
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
  elseif toolName == "get_env_info" then icon = "ℹ" end

  local resultText = tostring(result or "")
  local resultLower = resultText:lower()
  local denied = resultText == tostring(S.ai_user_denied)
    or resultText:find("用户拒绝", 1, true) ~= nil
    or resultLower:find("user declined", 1, true) ~= nil
  local status = result == nil and S.ai_tool_pending
    or (denied and S.ai_tool_denied or (isError and S.ai_tool_failed or S.ai_tool_success))
  local summary = icon .. " " .. toolDisplayName(toolName) .. "  ·  " .. status
  local detailParts = {}
  if args.path then detailParts[#detailParts + 1] = tostring(args.path) end
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
    if toolName == "read_files" and not isError then
      local files = args.paths
      local n = type(files) == "table" and #files or (type(files) == "string" and 1 or 0)
      display = S.ai_read_files_summary:format(n)
    end
    if #display > 12000 then
      display = display:sub(1, 12000) .. "\n\n" .. S.ai_tool_output_truncated
    end
    detailParts[#detailParts + 1] = tostring(display)
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
  container.addView(loadlayout(card, bubbleViews))
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
end

-- ─── 加载状态 ──

local function showLoading()
  isLoading = true
  if views.loadingBar then views.loadingBar.setVisibility(VISIBLE) end
  if views.btnSend then views.btnSend.setEnabled(false) end
  if views.btnSend then views.btnSend.setVisibility(GONE) end
  if views.btnStop then views.btnStop.setVisibility(VISIBLE) end
  if views.btnStop then views.btnStop.setEnabled(true) end
end

local function hideLoading()
  isLoading = false
  if views.loadingBar then views.loadingBar.setVisibility(GONE) end
  if views.btnSend then views.btnSend.setEnabled(true) end
  if views.btnSend then views.btnSend.setVisibility(VISIBLE) end
  if views.btnStop then views.btnStop.setVisibility(GONE) end
  if views.btnStop then views.btnStop.setEnabled(true) end
end

local function invalidateRequest()
  requestGeneration = requestGeneration + 1
  isLoading = false
  AgentChat.cancelPendingRequest()
  okHttp.cancelAll()
  hideLoading()
  return requestGeneration
end

local function refreshMessageList()
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
  saveHistory()
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
        if MainActivity and MainActivity.Public then
          MainActivity.Public.snack(tostring(result and result.error or "文件变更恢复失败"))
        end
        return
      end
      if MainActivity and MainActivity.RecyclerView then MainActivity.RecyclerView.update() end
      if views.msgContainer then views.msgContainer.removeAllViews() end
      loadHistory()
      if MainActivity and MainActivity.Public then
        MainActivity.Public.snack(tostring(result.error or "文件变更已恢复"))
      end
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

local function compressCurrentContext()
  if isLoading then return false end
  requestGeneration = requestGeneration + 1
  local generation = requestGeneration
  showLoading()
  AgentChat.buildCompressedApiMessages(messages, function(apiMessages, compressed)
    if generation ~= requestGeneration then return end
    hideLoading()
    if not compressed then
      if MainActivity and MainActivity.Public then MainActivity.Public.snack(S.ai_compress_unavailable) end
      return
    end
    local compacted = {}
    for i = 2, #apiMessages do compacted[#compacted + 1] = apiMessages[i] end
    messages = compacted
    undoTurns = {}
    redoTurns = {}
    saveHistory()
    refreshMessageList()
    if MainActivity and MainActivity.Public then
      MainActivity.Public.snack(S.ai_compress_done:format(#messages))
    end
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
    message = S.ai_confirm_delete:format(args.path)
  elseif toolName == "delete_folder" then
    title = S.ai_delete_folder
    message = S.ai_confirm_delete_folder:format(args.path)
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
    local preview = args.code or ""
    if #preview > 600 then preview = preview:sub(1, 600) .. "\n…" end
    message = S.ai_confirm_code:format(preview)
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
  elseif toolName == "read_file" or toolName == "read_files"
      or toolName == "list_dir" or toolName == "search_in_files" then
    title = S.ai_confirm_external_read_title
    local target = args.path or (type(args.paths) == "table" and table.concat(args.paths, "\n")) or args.paths or "?"
    message = S.ai_confirm_external_read_message:format(tostring(target))
  else
    title = S.ai_confirm_tool_title
    message = S.ai_confirm_tool_message:format(toolDisplayName(toolName))
  end

  MaterialAlertDialogBuilder(activity)
    .setTitle(title)
    .setMessage(message)
    .setPositiveButton(S.ai_allow, function()
      if onAllow then onAllow() end
    end)
    .setNegativeButton(S.ai_deny, function()
      if onDeny then onDeny() end
    end)
    .show()
end

-- ─── 执行工具调用链 ──

local function executeToolCalls(toolCalls, index, results, onAllDone, generation)
  if generation and generation ~= requestGeneration then return end
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
  pcall(function() args = json.decode(tc.arguments) end)
  if type(args) ~= "table" then args = {} end
  tc.name = AgentChat.normalizeToolName(tc.name, args)

  local function proceedWithResult(resultStr)
    if generation and generation ~= requestGeneration then return end
    results[#results + 1] = {
      tool_call_id = tc.id,
      content = resultStr,
    }
    addToolBubble(tc.name, args, resultStr)
    executeToolCalls(toolCalls, index + 1, results, onAllDone, generation)
  end

  if AgentChat.shouldAutoApprove(tc.name, args) then
    AgentChat.executeToolAsync(tc.name, args, proceedWithResult)
  elseif (AgentChat.requiresConfirmation and AgentChat.requiresConfirmation(tc.name, args))
      or AgentChat.isDestructiveTool(tc.name) then
    showToolConfirm(tc.name, args, function()
      if generation and generation ~= requestGeneration then return end
      AgentChat.executeToolAsync(tc.name, args, proceedWithResult)
    end, function()
      if generation and generation ~= requestGeneration then return end
      proceedWithResult(S.ai_user_denied)
    end)
  else
    AgentChat.executeToolAsync(tc.name, args, proceedWithResult)
  end
end

-- ─── 会话持久化 ──

saveHistory = function()
  AgentChat.saveCurrentConv(messages)
end

loadHistory = function(resetTurnHistory)
  if resetTurnHistory ~= false then
    undoTurns = {}
    redoTurns = {}
  end
  if AgentChat.clearActiveSkill then AgentChat.clearActiveSkill() end
  local conv, idx = AgentChat.getCurrentConv()
  if not conv or not conv.messages or #conv.messages == 0 then
    -- 自动创建新会话
    AgentChat.createConversation()
    if updateProjectLabel then updateProjectLabel() end
    return 0
  end
  messages = conv.messages
  if updateProjectLabel then updateProjectLabel() end
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
        if content ~= "" then
          addMessageBubble("assistant", content)
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
      end
    end
  end
  return #messages
end

-- ─── 发送消息核心 ──

local lastApiMessages = nil
local toolRoundCount = 0
local MAX_TOOL_ROUNDS = 30
local sendWithCompressedContext

local function sendToApi(apiMessages, isContinue)
  local generation = requestGeneration
  local function isCurrent()
    return generation == requestGeneration
  end
  lastApiMessages = apiMessages
  if not isContinue then
    toolRoundCount = 0
  end
  showLoading()

  -- 上下文用量显示：估算本次将发送的 token 数
  if views.ctxUsage then
    local u = AgentChat.estimateApiMessagesUsage(apiMessages)
    if type(u) == "table" then
      local used, budget = tonumber(u.used) or 0, tonumber(u.budget) or 0
      local ratio = budget > 0 and used / budget or 0
      local color = ColorText
      if ratio >= 0.95 then color = ColorError
      elseif ratio >= 0.8 then color = 0xffe6a23c end
      views.ctxUsage.setTextColor(color)
      views.ctxUsage.setText(used .. " / " .. budget .. " tok")
    end
  end

  -- 空气泡用于流式输出
  local container = views.msgContainer
  local streamViews = {}
  local card = {
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
        text = "",
        textSize = "13sp",
        textColor = ColorOnSurface,
        lineSpacingMultiplier = 1.35,
      },
    },
  }
  container.addView(loadlayout(card, streamViews))
  local aiTextView = streamViews.aiStreamText
  local fullResponse = ""

  AgentChat.sendStream(apiMessages, {
    onPrepared = function(usage)
      if not isCurrent() or type(usage) ~= "table" then return end
      local used = tonumber(usage.used) or 0
      local budget = tonumber(usage.budget) or 0
      local ratio = budget > 0 and used / budget or 0
      local color = ColorText
      if ratio >= 0.95 then color = ColorError
      elseif ratio >= 0.8 then color = 0xffe6a23c end
      if views.ctxUsage then
        views.ctxUsage.setTextColor(color)
        views.ctxUsage.setText(used .. " / " .. budget .. " tok")
      end
    end,
    onChunk = function(chunk)
      if not isCurrent() then return end
      fullResponse = fullResponse .. chunk
      if aiTextView then
        aiTextView.append(tostring(chunk))
        scrollDown()
      end
    end,
    -- 自动重试前清空已流出的内容，避免失败段落重复拼接
    onRetry = function()
      if not isCurrent() then return end
      fullResponse = ""
      if aiTextView then aiTextView.setText("") end
    end,
    onToolCalls = function(toolCalls, text)
      if not isCurrent() then return end
      -- 不调用 hideLoading，保持加载状态直到续请求完成
      -- 移除空对话气泡（无文本内容时）
      if not text or text == "" then
        local parent = aiTextView and aiTextView.getParent()
        if parent then
          local grandparent = parent.getParent()
          if grandparent then
            container.removeView(grandparent)
          end
        end
      end

      -- 保存 assistant 消息（含 tool_calls）
      local assistantMsg = { role = "assistant" }
      if text and text ~= "" then
        assistantMsg.content = text
      end
      assistantMsg.tool_calls = {}
      for _, tc in ipairs(toolCalls) do
        assistantMsg.tool_calls[#assistantMsg.tool_calls + 1] = {
          id = tc.id,
          type = "function",
          ["function"] = {
            name = tc.name,
            arguments = tc.arguments,
          },
        }
      end
      messages[#messages + 1] = assistantMsg
      saveHistory()

      -- 执行工具调用
      executeToolCalls(toolCalls, 1, {}, function(results)
        if not isCurrent() then return end
        -- 把每个 tool 结果加入 messages
        for _, r in ipairs(results) do
          messages[#messages + 1] = {
            role = "tool",
            tool_call_id = r.tool_call_id,
            content = r.content,
          }
          saveHistory()
        end

        -- 防止无限循环
        toolRoundCount = toolRoundCount + 1
        if toolRoundCount >= MAX_TOOL_ROUNDS then
          hideLoading()
          addMessageBubble("assistant", S.ai_max_tool_rounds:format(MAX_TOOL_ROUNDS))
          messages[#messages + 1] = { role = "assistant", content = S.ai_max_tool_rounds:format(MAX_TOOL_ROUNDS) }
          saveHistory()
          return
        end

        -- 继续对话（可能还有更多工具调用或最终文本）
        sendWithCompressedContext(true)
      end, generation)
    end,
    onDone = function(text)
      if not isCurrent() then return end
      hideLoading()
      messages[#messages + 1] = { role = "assistant", content = text }
      saveHistory()
      -- 移除流式空气泡，用 Markdown 重新渲染最终内容
      local parent = aiTextView and aiTextView.getParent()
      if parent then
        local grandparent = parent.getParent()
        if grandparent then
          container.removeView(grandparent)
        end
      end
      addMessageBubble("assistant", text)
    end,
    onError = function(err)
      if not isCurrent() then return end
      hideLoading()
      -- 用户主动停止：保留已生成部分，不显示错误
      if tostring(err):lower():match("cancel") then
        if fullResponse ~= "" then
          messages[#messages + 1] = { role = "assistant", content = fullResponse }
          saveHistory()
        end
        if aiTextView then
          local partial = fullResponse
          if partial == "" then partial = S.ai_stopped end
          aiTextView.setText(partial .. "\n\n" .. S.ai_stopped_tag)
        end
        return
      end
      -- 替换气泡内容为错误 + 重试按钮
      local parent = aiTextView and aiTextView.getParent()
      if parent then
        parent.removeAllViews()
        parent.addView(loadlayout({
          MaterialTextView,
          text = tostring(err),
          textSize = "13sp",
          textColor = ColorError,
          padding = "12dp",
          lineSpacingMultiplier = 1.3,
        }))
        parent.addView(loadlayout({
          MaterialButton,
          text = S.ai_retry,
          textSize = "12sp",
          textColor = ColorPrimary,
          layout_width = "wrap",
          layout_height = "32dp",
          layout_marginTop = "6dp",
          BackgroundTintList = ColorStateList.valueOf(0),
          icon = res.drawable("sync"),
          iconTint = ColorStateList.valueOf(ColorPrimary),
          onClick = function()
            if lastApiMessages then
              -- 移除错误气泡
              local grandparent = parent.getParent()
              if grandparent then
                container.removeView(grandparent)
              end
              -- 移除错误消息（最后一条 assistant 消息）
              if messages[#messages] and messages[#messages].role == "assistant" then
                table.remove(messages)
              end
              -- 重试
              sendToApi(lastApiMessages)
            end
          end,
        }))
      end
    end,
  })
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
  AgentChat.buildCompressedApiMessages(requestHistory, function(apiMessages)
    if generation ~= requestGeneration then return end
    sendToApi(apiMessages, isContinue)
  end)
end

-- ─── 发送消息 ──

local function sendMessage()
  if isLoading then return end

  local input = views.msgInput
  if not input then return end

  local text = tostring(input.getText() or ""):match("^%s*(.-)%s*$")
  if text == "" then return end

  input.setText("")

  local skill = AgentChat.selectSkill(text)

  addMessageBubble("user", text)
  messages[#messages + 1] = { role = "user", content = text }
  if skill then
    local conv = AgentChat.getCurrentConv()
    conv.skills = conv.skills or {}
    conv.skills[skill.name] = true
    saveHistory()
  end
  redoTurns = {}
  saveHistory()

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
  requestGeneration = requestGeneration + 1
  sendWithCompressedContext(false, userMsg)
end

-- ─── 模型管理 ──

local function showModelEditor(existingIndex, existingName, existingUrl, existingKey, existingModel)
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
  }

  local dialogViews = {}
  local content = loadlayout(inputLayout, dialogViews)

  MaterialAlertDialogBuilder(activity)
    .setTitle(existingIndex and S.ai_edit_model or S.ai_add_model)
    .setView(content)
    .setPositiveButton(S.ai_save, function()
      local name = tostring(dialogViews.nameInput.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
      local key = tostring(dialogViews.keyInput.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
      local url = tostring(dialogViews.urlInput.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
      local model = tostring(dialogViews.modelInput.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
      if name == "" then name = model end
      if key == "" then
        if MainActivity and MainActivity.Public then MainActivity.Public.snack(S.ai_need_api_key) end
        return
      end
      if existingIndex then
        AgentChat.updateModel(existingIndex, name, url, key, model)
        AgentChat.setCurrentModel(existingIndex)
      else
        local newIndex = AgentChat.addModel(name, url, key, model)
        AgentChat.setCurrentModel(newIndex)
      end
      if views.modelLabel then views.modelLabel.setText(AgentChat.getCurrentModelName()) end
      if MainActivity and MainActivity.Public then MainActivity.Public.snack(S.ai_saved) end
      showModelPicker()  -- 刷新列表
    end)
    .setNegativeButton(S.ai_cancel, nil)
    .show()

  dialogViews.nameInput.setText(existingName or "")
  dialogViews.keyInput.setText(existingKey or "")
  dialogViews.urlInput.setText(existingUrl or "")
  dialogViews.modelInput.setText(existingModel or "")
end

showModelManager = function()
  local models = AgentChat.loadModels()
  if #models == 0 then
    showModelEditor()
    return
  end

  local labels = {}
  for i, m in ipairs(models) do
    labels[i] = m.name .. "  (" .. m.model .. ")"
  end

  MaterialAlertDialogBuilder(activity)
    .setTitle(S.ai_manage_model)
    .setItems(labels, function(_, which)
      local m = models[which + 1]
      MaterialAlertDialogBuilder(activity)
        .setTitle(m.name)
        .setMessage(S.ai_api_key .. ": " .. m.key:sub(1, 12) .. "…\n" .. S.ai_api_url .. ": " .. m.url .. "\n" .. S.ai_model .. ": " .. m.model)
        .setPositiveButton(S.ai_edit, function()
          showModelEditor(which + 1, m.name, m.url, m.key, m.model)
        end)
        .setNegativeButton(S.ai_delete, function()
          AgentChat.removeModel(which + 1)
          if MainActivity and MainActivity.Public then MainActivity.Public.snack(S.ai_deleted_name:format(m.name)) end
          if views.modelLabel then views.modelLabel.setText(AgentChat.getCurrentModelName()) end
          showModelManager()
        end)
        .setNeutralButton(S.ai_cancel, nil)
        .show()
    end)
    .setPositiveButton(S.ai_add, function()
      showModelEditor()
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
    labels[i] = marker .. m.name .. "  (" .. m.model .. ")"
  end
  labels[#labels + 1] = S.ai_add_model_item

  MaterialAlertDialogBuilder(activity)
    .setTitle(S.ai_switch_model)
    .setItems(labels, function(_, which)
      if which == #models then
        showModelEditor()
      else
        AgentChat.setCurrentModel(which + 1)
        if views.modelLabel then views.modelLabel.setText(AgentChat.getCurrentModelName()) end
        if MainActivity and MainActivity.Public then MainActivity.Public.snack(S.ai_switched_to:format(models[which + 1].name)) end
      end
    end)
    .setNegativeButton(S.ai_manage, function()
      showModelManager()
    end)
    .setNeutralButton(S.ai_settings, function()
      showSettings()
    end)
    .setPositiveButton(S.ai_close, nil)
    .show()
end

showSettings = function()
  local autoApprove = this.getSharedData("ai_auto_approve", "0") == "1"
  local allowSelfSigned = this.getSharedData("ai_allow_selfsigned", "0") == "1"
  local temp = this.getSharedData("ai_temperature", "0.7")
  local maxTokens = this.getSharedData("ai_max_tokens", "4096")
  local contextLen = this.getSharedData("ai_context_length", "30000")
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
          text = S.ai_max_tokens,
          textSize = "13sp", textColor = ColorText,
        },
        {
          EditText,
          id = "maxTokensInput",
          text = tostring(maxTokens),
          layout_width = "match", layout_height = "wrap", minHeight = "40dp",
          textSize = "14sp", singleLine = true,
          inputType = 0x0002,
          layout_marginBottom = "8dp",
        },
        {
          MaterialTextView,
          text = S.ai_context_len,
          textSize = "13sp", textColor = ColorText,
        },
        {
          EditText,
          id = "contextInput",
          text = tostring(contextLen),
          layout_width = "match", layout_height = "wrap", minHeight = "40dp",
          textSize = "14sp", singleLine = true,
          inputType = 0x0002,
          hint = S.ai_ctx_hint,
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
          MaterialTextView,
          id = "autoApproveWarning",
          text = S.ai_auto_approve_warning,
          textSize = "12sp",
          textColor = ColorError,
          layout_marginTop = "8dp",
          visibility = autoApprove and VISIBLE or GONE,
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

  dlgViews.autoApproveSwitch.setOnCheckedChangeListener(function(_, checked)
    dlgViews.autoApproveWarning.setVisibility(checked and VISIBLE or GONE)
  end)

  dlgViews.btnTestConn.onClick = function()
    AgentChat.testConnection(function(ok, msg)
      if MainActivity and MainActivity.Public then
        MainActivity.Public.snack(msg)
      end
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
      row.setOrientation(0)
      row.setGravity(16)
      row.setPadding(dp(12), dp(10), dp(12), dp(10))
      local lp = LinearLayout.LayoutParams(-1, -2)
      lp.bottomMargin = dp(8)
      row.setLayoutParams(lp)
      local bg = GradientDrawable()
      bg.setColor(ColorUtils.blendARGB(ColorSurface, 0xffffffff, 0.35))
      bg.setCornerRadius(dp(14))
      row.setBackground(bg)

      local txtCol = LinearLayout(activity)
      txtCol.setOrientation(1)
      txtCol.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
      txtCol.setPadding(0, 0, dp(8), 0)
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

      local testBtn = mcpBtn(S.ai_test, ColorPrimary, ColorOnPrimary)
      local testLp = LinearLayout.LayoutParams(-2, dp(34))
      testLp.leftMargin = dp(8)
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
            if MainActivity and MainActivity.Public then MainActivity.Public.snack(sname .. ": " .. feedback) end
          end)
        end)
      end)
      row.addView(testBtn)

       local delBtn = mcpBtn(S.ai_delete, ColorErrorContainer, ColorOnErrorContainer)
      local delLp = LinearLayout.LayoutParams(-2, dp(34))
      delLp.leftMargin = dp(8)
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
      row.addView(delBtn)
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
    MaterialAlertDialogBuilder(activity)
      .setTitle(S.ai_add_mcp)
      .setView(formContent)
      .setPositiveButton(S.ai_ok, function()
        local sname = tostring(inViews.nameInput.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
        local surl = tostring(inViews.urlInput.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
        local sheaders = tostring(inViews.headerInput.getText() or "")
        if sname == "" or surl == "" then
          if MainActivity and MainActivity.Public then
            MainActivity.Public.snack(S.ai_name_url_required)
          end
          return
        end
        local headers = {}
        for line in sheaders:gmatch("[^\r\n]+") do
          local k, v = line:match("^%s*([^:%s]+)%s*:%s*(.*)%s*$")
          if k then headers[k] = v end
        end
        local servers = MCPClient.getServers()
        servers[#servers + 1] = { name = sname, url = surl, headers = headers }
        MCPClient.setServers(servers)
        MCPClient.refreshToolsAsync()
        renderMcpList()
      end)
      .setNegativeButton(S.ai_cancel, nil)
      .show()
  end

  local function addPresetServer(name, url)
    local servers = MCPClient.getServers()
    for _, s in ipairs(servers) do
      if tostring(s.name or "") == name then
        if MainActivity and MainActivity.Public then
          MainActivity.Public.snack(S.ai_exists:format(name))
        end
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
      this.setSharedData("ai_allow_selfsigned", dlgViews.selfSignedSwitch.isChecked() and "1" or "0")
      local tempVal = tostring(dlgViews.tempInput.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
      local mtVal = tostring(dlgViews.maxTokensInput.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
      local ctxVal = tostring(dlgViews.contextInput.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
      local retryVal = tostring(dlgViews.retryInput.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
      local promptVal = tostring(dlgViews.promptInput.getText() or "")
      if tempVal ~= "" then this.setSharedData("ai_temperature", tempVal) end
      if mtVal ~= "" then this.setSharedData("ai_max_tokens", mtVal) end
      if ctxVal ~= "" then this.setSharedData("ai_context_length", ctxVal) end
      if retryVal ~= "" then this.setSharedData("ai_retry_count", retryVal) end
      this.setSharedData("ai_system_prompt", promptVal)
      updateSafetyStatus()
      if MainActivity and MainActivity.Public then
        MainActivity.Public.snack(S.ai_settings_saved)
      end
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

local function convName(conv)
  local n = conv and conv.name or ""
  if n == "" then return S.ai_unnamed_conv end
  return n
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

local function showRenameDialog(index, oldName)
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
      if name ~= "" then
        AgentChat.renameConversation(index, name)
        if views.aiTitle and index == AgentChat.getCurrentConvIndex() then
          local c = AgentChat.getCurrentConv()
          if c then views.aiTitle.setText(convName(c)) end
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

local function buildManagerRow(conv, index, render)
  local name = convName(conv)
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
  row.addView(col)

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

  local renBtn = smallButton(S.ai_rename_btn, ColorSecondaryContainer, ColorOnSecondaryContainer)
  renBtn.setOnClickListener(function() showRenameDialog(index, name) end)
  row.addView(renBtn)

  local delBtn = smallButton(S.ai_delete, ColorErrorContainer, ColorOnErrorContainer)
  delBtn.setOnClickListener(function()
    MaterialAlertDialogBuilder(activity)
      .setTitle(S.ai_delete_conv)
      .setMessage(S.ai_confirm_delete_conv:format(name))
      .setPositiveButton(S.ai_delete, function()
        invalidateRequest()
        AgentChat.deleteConversation(index)
        if AgentChat.getCurrentConvIndex() == 0 then AgentChat.createConversation() end
        messages = {}
        if views.msgContainer then views.msgContainer.removeAllViews() end
        loadHistory()
        if views.aiTitle then
          local c = AgentChat.getCurrentConv()
          if c then views.aiTitle.setText(convName(c)) end
        end
        if MainActivity and MainActivity.Public then MainActivity.Public.snack(S.ai_deleted) end
        render()
      end)
      .setNegativeButton(S.ai_cancel, nil)
      .show()
  end)
  row.addView(delBtn)

  return row
end

local function showConvList()
  local convs = AgentChat.loadConversations()
  local current = AgentChat.getCurrentConvIndex()

  local projectPath = AgentChat.getCurrentProjectPath()
  local visible = {}
  for index, conv in ipairs(convs) do
    if conv.projectPath == projectPath then visible[#visible + 1] = { index = index, conv = conv } end
  end
  if #visible == 0 then
    AgentChat.createConversation()
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
           text = S.ai_conv_count:format(#visible),
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
  for _, item in ipairs(visible) do
    local idx, conv = item.index, item.conv
    local row = buildConvRow(conv, idx == current, function()
      saveHistory()
      invalidateRequest()
      AgentChat.setCurrentConv(idx)
      if AgentChat.syncAgentProjectScope then AgentChat.syncAgentProjectScope() end
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
    AgentChat.createConversation()
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
  local convs = AgentChat.loadConversations()
  if #convs == 0 then return end

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
          text = S.ai_conv_count:format(#convs),
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
    local convs2 = AgentChat.loadConversations()
    local projectPath = AgentChat.getCurrentProjectPath()
    container.removeAllViews()
    for i, conv in ipairs(convs2) do
      if conv.projectPath == projectPath then
        container.addView(buildManagerRow(conv, i, render))
      end
    end
    local count = 0
    for _, conv in ipairs(convs2) do if conv.projectPath == projectPath then count = count + 1 end end
    if dlgViews.convCount then dlgViews.convCount.setText(S.ai_conv_count:format(count)) end
  end

  dlgViews.btnNew.onClick = function()
    saveHistory()
    AgentChat.createConversation()
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
        textSize = "12sp",
        layout_width = "wrap",
        layout_height = "40dp",
        layout_marginTop = "8dp",
        includeFontPadding = false,
         BackgroundTintList = ColorStateList.valueOf(ColorSecondaryContainer),
         textColor = ColorOnSecondaryContainer,
      },
    },
  }
  views.msgContainer.addView(loadlayout(welcome, welcomeViews))
  welcomeViews.btnWelcomeHelp.onClick = function() showAgentHelp() end
end

local function clearChat()
  invalidateRequest()
  messages = {}
  saveHistory()
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

-- ─── 显示聊天面板 ──

function _M.show()
  if dialog and dialog.isShowing() then
    saveHistory()
    dialog.dismiss()
  end

  views = {}
  local content = loadlayout(res.layout.ai_chat_panel, views)

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
    end
  end)

  -- 关闭时保存会话
  dialog.setOnDismissListener(function()
    invalidateRequest()
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
      -- 先让当前流回调保存部分响应，再使工具链和续请求的 generation 失效。
      AgentChat.cancelPendingRequest()
      requestGeneration = requestGeneration + 1
      isLoading = false
      okHttp.cancelAll()
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

  if views.autoApproveStatus then
    views.autoApproveStatus.setClickable(true)
    views.autoApproveStatus.setFocusable(true)
    views.autoApproveStatus.onClick = function() showSettings() end
    updateSafetyStatus()
  end

  if views.btnClear then
    views.btnClear.onClick = function()
      invalidateRequest()
      saveHistory()
      AgentChat.createConversation()
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
  if views.modelLabel then
    views.modelLabel.setText(AgentChat.getCurrentModelName())
  end

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
    local historyCount = loadHistory()
    if historyCount == 0 then
      addWelcomeCard(S.ai_welcome_title, S.ai_welcome_body)
    end
  end

  dialog.setOnShowListener(function()
    expandSheet(dialog, content)
  end)
  dialog.show()
  expandSheet(dialog, content)

  if not AgentChat.hasApiKey() then
    content.post(function()
      showModelPicker()
    end)
  end

  return dialog
end

function _M.refreshProjectContext()
  if not dialog or not dialog.isShowing() then return end
  invalidateRequest()
  if views.msgContainer then views.msgContainer.removeAllViews() end
  loadHistory()
  local conv = AgentChat.getCurrentConv()
  if views.aiTitle then views.aiTitle.setText(conv and convName(conv) or S.ai_new_conv) end
  updateProjectLabel()
end

-- ─── 插入代码到编辑器 ──

function _M.insertCode(code)
  if not mLuaEditor or mLuaEditor.getVisibility() ~= 0 then
    if MainActivity and MainActivity.Public then
      MainActivity.Public.snack(S.ai_need_open_file)
    end
    return
  end

  local startPos = mLuaEditor.getSelectionStart()
  local text = tostring(mLuaEditor.getText() or "")
  local newText = text:sub(1, startPos) .. code .. text:sub(startPos + 1)
  mLuaEditor.setText(newText)
  mLuaEditor.setSelection(startPos + #code)

  if MainActivity and MainActivity.Public then
    MainActivity.Public.snack(S.ai_inserted)
  end
end

return _M
