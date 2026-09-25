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
local LinkMovementMethod = luajava.bindClass("android.text.method.LinkMovementMethod")
local Typeface = luajava.bindClass("android.graphics.Typeface")
local ProgressBar = luajava.bindClass("android.widget.ProgressBar")
local WindowManager = luajava.bindClass("android.view.WindowManager")
local DialogInterface = luajava.bindClass("android.content.DialogInterface")

import "androidx.core.graphics.ColorUtils"

local AgentChat = require("mods.agent.AgentChat")
local AgentTurn = require("mods.agent.AgentTurn")
local MCPClient = require("mods.agent.MCPClient")
local TodoManager = require("mods.agent.TodoManager")
local SubagentRunner = require("mods.agent.SubagentRunner")
local TextUtil = require("mods.utils.TextUtil")
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
    run_subtask = S.ai_tool_subtask,
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

-- ─── Markdown 渲染辅助（已抽到 mods/agent/Markdown）──
local Markdown = require("mods.agent.Markdown")
local renderMarkdown = Markdown.renderMarkdown
local splitCodeBlocks = Markdown.splitCodeBlocks
--- 复制文本到剪贴板
-- ─── 气泡渲染层（已抽到 mods/agent/BubbleRenderer）──
-- 容器/消息表/回调节点经 configure 注入；渲染入口保持原局部名转发，
-- loadHistory / AgentTurn 钩子 / SubagentRunner 进度等调用点零改动。
local BubbleRenderer = require("mods.agent.BubbleRenderer")
BubbleRenderer.configure({
  scrollDown = scrollDown,
  isPanelVisible = isPanelVisible,
  getContainer = function() return views.msgContainer end,
  getMessages = function() return messages end,
  saveHistory = function(updates) saveHistory(updates) end,
  isToolError = isToolError,
  toolDisplayName = toolDisplayName,
  insertCode = function(code) _M.insertCode(code) end,
})
addMessageBubble = BubbleRenderer.renderMessage
addToolBubble = BubbleRenderer.renderTool

--- 任务计划置顶条：显示当前计划的完成进度，点击弹出完整清单。
--- 数据源就是 TodoManager 的实时状态（系统提示注入的同一份）。
local function updatePlanStrip()
  if not views.planStrip then return end
  local todos = TodoManager.get()
  if not todos or #todos == 0 then
    views.planStrip.setVisibility(GONE)
    return
  end
  local done = 0
  for _, item in ipairs(todos) do
    if item.status == "completed" then done = done + 1 end
  end
  views.planLabel.setText(S.ai_todo)
  views.planProgress.setText(S.ai_plan_progress:format(done, #todos))
  views.planStrip.setVisibility(VISIBLE)
end

--- 编辑器上下文指示：显示发送时将附带的上下文摘要，点击预览/本次跳过。
--- buildContext 静默拼接当前文件内容——这里让它可见、可控。
local skipContext = false

local function updateContextChip()
  if not views.ctxChip then return end
  local context = AgentChat.buildContext()
  if context == "" then
    skipContext = false
    views.ctxChip.setVisibility(GONE)
    return
  end
  local thisFile = Bean and Bean.Path and Bean.Path.this_file or ""
  local name = thisFile ~= "" and tostring(thisFile):gsub("^.*/", "") or S.ai_ctx_env
  local label
  if skipContext then
    label = "📎 " .. S.ai_ctx_skipped
  else
    local tokens = 0
    pcall(function()
      local ContextManager = require("mods.agent.ContextManager")
      tokens = ContextManager.estimateTokens(context)
    end)
    label = "📎 " .. S.ai_ctx_chip:format(name) .. " · ~" .. tokens .. " tokens"
  end
  views.ctxChip.setText(label)
  views.ctxChip.setVisibility(VISIBLE)
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
    raw = TextUtil.utf8Cap(raw, 30)
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
  updatePlanStrip()
  updateContextChip()
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
  -- 子代理仍在运行时恢复实时卡片；已完成的清除（结果气泡已由历史重建呈现）
  BubbleRenderer.syncSubtask(SubagentRunner.isRunning() and SubagentRunner.progressInfo() or nil)
  BubbleRenderer.renderSubtaskCard()
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

  -- 构建上下文（用户可通过上下文 chip 本次跳过）
  local context = AgentChat.buildContext()
  local userMsg = text
  if not skipContext and context ~= "" then
    userMsg = context .. "\n\n用户问题: " .. text
  end
  -- “本次”语义：无论是否跳过，发送后复位
  if skipContext then
    skipContext = false
    updateContextChip()
  end

  -- 编辑器上下文只加入请求副本，不写入持久化会话；超预算时先压缩历史。
  AgentTurn.bumpGeneration()
  AgentTurn.send(false, userMsg)
end

-- ─── 供应商与模型设置 UI（已抽到 mods/agent/SettingsUi）──
-- 全部供应商/模型/AI 设置对话框原样迁出，模型标签刷新经 configure 注入；
-- 保留 ChatUI 侧的转发声明，调用点零改动。
local SettingsUi = require("mods.agent.SettingsUi")
SettingsUi.configure({ updateModelLabel = updateModelLabel })
showModelPicker = SettingsUi.showModelPicker
showModelManager = SettingsUi.showModelManager
showSettings = SettingsUi.showSettings
-- ─── 会话管理（UI 已抽到 mods/agent/ConvUi）──
-- 状态序列（切换/新建/删除后重载/重命名刷新）留在 ChatUI，经 configure 注入。

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

-- 统一的新建会话序列：原先在 4 处各写一份，顺带修复其中两处
-- 遗漏的任务计划清理与陈旧用量统计未复位的问题
local function newConversation()
  saveHistory()
  AgentTurn.invalidate()
  local created = AgentChat.createConversation()
  activeConversationId = created and created.id or nil
  activeConversationProjectPath = created and AgentChat.getCurrentProjectPath() or nil
  conversationLoaded = created ~= nil
  activeConversationHadMessages = false
  messages = created and created.messages or {}
  TodoManager.set(nil)
  convUsage = { requests = 0, tokens = 0 }
  if views.msgContainer then views.msgContainer.removeAllViews() end
  if views.aiTitle then views.aiTitle.setText(S.ai_new_conv) end
  if updateProjectLabel then updateProjectLabel() end
end

local ConvUi = require("mods.agent.ConvUi")
ConvUi.configure({
  onSwitch = switchToConversation,
  onNew = newConversation,
  onAfterDelete = function(convId)
    messages = {}
    if views.msgContainer then views.msgContainer.removeAllViews() end
    loadHistory()
    if views.aiTitle then
      local c = AgentChat.getCurrentConv()
      if c then views.aiTitle.setText(convName(c)) end
    end
  end,
  onRenamed = function(convId)
    local c = AgentChat.getCurrentConv()
    if views.aiTitle and c and c.id == convId then
      views.aiTitle.setText(convName(c))
    end
  end,
})
showConvList = ConvUi.showConvList
showConvManager = ConvUi.showConvManager
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

  -- 任务计划置顶条点击：弹出完整清单
  if views.planStrip then
    views.planStrip.onClick = function()
      local todos = TodoManager.get() or {}
      if #todos == 0 then return end
      local items = {}
      for index, item in ipairs(todos) do
        local mark = "○"
        if item.status == "completed" then
          mark = "✓"
        elseif item.status == "in_progress" then
          mark = "◐"
        end
        items[index] = mark .. "  " .. tostring(item.content or "")
      end
      MaterialAlertDialogBuilder(activity)
        .setTitle(S.ai_todo)
        .setItems(items, nil)
        .setPositiveButton(S.ai_close, nil)
        .show()
    end
  end

  -- 上下文指示点击：预览本次将附带的内容，并可在“附带/跳过”间切换
  if views.ctxChip then
    views.ctxChip.onClick = function()
      local context = AgentChat.buildContext()
      if context == "" then return end
      local preview = context
      if #preview > 1500 then preview = preview:sub(1, 1500) .. "\n…" end
      MaterialAlertDialogBuilder(activity)
        .setTitle(S.ai_ctx_preview_title)
        .setMessage(preview)
        .setPositiveButton(skipContext and S.ai_ctx_resume or S.ai_ctx_skip, function()
          skipContext = not skipContext
          updateContextChip()
        end)
        .setNegativeButton(S.ai_close, nil)
        .show()
    end
  end

  if views.btnClear then
    views.btnClear.onClick = function()
      newConversation()
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

-- 子代理的 UI 侧钩子：工具确认复用全局确认对话框，
-- 状态条实时显示子任务进度，模型请求计入会话用量统计
SubagentRunner.configure({
  showToolConfirm = function(name, args, onAllow, onDeny)
    showToolConfirm(name, args, onAllow, onDeny)
  end,
  setStatus = function(text)
    AgentTurn.setLoadingStatus(text)
  end,
  reportUsage = function(used)
    convUsage.requests = convUsage.requests + 1
    convUsage.tokens = convUsage.tokens + math.max(0, tonumber(used) or 0)
  end,
  onProgress = function(info)
    BubbleRenderer.syncSubtask(info)
    BubbleRenderer.renderSubtaskCard()
  end,
})

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
