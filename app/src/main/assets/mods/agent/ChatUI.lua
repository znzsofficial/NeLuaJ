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
local ToolRegistry = require("mods.agent.ToolRegistry")
local Session = require("mods.agent.SessionState")
local AgentTurn = require("mods.agent.AgentTurn")
local MCPClient = require("mods.agent.MCPClient")
local TodoManager = require("mods.agent.TodoManager")
local SubagentRunner = require("mods.agent.SubagentRunner")
local TextUtil = require("mods.utils.TextUtil")
-- 延迟或按需加载，避免在主界面启动加载 Actions 时提前触发非必要的深度依赖
local ActivityUtil = nil
local function getActivityUtil()
  if not ActivityUtil then ActivityUtil = require("mods.utils.ActivityUtil") end
  return ActivityUtil
end
import "mods.utils.EditorUtil"
local ColorUtil = this.themeUtil
local ColorPrimary = ColorUtil.primary.main
local ColorOnPrimary = ColorUtil.primary.on
local ColorPrimaryContainer = ColorUtil.primary.container
local ColorOnPrimaryContainer = ColorUtil.primary.onContainer
local ColorSecondaryContainer = ColorUtil.secondary and ColorUtil.secondary.container or ColorPrimaryContainer
local ColorOnSecondaryContainer = ColorUtil.secondary and ColorUtil.secondary.onContainer or ColorOnPrimaryContainer
local ColorSurface = ColorUtil.surface.container
local ColorSurfaceContainerLow = ColorUtil.surface.containerLow
local ColorSurfaceContainerHigh = ColorUtil.surface.containerHigh
local ColorOnSurface = ColorUtil.surface.on
local ColorText = ColorUtil.surface.onVariant
local ColorOutline = ColorUtil.outline.variant
local ColorError = ColorUtil.error.main
local ColorOnError = ColorUtil.error.on
local ColorErrorContainer = ColorUtil.error.container
local ColorOnErrorContainer = ColorUtil.error.onContainer
local ColorRipple = ColorUtils.blendARGB(ColorPrimary, 0x00ffffff, 0.4)
local ColorCodeBg = ColorUtils.blendARGB(ColorSurfaceContainerLow, 0xff000000, 0.08)
local S = res.string
local GradientDrawable = luajava.bindClass("android.graphics.drawable.GradientDrawable")
local function dp(n) return this.dpToPx(n) end

local VISIBLE = 0
local GONE = 8

-- 消息数组只存在于 Session。每次读取都取当前表，避免替换后还拿着旧别名。
local function messages()
  return Session.messages()
end
local dialog = nil
local views = {}
-- View ownership stays here; AgentTurn only publishes plain stream snapshots.
local streamView = {}
local activeToolConfirm = nil
local editingMessageIndex = nil
local titleInFlight = false
-- 回合状态（loading/generation/stopRequested/activeStream/failedToolCalls/
-- retryPayloads/activeToolStop）已迁至 AgentTurn；此处仅保留会话与视图状态。

-- 前向声明
local MessageItemFlattener = require("mods.agent.MessageItemFlattener")
local chatAdapter = nil
local currentVisualCards = {}

local saveHistory, loadHistory, renderCards, showModelManager, showModelPicker, showConvManager, showConvList, showSettings, addMessageBubble, addToolBubble, updateProjectLabel, sendMessage, addRequestErrorBubble
local regenerateLastTurn, editUserMessage
local refreshMessageList, updatePlanStrip

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

local function currentProjectName()
  if AgentChat.currentProjectName then return AgentChat.currentProjectName() end
  return ""
end

updateProjectLabel = function()
  if not views.aiProject then return end
  local name = currentProjectName()
  if name == "" then
    views.aiProject.setText(S.ai_project_unknown)
  else
    views.aiProject.setText(S.ai_project:format(name))
  end
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
  return ToolRegistry.displayName(name, S)
end

--- 智能滚动：仅当用户停留在底部附近时自动跟随；回看历史时不再打扰，
--- 并显示“跳到最新”悬浮按钮。
local function isNearBottom()
  if not views.msgRecycler or not chatAdapter then return true end
  local count = chatAdapter.getItemCount()
  if count <= 1 then return true end
  local lm = views.msgRecycler.getLayoutManager()
  if lm and lm.findLastVisibleItemPosition then
    local last = lm.findLastVisibleItemPosition()
    return (count - 1 - last) <= 2
  end
  return true
end

local function updateJumpLatest(visible)
  if not views.btnJumpLatest then return end
  views.btnJumpLatest.setVisibility(visible and VISIBLE or GONE)
end

local function scrollDown(force)
  if not views.msgRecycler or not chatAdapter then return end
  if not force and not isNearBottom() then return end
  local count = chatAdapter.getItemCount()
  if count > 0 then
    views.msgRecycler.post(function()
      pcall(function()
        if force then
          views.msgRecycler.smoothScrollToPosition(count - 1)
        else
          views.msgRecycler.scrollToPosition(count - 1)
        end
        updateJumpLatest(false)
      end)
    end)
  end
end

local function showAgentHelp()
  getActivityUtil().open("help", "agent")
end

-- ─── Markdown 渲染辅助（已抽到 mods/agent/Markdown）──
-- 气泡正文渲染在 BubbleRenderer 内直接 require Markdown；ChatUI 自身仅
-- 欢迎卡等纯文本展示，不再持有渲染别名。
--- 复制文本到剪贴板
-- ─── 气泡渲染层（已抽到 mods/agent/BubbleRenderer）──
-- 容器/消息表/回调节点经 configure 注入；渲染入口保持原局部名转发，
-- loadHistory / AgentTurn 钩子 / SubagentRunner 进度等调用点零改动。
local BubbleRenderer = require("mods.agent.BubbleRenderer")
addMessageBubble = BubbleRenderer.renderMessage
  addToolBubble = function(name, args, result)
    if AgentChat.normalizeToolName(name) == "update_todos" then
      updatePlanStrip()
    end
    refreshMessageList()
  end

--- 任务计划置顶条：显示当前计划的完成进度，点击弹出完整清单。
--- 数据源就是 TodoManager 的实时状态（系统提示注入的同一份）。
updatePlanStrip = function()
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
  local todoTitle = S.ai_todo or S.ai_tool_todo or "任务计划"
  views.planLabel.setText(tostring(todoTitle))
  local progressPattern = S.ai_plan_progress or "%d/%d 已完成"
  views.planProgress.setText(string.format(progressPattern, done, #todos))
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
    label = S.ai_ctx_skipped
  else
    local tokens = 0
    pcall(function()
      local ContextManager = require("mods.agent.ContextManager")
      tokens = ContextManager.estimateTokens(context)
    end)
    label = S.ai_ctx_chip:format(name) .. " · ~" .. tokens .. " tokens"
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

local fmtTokens = TextUtil.fmtTokens

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
  local usage = Session.usage()
  if usage.requests > 0 then
    text = text .. " · " .. S.ai_usage_total:format(usage.requests, fmtTokens(usage.tokens))
  end
  views.ctxUsage.setText(text)
end

--- 首轮问答完成后用辅助模型异步生成简短会话标题（替换“首条消息前 30 字”默认名）。
--- 生成成功后落盘 name 与 titled 标记；失败保持默认名，下个回合结束时重试。
local function maybeGenerateTitle()
  if titleInFlight or AgentTurn.isActive() or not Session.loaded() then return end
  local conv = AgentChat.getCurrentConv()
  if not conv or conv.titled then return end
  if #AgentChat.loadModels() == 0 then return end
  local convId = Session.id()
  local firstUser, firstAssistant
  for _, msg in ipairs(messages()) do
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
    local capped = TextUtil.utf8Cap(text, limit)
    if #capped < #text then return capped .. "…" end
    return capped
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
      if not Session.loaded() or Session.id() ~= convId then return end
      title = settleTitle(title)
      if title == "" then return end
      saveHistory({ name = title, titled = true })
      if views.aiTitle then views.aiTitle.setText(title) end
      -- 静默更新标题栏即可，无需弹出全局 Toast 打断用户当前正在做的事情
    end,
    onError = function()
      titleInFlight = false
    end,
  })
end

local isRefreshing = false
local pendingRefresh = false

refreshMessageList = function()
  if not isPanelVisible() then return end
  if isRefreshing then
    pendingRefresh = true
    return
  end
  isRefreshing = true
  repeat
    pendingRefresh = false
    pcall(function()
      updatePlanStrip()
      if renderCards then
        renderCards()
      else
        loadHistory(false)
      end
    end)
  until not pendingRefresh
  isRefreshing = false
end

local function undoLastTurn()
  if AgentTurn.isActive() then return false end
  if not Session.undoTurn() then return false end
  saveHistory(#Session.messages() == 0 and { __allow_empty = true } or nil)
  refreshMessageList()
  return true
end

local function redoLastTurn()
  if AgentTurn.isActive() or not Session.canRedo() then return false end
  if not Session.redoTurn() then return false end
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
      refreshMessageList()
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

--- 导出当前会话为 Markdown：写成真实本地文件并以文件流分享，零字符截断、无大小限制
local function exportConversation()
  local conv = AgentChat.getCurrentConv()
  if not conv or #messages() == 0 then return end
  local out = { "# " .. convName(conv), "" }
  for _, msg in ipairs(messages()) do
    if msg.role == "user" then
      out[#out + 1] = "## " .. S.ai_you
      out[#out + 1] = ""
      out[#out + 1] = tostring(msg.content or "")
      out[#out + 1] = ""
    elseif msg.role == "assistant" then
      local reasoning = tostring(msg.reasoning_content or "")
      if reasoning ~= "" then
        out[#out + 1] = "> " .. S.ai_thinking .. ": " .. reasoning:gsub("\n", "\n> ")
        out[#out + 1] = ""
      end
      out[#out + 1] = "## AI"
      out[#out + 1] = ""
      out[#out + 1] = tostring(msg.content or "")
      out[#out + 1] = ""
    elseif msg.role == "tool" then
      local text = tostring(msg.content or "")
      if text ~= "" then
        out[#out + 1] = "```"
        out[#out + 1] = "[tool] " .. text
        out[#out + 1] = "```"
        out[#out + 1] = ""
      end
    end
  end
  local fullMarkdown = table.concat(out, "\n")
  local fileName = (convName(conv):gsub("[^%w%._%-]+", "_")) .. ".md"
  if fileName == ".md" or fileName == "_.md" then fileName = "conversation.md" end

  -- 尝试通过真实文件 + FileProvider 分享（无任何 Binder 内存与字数限制）
  local sharedByFile = false
  pcall(function()
    local File = luajava.bindClass("java.io.File")
    local FileOutputStream = luajava.bindClass("java.io.FileOutputStream")
    local FileProvider = luajava.bindClass("androidx.core.content.FileProvider")
    local Intent = luajava.bindClass("android.content.Intent")

    -- 写入外部缓存目录（受 FileProvider 授权保护，系统完全可读）
    local cacheDir = activity.getExternalCacheDir() or activity.getCacheDir()
    local exportDir = File(cacheDir, "exports")
    if not exportDir.exists() then exportDir.mkdirs() end
    local targetFile = File(exportDir, fileName)

    local fos = FileOutputStream(targetFile)
    local javaBytes = luajava.newInstance("java.lang.String", fullMarkdown).getBytes("UTF-8")
    fos.write(javaBytes)
    fos.flush()
    fos.close()

    local authority = activity.getPackageName() .. ".fileprovider"
    local uri = FileProvider.getUriForFile(activity, authority, targetFile)

    local intent = Intent(Intent.ACTION_SEND)
    intent.setType("text/markdown")
    intent.putExtra(Intent.EXTRA_STREAM, uri)
    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    intent.putExtra(Intent.EXTRA_TITLE, fileName)

    local chooser = Intent.createChooser(intent, S.ai_export_conv)
    chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    activity.startActivity(chooser)
    sharedByFile = true
  end)

  if sharedByFile then return end

  -- 极端回退（如单元测试或环境异常未配置 FileProvider）
  pcall(function()
    local fallbackText = fullMarkdown
    if #fallbackText > 100000 then
      fallbackText = fallbackText:sub(1, 100000) .. "\n\n...(内容过长已截断)"
    end
    local Intent = luajava.bindClass("android.content.Intent")
    local intent = Intent(Intent.ACTION_SEND)
    intent.setType("text/plain")
    intent.putExtra(Intent.EXTRA_TEXT, fallbackText)
    intent.putExtra(Intent.EXTRA_TITLE, fileName)
    activity.startActivity(Intent.createChooser(intent, S.ai_export_conv))
  end)
end

--- 会话内搜索：实时过滤消息内容，点击结果跳到对应气泡
local function showConvSearch()
  if #messages() == 0 then return end
  local searchViews = {}
  local searchDlg
  local content = loadlayout({
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    padding = "16dp",
    {
      EditText,
      id = "searchInput",
      layout_width = "match",
      layout_height = "wrap",
      minHeight = "46dp",
      hint = S.ai_search_hint,
      textSize = "14sp",
      singleLine = true,
    },
    {
      ScrollView,
      layout_width = "match",
      layout_height = "wrap",
      {
        LinearLayout,
        id = "searchResults",
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        layout_marginTop = "8dp",
      },
    },
  }, searchViews)

  local function jumpToMessage(msg)
    if views.msgRecycler and chatAdapter and currentVisualCards then
      for pos, card in ipairs(currentVisualCards) do
        if card.message == msg then
          views.msgRecycler.post(function()
            pcall(function()
              local lm = views.msgRecycler.getLayoutManager()
              if lm and lm.scrollToPositionWithOffset then
                lm.scrollToPositionWithOffset(pos - 1, dp(16))
              else
                views.msgRecycler.scrollToPosition(pos - 1)
              end
            end)
          end)
          return
        end
      end
    end
  end

  local function doSearch()
    local container = searchViews.searchResults
    if not container then return end
    container.removeAllViews()
    local query = searchViews.searchInput.text:match("^%s*(.-)%s*$")
    if query == "" then return end
    local lowerQuery = query:lower()
    local count = 0
    for _, msg in ipairs(messages()) do
      if count >= 30 then break end
      local text = tostring(msg.content or "")
      local lowerText = text:lower()
      local start = lowerText:find(lowerQuery, 1, true)
      if start then
        count = count + 1
        local snippet = text:sub(math.max(1, start - 40), start + #query + 60)
        if start > 41 then snippet = "…" .. snippet end
        if start + #query + 60 < #text then snippet = snippet .. "…" end
        local role = msg.role == "user" and S.ai_you or (msg.role == "assistant" and "AI" or "[tool]")
        local target = msg
        local resultRow = loadlayout({
          MaterialCardView,
          radius = "10dp",
          CardElevation = 0,
          CardBackgroundColor = ColorSurfaceContainerHigh,
          layout_width = "match",
          layout_height = "wrap",
          clickable = true,
          focusable = true,
          {
            LinearLayout,
            orientation = "vertical",
            layout_width = "match",
            layout_height = "wrap",
            padding = "10dp",
            {
              MaterialTextView,
              text = role,
              textSize = "11sp",
              textStyle = "bold",
              textColor = ColorPrimary,
            },
            {
              MaterialTextView,
              text = snippet,
              textSize = "12sp",
              textColor = ColorText,
              maxLines = 2,
              ellipsize = "end",
              layout_marginTop = "2dp",
            },
          },
        })
        resultRow.onClick = function()
          if searchDlg then searchDlg.dismiss() end
          jumpToMessage(target)
        end
        local lp = LinearLayout.LayoutParams(-1, -2)
        lp.bottomMargin = dp(6)
        container.addView(resultRow, lp)
      end
    end
    if count == 0 then
      container.addView(loadlayout({
        MaterialTextView,
        text = S.ai_search_empty,
        textSize = "13sp",
        textColor = ColorText,
        paddingTop = "24dp",
        paddingBottom = "24dp",
        layout_width = "match",
        layout_height = "wrap",
      }))
    end
  end

  local pendingSearch = nil
  pcall(function()
    searchViews.searchInput.addTextChangedListener({
      beforeTextChanged = function() end,
      onTextChanged = function() end,
      afterTextChanged = function()
        -- 250ms 防抖，避免中文输入法连续击键时频繁重新构建 30 个 CardView
        if pendingSearch then searchViews.searchInput.removeCallbacks(pendingSearch) end
        pendingSearch = Runnable({
          run = function()
            doSearch()
          end
        })
        searchViews.searchInput.postDelayed(pendingSearch, 250)
      end,
    })
  end)

  searchDlg = MaterialAlertDialogBuilder(activity)
    .setTitle(S.ai_search_conv)
    .setView(content)
    .setNegativeButton(S.ai_close, nil)
    .show()
end

local function showCommandMenu()
  local items = {}
  local menuDialog

  local function addSection(label)
    items[#items + 1] = {
      MaterialTextView,
      text = label,
      textSize = "12sp",
      textStyle = "bold",
      textColor = ColorPrimary,
      paddingLeft = "16dp",
      paddingTop = "12dp",
      paddingRight = "16dp",
      paddingBottom = "4dp",
      layout_width = "match",
      layout_height = "wrap",
    }
  end

  local function addAction(label, enabled, action)
    local actionIndex = #items + 1
    items[actionIndex] = {
      MaterialTextView,
      id = "cmd_" .. actionIndex,
      text = label,
      textSize = "15sp",
      textColor = ColorOnSurface,
      gravity = "center_vertical",
      paddingLeft = "16dp",
      paddingRight = "16dp",
      minHeight = "48dp",
      enabled = enabled,
      alpha = enabled and 1 or 0.42,
      clickable = enabled,
      layout_width = "match",
      layout_height = "wrap",
      onClick = enabled and function()
        if menuDialog then menuDialog.dismiss() end
        action()
      end or nil,
    }
  end

  local hasTurn = false
  for _, message in ipairs(messages()) do
    if message.role == "user" then hasTurn = true break end
  end
  addSection(S.ai_command_conversation)
  addAction(S.ai_compress_context, not AgentTurn.isActive() and #messages() > 0, compressCurrentContext)
  addAction(S.ai_undo_turn, not AgentTurn.isActive() and hasTurn, undoLastTurn)
  addAction(S.ai_redo_turn, not AgentTurn.isActive() and Session.canRedo(), redoLastTurn)
  addAction(S.ai_search_conv, #messages() > 0, showConvSearch)
  addAction(S.ai_export_conv, #messages() > 0, exportConversation)
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

  local contentTree = {
    ScrollView,
    layout_width = "match",
    layout_height = "wrap",
    fillViewport = true,
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      paddingLeft = "8dp",
      paddingTop = "4dp",
      paddingRight = "8dp",
      paddingBottom = "4dp",
    },
  }
  local innerLayout = contentTree[2]
  for _, item in ipairs(items) do
    innerLayout[#innerLayout + 1] = item
  end

  local dialogViews = {}
  local view = loadlayout(contentTree, dialogViews)
  menuDialog = MaterialAlertDialogBuilder(activity)
    .setTitle(S.ai_commands)
    .setView(view)
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
    if #preview > 2000 then preview = preview:sub(1, 2000) .. "\n…" end
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

  local isCodeTool = (toolName == "run_lua" or toolName == "apply_patch")
  local dialogView = loadlayout({
    ScrollView,
    layout_width = "match",
    layout_height = "wrap",
    fillViewport = true,
    paddingLeft = "24dp",
    paddingRight = "24dp",
    paddingTop = "8dp",
    paddingBottom = "8dp",
    {
      MaterialTextView,
      text = message,
      textSize = "14sp",
      textColor = ColorOnSurface,
      lineSpacingMultiplier = 1.3,
      typeface = isCodeTool and Typeface.MONOSPACE or nil,
      textIsSelectable = true,
    },
  })

  local confirm = MaterialAlertDialogBuilder(activity)
    .setTitle(title)
    .setView(dialogView)
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
  local projectPath = AgentChat.getCurrentProjectPath()
  if not Session.canPersist(projectPath, updates) then return false end
  -- 镜像同步会话级状态：任务计划与累计用量随每次落盘持久化，
  -- 与工具回合的状态提交合并为同一次写入
  local merged = updates
  if type(updates) ~= "table" or updates.todos == nil then
    merged = {}
    if type(updates) == "table" then
      for key, value in pairs(updates) do merged[key] = value end
    end
    merged.todos = TodoManager.get() or {}
    merged.usage = Session.usageRecord()
  end
  local saved = AgentChat.saveConversation(Session.id(), Session.messages(), merged)
  if saved then Session.syncHadMessages() end
  return saved
end

local function conversationMessageCount(conv)
  if not conv then return 0 end
  if type(conv.messages) == "table" then return #conv.messages end
  return tonumber(conv.messageCount) or 0
end

--- 打开面板时自动建出来的空会话：没有消息，名字也还是占位。
local function isPlaceholderConversation(conv)
  if conversationMessageCount(conv) > 0 then return false end
  local name = tostring(conv and conv.name or "")
  return name == "" or name == "新对话" or name == S.ai_new_conv or name == S.ai_unnamed_conv
end

--- 打开面板时回到最近一条真正有内容的会话；没有就留空，不写记录。
local function resumeConversation()
  local guard = 0
  while guard < 20 do
    guard = guard + 1
    local conv = AgentChat.getCurrentConv()
    if not conv then return nil end
    if not isPlaceholderConversation(conv) then return conv end
    if not AgentChat.deleteConversation(conv.id) then return nil end
  end
  return nil
end

--- 草稿在第一条消息发出时才创建。失败则保留输入框里的文字。
local function ensureConversation()
  local projectPath = AgentChat.getCurrentProjectPath()
  if Session.loaded() and Session.id() and Session.id() ~= ""
      and Session.projectPath() == projectPath then
    return true
  end
  local created = AgentChat.createConversation()
  if not created then return false end
  Session.beginCreated(created, projectPath)
  if views.aiTitle then views.aiTitle.setText(S.ai_new_conv) end
  return true
end

loadHistory = function(resetTurnHistory)
  if resetTurnHistory ~= false then
    Session.resetTurns()
    if AgentChat.clearActiveSkill then AgentChat.clearActiveSkill() end
  end
  local conv = resumeConversation()
  if not conv then
    Session.beginDraft(AgentChat.getCurrentProjectPath())
    TodoManager.set(nil)
    if views.aiTitle then views.aiTitle.setText(S.ai_new_conv) end
    if updateProjectLabel then updateProjectLabel() end
    updatePlanStrip()
    renderCards(true)
    return 0
  end
  Session.activate(conv, AgentChat.getCurrentProjectPath())
  -- 会话的任务计划随会话切换整体注入（空/缺失即清空）
  TodoManager.set(conv and conv.todos or nil)
  -- 会话激活技能恢复：按记录的技能名重查正文（无记录/找不到即保持清空）
  if conv and type(conv.skills) == "table" and next(conv.skills) ~= nil then
    pcall(function() AgentChat.restoreSkillFromConv(conv) end)
  end
  -- 上次会话的任务可能被应用退出打断：注入提示并清除标记
  -- （必须在 activate 置位之后，saveHistory 才会真正落盘）
  if conv and conv.running and not AgentTurn.isActive() then
    conv.running = false
    messages()[#messages() + 1] = { role = "assistant", content = S.ai_task_interrupted }
    saveHistory({ running = false })
  end
  Session.syncHadMessages()
  if updateProjectLabel then updateProjectLabel() end
  if views.aiTitle and conv then views.aiTitle.setText(convName(conv)) end
  updatePlanStrip()
  renderCards(not Session.loaded())
  return #messages()
end

renderCards = function(isDraft)
  -- 重建气泡：统一由 RecyclerView 虚拟化 Adapter 数据驱动更新
  local welcomeData = nil
  if #messages() == 0 then
    welcomeData = {
      title = isDraft and S.ai_new_conv or S.ai_welcome_title,
      body = isDraft and S.ai_start_chat or S.ai_welcome_body,
    }
  end
  local cards = MessageItemFlattener.flatten(messages(), {
    activeStream = AgentTurn.activeStream(),
    subtask = SubagentRunner.isRunning() and SubagentRunner.progressInfo() or nil,
    welcome = welcomeData,
  })
  currentVisualCards = cards
  if chatAdapter then
    chatAdapter.submitMessages(cards)
  end
  scrollDown()

  -- 子代理仍在运行时恢复实时卡片；已完成的清除（结果气泡已由卡片流统一呈现）
  BubbleRenderer.syncSubtask(SubagentRunner.isRunning() and SubagentRunner.progressInfo() or nil)
end

-- ─── 发送消息核心 ──

addRequestErrorBubble = function(err, messageIndex)
  refreshMessageList()
end

-- ─── 发送消息 ──

sendMessage = function()
  if AgentTurn.isActive() then return end

  local input = views.msgInput
  if not input then return end

  local text = input.text:match("^%s*(.-)%s*$")
  if text == "" then return end
  -- 草稿没有 id，不能在清空输入框之后再发现创建失败。
  if not ensureConversation() then return end

  input.setText("")

  local skill = AgentChat.selectSkill(text)

  for _, message in ipairs(messages()) do
    if message.role == "user" then message.request_error = nil end
  end

  local editedIndex = editingMessageIndex
  editingMessageIndex = nil
  if editedIndex and messages()[editedIndex] and messages()[editedIndex].role == "user" then
    messages()[editedIndex].content = text
    messages()[editedIndex].request_error = nil
    for index = #messages(), editedIndex + 1, -1 do table.remove(messages(), index) end
    refreshMessageList()
  else
    messages()[#messages() + 1] = { role = "user", content = text }
    refreshMessageList()
  end
  if skill then
    local conv = AgentChat.getCurrentConv()
    local skills = conv and conv.skills or {}
    skills[skill.name] = true
    saveHistory({ skills = skills })
  else
    saveHistory()
  end
  Session.clearRedo()

  if not AgentChat.hasApiKey() then
    messages()[#messages() + 1] = { role = "assistant", content = S.ai_need_config }
    refreshMessageList()
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

--- 最新一轮“重新生成”：撤销整轮后用原文本重发（上下文按当前编辑器重建）
regenerateLastTurn = function()
  if AgentTurn.isActive() then return false end
  local lastUser
  for i = #messages(), 1, -1 do
    if messages()[i].role == "user" then lastUser = messages()[i]; break end
  end
  if not lastUser then return false end
  if not undoLastTurn() then return false end
  local text = tostring(lastUser.content or "")
  messages()[#messages() + 1] = { role = "user", content = text }
  refreshMessageList()
  Session.clearRedo()
  saveHistory()
  if not AgentChat.hasApiKey() then
    messages()[#messages() + 1] = { role = "assistant", content = S.ai_need_config }
    refreshMessageList()
    return true
  end
  local context = AgentChat.buildContext()
  local userMsg = text
  if not skipContext and context ~= "" then
    userMsg = context .. "\n\n用户问题: " .. text
  end
  if skipContext then
    skipContext = false
    updateContextChip()
  end
  AgentTurn.bumpGeneration()
  AgentTurn.send(false, userMsg)
  return true
end

--- 编辑重发：把该用户消息回填输入框并进入编辑态（发送时原地替换并截断后续）
editUserMessage = function(stateMessage)
  if AgentTurn.isActive() then return end
  local index
  for i, msg in ipairs(messages()) do
    if msg == stateMessage then index = i; break end
  end
  if not index or not views.msgInput then return end
  editingMessageIndex = index
  views.msgInput.setText(tostring(stateMessage.content or ""))
  pcall(function() views.msgInput.requestFocus() end)
end

-- ─── 供应商与模型设置 UI（已抽到 mods/agent/SettingsUi）──
-- 全部供应商/模型/AI 设置对话框原样迁出，模型标签刷新经 configure 注入；
-- 保留 ChatUI 侧的转发声明，调用点零改动。
local SettingsUi = require("mods.agent.SettingsUi")
showModelPicker = SettingsUi.showModelPicker
showModelManager = SettingsUi.showModelManager
showSettings = SettingsUi.showSettings
-- ─── 会话管理（UI 已抽到 mods/agent/ConvUi）──
-- 状态序列（切换/新建/删除后重载/重命名刷新）留在 ChatUI，经 configure 注入。

-- 统一的会话切换序列（面板内列表、首屏 chips 与对外 openConversation 共用）
local function switchToConversation(conv)
  editingMessageIndex = nil -- 强制清空编辑状态，防止跨会话截断
  saveHistory()
  AgentTurn.invalidate()
  AgentChat.setCurrentConv(conv.id)
  Session.beginSwitch(conv.id, AgentChat.getCurrentProjectPath())
  loadHistory(true)
  if views.aiTitle then views.aiTitle.setText(convName(conv)) end
  if updateProjectLabel then updateProjectLabel() end
end

-- 新会话先只留在内存里。第一条消息发出时才创建记录，避免列表里堆未命名空会话。
local function newConversation()
  editingMessageIndex = nil -- 强制清空编辑状态
  saveHistory()
  AgentTurn.invalidate()
  Session.beginDraft(AgentChat.getCurrentProjectPath())
  TodoManager.set(nil)
  if views.aiTitle then views.aiTitle.setText(S.ai_new_conv) end
  if updateProjectLabel then updateProjectLabel() end
  updatePlanStrip()
  renderCards(true)
end

local ConvUi = require("mods.agent.ConvUi")
showConvList = ConvUi.showConvList
showConvManager = ConvUi.showConvManager

local function clearChat()
  AgentTurn.invalidate()
  local conversationId = Session.id()
  local sameProject = Session.loaded() and conversationId and conversationId ~= ""
      and Session.projectPath() == AgentChat.getCurrentProjectPath()
  Session.clearMessages()
  if sameProject and AgentChat.clearConversation then
    AgentChat.clearConversation(conversationId)
  end
  refreshMessageList()
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
  if not activity or not activity.getCurrentFocus then return end
  local focused = activity.getCurrentFocus()
  if not focused then return end
  pcall(function()
    local imm = activity.getSystemService("input_method")
    if imm then imm.hideSoftInputFromWindow(focused.getWindowToken(), 0) end
  end)
end

-- ─── 显示聊天面板 ──

function _M.show(startDraft)
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

  -- 初始化 RecyclerView 适配器（真机环境加载，单测环境自动降级）
  pcall(function()
    if views.msgRecycler and not chatAdapter then
      local RecyclerView = luajava.bindClass("androidx.recyclerview.widget.RecyclerView")
      local LinearLayoutManager = luajava.bindClass("androidx.recyclerview.widget.LinearLayoutManager")
      local AgentChatAdapter = luajava.bindClass("com.nekolaska.agent.adapter.AgentChatAdapter")
      local SimpleItemAnimator = luajava.bindClass("androidx.recyclerview.widget.SimpleItemAnimator")

      local layoutManager = LinearLayoutManager(activity)
      views.msgRecycler.setLayoutManager(layoutManager)

      -- 禁用默认条目闪烁动画，确保打字流与更新平滑稳定
      pcall(function()
        local animator = views.msgRecycler.getItemAnimator()
        if animator then animator.setSupportsChangeAnimations(false) end
      end)

      local delegate
      delegate = {
        getItemViewType = function(item, position)
          return item.viewType or 0
        end,
        onCreateViewHolder = function(parent, viewType)
          local LuaCustRecyclerHolder = luajava.bindClass("github.znzsofficial.adapter.LuaCustRecyclerHolder")
          local dummy = loadlayout({
            LinearLayout,
            layout_width = "match",
            layout_height = "wrap",
            orientation = "vertical",
          })
          local lp = RecyclerView.LayoutParams(-1, -2)
          dummy.setLayoutParams(lp)
          return LuaCustRecyclerHolder(dummy)
        end,
        onBindViewHolder = function(holder, item, position)
          if streamView.holder == holder then streamView = {} end
          local itemView = holder.itemView
          itemView.removeAllViews()
          local vt = item.viewType or 0
          local cardView
          if vt == 0 then
            cardView = BubbleRenderer.createMessageView("user", item.content, item.message, { isLastUser = item.isLastUser })
          elseif vt == 1 then
            cardView = BubbleRenderer.createMessageView("assistant", item.content, item.message, { isLastAssistant = item.isLastAssistant })
          elseif vt == 2 then
            cardView = BubbleRenderer.createToolView(item.toolName, item.args or {}, item.result)
          elseif vt == 4 then
            -- 流式动态卡片
            local streamViews = {}
            cardView = loadlayout({
              LinearLayout,
              layout_width = "match",
              layout_height = "wrap",
              orientation = "vertical",
              paddingBottom = "14dp",
              {
                MaterialTextView,
                id = "aiStreamText",
                text = item.text or "",
                textSize = "14sp",
                textColor = ColorOnSurface,
                lineSpacingMultiplier = 1.4,
              },
            }, streamViews)
            streamView = { holder = holder, bubble = cardView, textView = streamViews.aiStreamText, id = item.streamId }
          elseif vt == 5 then
            -- 完整保留错误重试卡片（包含一键重试、打开设置、压缩上下文与编辑请求）
            local err = tostring(item.error or "")
            local lowerError = err:lower()
            local action = S.ai_retry
            local opensSettings = lowerError:find("http 401", 1, true) or lowerError:find("http 403", 1, true)
              or lowerError:find("api key", 1, true) or lowerError:find("unauthorized", 1, true)
            local compresses = lowerError:find("context", 1, true) or lowerError:find("token", 1, true)
              or lowerError:find("too large", 1, true)
            if opensSettings then action = S.ai_open_settings
            elseif compresses then action = S.ai_compress_retry end

            local errViews = {}
            cardView = loadlayout({
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
                  text = err,
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
            }, errViews)

            errViews.recoverButton.onClick = function()
              if AgentTurn.isActive() then return end
              local message = messages()[item.messageIndex]
              if not message or message.role ~= "user" or not message.request_error then
                print(S.ai_request_expired)
                return
              end
              if opensSettings then
                showSettings()
                return
              end
              local retryPayload = AgentTurn.retryPayloadFor(message)
              if compresses then
                AgentTurn.compressAndRetry(retryPayload)
              else
                AgentTurn.retry(retryPayload)
              end
            end

            errViews.editButton.onClick = function()
              if AgentTurn.isActive() then return end
              local message = messages()[item.messageIndex]
              if not message or message.role ~= "user" then return end
              editingMessageIndex = item.messageIndex
              message.request_error = nil
              saveHistory()
              refreshMessageList()
              if views.msgInput then
                views.msgInput.setText(message.content or "")
                views.msgInput.requestFocus()
                pcall(function()
                  local imm = activity.getSystemService("input_method")
                  if imm then imm.showSoftInput(views.msgInput, 0) end
                end)
              end
            end
          elseif vt == 6 then
            -- 空会话首屏欢迎卡片
            cardView = loadlayout({
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
                  text = tostring(item.title or S.ai_welcome_title),
                  textSize = "16sp",
                  textStyle = "bold",
                  textColor = ColorOnSurface,
                },
                {
                  MaterialTextView,
                  text = tostring(item.body or S.ai_welcome_body),
                  textSize = "13sp",
                  textColor = ColorText,
                  lineSpacingMultiplier = 1.3,
                  layout_marginTop = "8dp",
                },
              },
            })
          elseif vt == 7 then
            -- 子代理实时任务进度卡片
            cardView = BubbleRenderer.createSubtaskView(item.subtask)
          end
          if cardView then
            itemView.addView(cardView)
          end
        end,
        onBindViewHolderWithPayload = function(holder, item, position, payloads)
          if item.viewType == 4 and streamView.holder == holder and streamView.id == item.streamId
              and streamView.textView then
            streamView.textView.setText(item.text or "")
          else
            delegate.onBindViewHolder(holder, item, position)
          end
        end,
        onViewRecycled = function(holder)
          if streamView.holder == holder then streamView = {} end
        end,
      }
      chatAdapter = AgentChatAdapter(activity, delegate)
      views.msgRecycler.setAdapter(chatAdapter)

      -- 监听 RecyclerView 滚动，动态切换“跳到最新”悬浮按钮
      pcall(function()
        local listener = luajava.createProxy("androidx.recyclerview.widget.RecyclerView$OnScrollListener", {
          onScrolled = function(recyclerView, dx, dy)
            updateJumpLatest(not isNearBottom())
          end,
        })
        views.msgRecycler.addOnScrollListener(listener)
      end)
    end
  end)

  dialog = BottomSheetDialog(activity)
  dialog.setContentView(content)
  local savedNav = nil

  -- 去掉底部间距
  pcall(function()
    local window = dialog.getWindow()
    if window then
      window.getAttributes().gravity = 80  -- Gravity.BOTTOM
      window.setBackgroundDrawableResource(android.R.color.transparent)
      pcall(function()
        local nav = ColorUtil.surface.main
        window.setNavigationBarColor(nav)
        -- 底栏露在 Activity 窗口上，对话打开时跟输入区同一色。
        local host = activity.getWindow()
        savedNav = host.getNavigationBarColor()
        host.setNavigationBarColor(nav)
      end)
      pcall(function() window.setNavigationBarContrastEnforced(false) end)
      pcall(function() activity.getWindow().setNavigationBarContrastEnforced(false) end)
      window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN
        | WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    end
  end)

  -- 关闭面板只保存会话，不取消后台请求；停止按钮和上下文切换负责取消。
  dialog.setOnDismissListener(function()
    saveHistory()
    streamView = {}
    activeToolConfirm = nil
    chatAdapter = nil
    views = {}
    if savedNav ~= nil then
      pcall(function()
        activity.getWindow().setNavigationBarColor(savedNav)
      end)
    end
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
        .setTitle(S.ai_todo or S.ai_tool_todo or "任务计划")
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
    end
  end

  if views.btnJumpLatest then
    views.btnJumpLatest.onClick = function()
      scrollDown(true)
      updateJumpLatest(false)
    end
  end

  -- 标题栏关闭/收起按钮
  if views.btnClose then
    views.btnClose.onClick = function()
      if dialog then dialog.dismiss() end
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
          -- 仅在明确的 IME 动作（如“发送/完成”）时触发发送；
          -- 不再拦截 actionId == 0 (IME_NULL)，保留多行输入框按 Enter 键换行的原生语义
          if actionId == 4 or actionId == 6 then
            sendMessage()
            return true
          end
          return false
        end
      })
    end)
  end

  -- 恢复上次会话。显式新建只进入草稿，第一条消息才落盘。
  local historyCount = 0
  if startDraft then
    newConversation()
    historyCount = 0
  else
    historyCount = loadHistory(not AgentTurn.isActive())
  end
  updateContextChip()

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
  Session.suspend()
end

function _M.refreshProjectContext()
  AgentTurn.invalidate()
  Session.reset()
  if not dialog or not dialog.isShowing() then return end
  loadHistory(true)
  local conv = AgentChat.getCurrentConv()
  if views.aiTitle then views.aiTitle.setText(conv and convName(conv) or S.ai_new_conv) end
  if updateProjectLabel then updateProjectLabel() end
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
    Session.select(target.id, AgentChat.getCurrentProjectPath())
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

  pcall(function()
    mLuaEditor.paste(tostring(code or ""))
  end)

  print(S.ai_inserted)
end

-- ─── 回合状态机装配 ──
-- 编排逻辑全部位于 AgentTurn；此处注入视图钩子。
-- All action functions are defined before wiring; missing callbacks fail here.
BubbleRenderer.configure({
  scrollDown = scrollDown,
  isPanelVisible = isPanelVisible,
  getContainer = function() return (views.msgRecycler and views.msgRecycler.getParent()) or views.msgRecycler end,
  getMessages = function() return Session.messages() end,
  saveHistory = saveHistory,
  isToolError = isToolError,
  toolDisplayName = toolDisplayName,
  insertCode = _M.insertCode,
  onRegenerate = regenerateLastTurn,
  onEditRequest = editUserMessage,
})
SettingsUi.configure({ updateModelLabel = updateModelLabel })
ConvUi.configure({
  onSwitch = switchToConversation,
  onNew = newConversation,
  onAfterDelete = function(convId)
    -- 只有删除的是当前活跃会话时，才重置当前会话内存状态与视图
    if convId == Session.id() then
      Session.setMessages({})
      loadHistory(true)
      if views.aiTitle then
        local c = AgentChat.getCurrentConv()
        if c then views.aiTitle.setText(convName(c)) end
      end
    end
  end,
  onRenamed = function(convId)
    local c = AgentChat.getCurrentConv()
    if views.aiTitle and c and c.id == convId then views.aiTitle.setText(convName(c)) end
  end,
})

-- 子代理的 UI 侧钩子：工具确认复用全局确认对话框，
-- 状态条实时显示子任务进度，模型请求计入会话用量统计
SubagentRunner.configure({
  showToolConfirm = function(name, args, onAllow, onDeny)
    showToolConfirm(name, args, onAllow, onDeny)
  end,
  cancelToolConfirm = function()
    if activeToolConfirm then activeToolConfirm.cancel() end
  end,
  setStatus = function(text)
    AgentTurn.setLoadingStatus(text)
  end,
  reportUsage = function(used) Session.addUsage(used) end,
  onProgress = function(info)
    BubbleRenderer.syncSubtask(info)
    if not isRefreshing then
      refreshMessageList()
    end
  end,
})

AgentTurn.configure({
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
  reportUsage = function(used) Session.addUsage(used) end,
  onTurnSettled = function() maybeGenerateTitle() end,
  setConversationRunning = function(running)
    if Session.loaded() then saveHistory({ running = running == true }) end
  end,
  onRequestError = function(err)
    if not isRefreshing then
      refreshMessageList()
    end
    print(tostring(err or "请求失败"))
  end,
  onStreamChanged = function(streamState)
      if not streamState then
        streamView = {}
        if isPanelVisible() and not isRefreshing then
          refreshMessageList()
        end
        return
      end
      if not isPanelVisible() then return end

      -- Update the adapter's source of truth, not a possibly recycled TextView.
      if chatAdapter and chatAdapter.updateStreamingText(streamState.id, streamState.text or "") then
        local now = (os.clock and os.clock()) or os.time()
        if not streamView.lastScroll or (now - streamView.lastScroll) >= 0.1 then
          streamView.lastScroll = now
          scrollDown()
        end
      else
        refreshMessageList()
      end
  end,
})

return _M
