--[[
  vConsole — 调试悬浮窗（对接 LuaActivity 日志）

  require "vConsole"  -- 建议放在 setContentView 之后
  UI：AppCompatDialog + ViewPager
  颜色：内置 LIGHT / DARK 固定色（isNightMode 切换），不读主题 attr / dynamicColor
  结构：单文件 + vc 表挂载（压低 main chunk local，规避 Luaj 200 上限）

  loadlayout 必须传绑定表，禁止单参（单参 env 默认 _G，id 会污染全局）：
    悬浮钮 → S.bubbleIds
    面板   → ui（vc.ui）
    动态钮 → 临时 holder 表

  Tabs: Prints / Vars / Logcat / Text / Control / Views
  Hooks: print, printf, error, assert, onError
  Control: Device / Memory / Intent / Views / Paths / GC / Pause / Screen / Hist
]]

if rawget(_G, "__vConsole_installed") then return true end
_G.__vConsole_installed = true

local bindClass = luajava.bindClass
local activity, this = activity, this
local utf8 = utf8 or require "utf8"

local vc = {
  J = {},
  c = {},
  S = {},
  api = {},
  ui = {},
  LIGHT = {
    primary = 0xFF1565C0,
    onPrimary = 0xFFFFFFFF,
    primaryContainer = 0xFFD1E4FF,
    onPrimaryContainer = 0xFF001D36,
    secondaryContainer = 0xFFD7E3F7,
    onSecondaryContainer = 0xFF101C2B,
    surface = 0xFFF8F9FF,
    surfaceContainer = 0xFFECEDF3,
    surfaceContainerHigh = 0xFFE6E8EE,
    surfaceContainerLow = 0xFFF2F3F9,
    onSurface = 0xFF191C20,
    onSurfaceVariant = 0xFF43474E,
    outline = 0xFFC3C6CF,
    error = 0xFFB3261E,
    errorContainer = 0xFFF9DEDC,
    onErrorContainer = 0xFF410E0B,
    success = 0xFF2E7D32,
    warning = 0xFFE65100,
  },
  DARK = {
    primary = 0xFF9ECAFF,
    onPrimary = 0xFF003258,
    primaryContainer = 0xFF00497D,
    onPrimaryContainer = 0xFFD1E4FF,
    secondaryContainer = 0xFF3E4759,
    onSecondaryContainer = 0xFFD7E3F7,
    surface = 0xFF111418,
    surfaceContainer = 0xFF1D2024,
    surfaceContainerHigh = 0xFF282A2F,
    surfaceContainerLow = 0xFF191C20,
    onSurface = 0xFFE1E2E8,
    onSurfaceVariant = 0xFFC3C6CF,
    outline = 0xFF8D9199,
    error = 0xFFF2B8B5,
    errorContainer = 0xFF8C1D18,
    onErrorContainer = 0xFFF9DEDC,
    success = 0xFF81C784,
    warning = 0xFFFFB74D,
  },
}

-- 短别名：main chunk 仅这几个 local（函数体通过 upvalue 使用）
local J, S, api, c, ui = vc.J, vc.S, vc.api, vc.c, vc.ui

J.Gravity = bindClass "android.view.Gravity"
J.MotionEvent = bindClass "android.view.MotionEvent"
J.ViewConfiguration = bindClass "android.view.ViewConfiguration"
J.WindowManager = bindClass "android.view.WindowManager"
J.PixelFormat = bindClass "android.graphics.PixelFormat"
J.System = bindClass "java.lang.System"
J.Runtime = bindClass "java.lang.Runtime"
J.Build = bindClass "android.os.Build"
J.Context = bindClass "android.content.Context"
J.Intent = bindClass "android.content.Intent"
J.TypedValue = bindClass "android.util.TypedValue"
J.GradientDrawable = bindClass "android.graphics.drawable.GradientDrawable"
J.FrameLayout = bindClass "android.widget.FrameLayout"
J.LinearLayout = bindClass "android.widget.LinearLayout"
J.ListView = bindClass "android.widget.ListView"
J.ScrollView = bindClass "android.widget.ScrollView"
J.HorizontalScrollView = bindClass "android.widget.HorizontalScrollView"
J.TextView = bindClass "androidx.appcompat.widget.AppCompatTextView"
J.EditText = bindClass "androidx.appcompat.widget.AppCompatEditText"
J.Button = bindClass "androidx.appcompat.widget.AppCompatButton"
J.ViewPager = bindClass "androidx.viewpager.widget.ViewPager"
J.AppCompatDialog = bindClass "androidx.appcompat.app.AppCompatDialog"
J.ColorDrawable = bindClass "android.graphics.drawable.ColorDrawable"
J.HapticFeedbackConstants = bindClass "android.view.HapticFeedbackConstants"
J.ClipData = bindClass "android.content.ClipData"
J.Spannable = bindClass "android.text.Spannable"
J.SpannableStringBuilder = bindClass "android.text.SpannableStringBuilder"
J.ForegroundColorSpan = bindClass "android.text.style.ForegroundColorSpan"
J.BackgroundColorSpan = bindClass "android.text.style.BackgroundColorSpan"
J.SimpleDateFormat = bindClass "java.text.SimpleDateFormat"
J.File = bindClass "java.io.File"
J.FileOutputStream = bindClass "java.io.FileOutputStream"
J.LuaAdapter = bindClass "com.androlua.adapter.LuaAdapter"
J.Toast = bindClass "android.widget.Toast"
J.View = bindClass "android.view.View"
J.LuaActivityClass = bindClass "com.androlua.LuaActivity"

S.MAX_PRINT = 500
S.MAX_LOGCAT = 300
S.MAX_EVAL_HISTORY = 12
S.themeReady = false
S.dm = activity.getResources().getDisplayMetrics()
S.printStore = {}
S.printData = {}
S.printFull = {}
S.printAdp = nil
S.printFilter = "all"
S.printQuery = ""
S.logcatFull = {}
S.logcatData = {}
S.logcatAdp = nil
S.logcatPos = 1
S.variablePath = {}
S.variableKv = {}
S.variableNode = {}
S.variableData = {}
S.variableAdp = nil
S.variableSpanCache = {}
S.varQuery = ""
S.spanFlags = J.Spannable.SPAN_INCLUSIVE_INCLUSIVE
S.dateFmt = J.SimpleDateFormat("HH:mm:ss.SSS")
S.fileStampFmt = J.SimpleDateFormat("yyyyMMdd_HHmmss")
S.sheet = nil
S.hasError = false
S.hostLogsCursor = 0
S.suppressHostMirror = false
S.lastCrashPath = nil
S.loggingPaused = false
S.keepScreenOn = false
S.evalHistory = {}
S.logcatTypes = { "", "lua:* *:S", "tcc:* *:S", "*:E", "*:W", "*:I", "*:D", "*:V" }
-- 芯片文案 key：All/Lua/Tcc/E…（与 S.L 共享）
S.logcatLabelKeys = { "all", "lc_lua", "lc_tcc", "lc_e", "lc_w", "lc_i", "lc_d", "lc_v" }
S.printFilterIds = {
  { "pf_all", "all", "all" },
  { "pf_error", "error", "error" },
  { "pf_warn", "warn", "warn" },
  { "pf_info", "info", "info" },
  { "pf_log", "log", "log" },
}
S.hostPrint = print
S.hostPrintf = printf
S.hostError = error
S.hostAssert = assert
S.bubbleHost = nil
S.bubbleLp = nil
S.contentRoot = nil
S.wm = activity.getSystemService(J.Context.WINDOW_SERVICE)
S.bubbleIds = {}
S.bubbleAttached = false
S.bubble = nil
S.touchSlop = J.ViewConfiguration.get(activity).getScaledTouchSlop()
S.drag = { downX = 0, downY = 0, startX = 0, startY = 0, moved = false, dragging = false }
S.colorKey = nil
S.colorArrow = nil
S.colorTable = nil
S.bootDone = false
S.ERROR_NEEDLES = {
  "vm error:", "syntax error", "stack traceback", "Error:", "Runtime error",
}
S.WARN_NEEDLES = {
  "no matching overload", "exception in Java", "attempt to call",
  "bad argument", "Warning",
}
S.VC_HIDDEN_GLOBALS = {
  __vConsole_installed = true,
  log = true,
  safe_error = true,
  explain = true,
  info = true,
  warning = true,
  paintLogcatBadges = true,
  print = true,
  printf = true,
  error = true,
  assert = true,
  onError = true,
}
S.logcatChipIds = {
  "lc_all", "lc_lua", "lc_tcc", "lc_e", "lc_w", "lc_i", "lc_d", "lc_v",
}
S.tabIds = { "tab_prints", "tab_vars", "tab_logcat", "tab_text", "tab_control", "tab_views" }
-- 视图树
S.viewTreeRoot = nil
S.viewTreeFlat = {}
S.viewTreeData = {}
S.viewTreeAdp = nil
S.viewOnlyVisible = false

-- ─── I18N：共享 key → { en, zh }，api.t(key) 取当前语言 ───
S.lang = "en" -- "en" | "zh"
S.L = {
  -- header / common
  app_sub = { "Runtime debugger", "运行时调试器" },
  clear = { "Clear", "清空" },
  export = { "Export", "导出" },
  lang = { "中文", "EN" }, -- 按钮显示「目标语言」
  close = { "Close", "关闭" },
  copy = { "Copy", "复制" },
  share = { "Share", "分享" },
  refresh = { "Refresh", "刷新" },
  save = { "Save", "保存" },
  paste = { "Paste", "粘贴" },
  run = { "Run", "运行" },
  empty = { "Empty", "空" },
  bottom = { "Bottom", "到底" },
  root = { "Root", "根" },
  copy_path = { "Copy path", "复制路径" },
  -- tabs
  tab_prints = { "Prints", "输出" },
  tab_vars = { "Vars", "变量" },
  tab_logcat = { "Logcat", "系统日志" },
  tab_text = { "Text", "文本" },
  tab_control = { "Control", "控制" },
  tab_views = { "Views", "视图" },
  views_meta = { "%d rows · tap expand", "%d 行 · 点展开" },
  views_only_vis = { "Visible", "仅可见" },
  views_all = { "All", "全部" },
  views_collapse = { "Collapse", "折叠" },
  views_detail = { "View detail", "节点详情" },
  views_empty = { "No views", "无视图" },
  -- filters
  all = { "All", "全部" },
  error = { "Error", "错误" },
  warn = { "Warn", "警告" },
  info = { "Info", "信息" },
  log = { "Log", "普通" },
  lc_lua = { "Lua", "Lua" },
  lc_tcc = { "Tcc", "Tcc" },
  lc_e = { "E", "E" },
  lc_w = { "W", "W" },
  lc_i = { "I", "I" },
  lc_d = { "D", "D" },
  lc_v = { "V", "V" },
  -- prints empty
  no_logs = { "No logs yet", "暂无日志" },
  no_logs_hint = { "print() · sendMsg · onError will show here", "print() · sendMsg · onError 会出现在这里" },
  entries = { "%d entries", "%d 条" },
  -- vars / text
  node = { "node: /", "节点: /" },
  inspect = { "Inspect", "检查" },
  -- control
  tools = { "Tools", "工具" },
  device = { "Device", "设备" },
  memory = { "Memory", "内存" },
  intent = { "Intent", "Intent" },
  views = { "Views", "视图" },
  paths = { "Paths", "路径" },
  gc = { "GC", "GC" },
  pause_log = { "Pause log", "暂停日志" },
  resume_log = { "Resume log", "恢复日志" },
  screen_on = { "Screen on", "常亮开" },
  screen_off = { "Screen off", "常亮关" },
  hide_bubble = { "Hide bubble", "隐藏气泡" },
  eval_hist = { "Eval hist", "历史" },
  eval_hint = { "Eval Lua in this environment", "在此环境执行 Lua" },
  code_hint = { "Lua code…", "Lua 代码…" },
  finish = { "Finish", "结束" },
  recreate = { "Recreate", "重建" },
  restart = { "Restart", "重启" },
  kill = { "Kill", "强杀" },
  -- toasts / status
  export_failed = { "Export failed", "导出失败" },
  save_failed = { "Save failed", "保存失败" },
  saved = { "Saved: %s", "已保存: %s" },
  copied = { "Copied", "已复制" },
  copied_n = { "Copied %d", "已复制 %d" },
  copied_logcat = { "Copied logcat", "已复制 logcat" },
  nothing_copy = { "Nothing to copy", "无可复制内容" },
  empty_logcat = { "Empty logcat", "logcat 为空" },
  logging_paused = { "Logging paused", "日志已暂停" },
  logging_resumed = { "Logging resumed", "日志已恢复" },
  bubble_hidden = { "Bubble hidden until recreate / re-require", "气泡已隐藏，重建/重新 require 后恢复" },
  export_banner = { "=== vConsole export ===", "=== vConsole 导出 ===" },
  empty_logcat_body = { "<empty logcat>", "<logcat 为空>" },
  logcat_unavail = { "<logcat unavailable>", "<logcat 不可用>" },
  lang_switched = { "Language: English", "语言: 中文" },
  search_logs = { "Search logs…", "搜索日志…" },
  search_vars = { "Filter keys…", "筛选键名…" },
  text_buffer = { "Text buffer…", "文本缓冲…" },
  key_hint = { "Filter keys…", "筛选键名…" },
  share_logs = { "Share logs", "分享日志" },
  share_text = { "Share text", "分享文本" },
  eval_history = { "Eval history", "执行历史" },
  no_eval_hist = { "No eval history", "无执行历史" },
  keep_screen_on = { "Keep screen ON", "屏幕常亮：开" },
  keep_screen_off = { "Keep screen OFF", "屏幕常亮：关" },
  logs_meta = { "%d logs · filter %s", "%d 条 · 筛选 %s" },
  filtered_meta = { "%d / %d · %s%s", "%d / %d · %s%s" },
  copied_panel = { "Copied (panel closed)", "已复制（面板未开）" },
  copied_line = { "Copied log line", "已复制该行" },
  mem_gc = { "Memory / GC", "内存 / GC" },
  eval_result = { "Eval result", "执行结果" },
  loaded_eval = { "Loaded last eval (%d)", "已载入上次代码 (%d)" },
  runtime_error = { "runtime error", "运行时错误" },
  syntax_error = { "syntax error", "语法错误" },
}

function api.t(key)
  local row = S.L[key]
  if not row then return tostring(key or "") end
  local i = (S.lang == "zh") and 2 or 1
  return row[i] or row[1] or tostring(key)
end

function api.tf(key, ...)
  local fmt = api.t(key)
  if select("#", ...) == 0 then return fmt end
  local ok, s = pcall(string.format, fmt, ...)
  return ok and s or fmt
end

function api.setLang(lang, quiet)
  if lang ~= "zh" and lang ~= "en" then lang = "en" end
  S.lang = lang
  if this and this.setSharedData then
    this.setSharedData("vconsole_lang", lang)
  end
  api.applyI18n()
  if not quiet then api.toast(api.t("lang_switched")) end
end

function api.toggleLang()
  api.setLang(S.lang == "zh" and "en" or "zh")
end

function api.detectSystemLang()
  local Locale = bindClass "java.util.Locale"
  local l = Locale.getDefault().getLanguage()
  if l and tostring(l):sub(1, 2) == "zh" then return "zh" end
  return "en"
end

function api.loadLangPref()
  if this and this.getSharedData then
    local v = this.getSharedData("vconsole_lang", nil)
    if v == "zh" or v == "en" then
      S.lang = v
      return
    end
  end
  S.lang = api.detectSystemLang()
end

function api.tabTitleKeys()
  return { "tab_prints", "tab_vars", "tab_logcat", "tab_text", "tab_control", "tab_views" }
end

function api.syncPagerTitles()
  if not ui.page then return end
  local adp = ui.page.getAdapter()
  if not adp or not adp.setPageTitle then return end
  local keys = api.tabTitleKeys()
  for i = 1, #keys do
    adp.setPageTitle(i - 1, api.t(keys[i]))
  end
end

--- 刷新已创建控件文案（切换语言 / 打开面板后）
function api.applyI18n()
  local function setText(view, key)
    if view then view.setText(api.t(key)) end
  end
  local function setHint(view, key)
    if view then view.setHint(api.t(key)) end
  end
  setText(ui.headerClear, "clear")
  setText(ui.headerExport, "export")
  setText(ui.headerLang, "lang")
  setText(ui.ctrlFinish, "finish")
  setText(ui.ctrlRecreate, "recreate")
  setText(ui.ctrlRestart, "restart")
  setText(ui.ctrlKill, "kill")
  setText(ui.ctrlDevice, "device")
  setText(ui.ctrlMem, "memory")
  setText(ui.ctrlIntent, "intent")
  setText(ui.ctrlViews, "views")
  setText(ui.ctrlPaths, "paths")
  setText(ui.ctrlGc, "gc")
  setText(ui.ctrlHide, "hide_bubble")
  setText(ui.ctrlHist, "eval_hist")
  setText(ui.ctrlRun, "run")
  setText(ui.ctrlInspectLabel, "inspect")
  setText(ui.ctrlToolsLabel, "tools")
  setText(ui.ctrlEvalLabel, "eval_hint")
  setHint(ui.printSearch, "search_logs")
  setHint(ui.textEdit, "text_buffer")
  setHint(ui.ctrlCode, "code_hint")
  setHint(ui.varSearch, "search_vars")
  if ui.ctrlPause then
    ui.ctrlPause.setText(S.loggingPaused and api.t("resume_log") or api.t("pause_log"))
  end
  if ui.ctrlScreen then
    ui.ctrlScreen.setText(S.keepScreenOn and api.t("screen_off") or api.t("screen_on"))
  end
  local keys = api.tabTitleKeys()
  for i, id in ipairs(S.tabIds) do
    setText(ui[id], keys[i])
  end
  for _, item in ipairs(S.printFilterIds) do
    setText(ui[item[1]], item[2])
  end
  for i, id in ipairs(S.logcatChipIds) do
    setText(ui[id], S.logcatLabelKeys[i])
  end
  setText(ui.printEmptyTitle, "no_logs")
  setText(ui.printEmptyHint, "no_logs_hint")
  if ui.headerSub and #S.printStore == 0 then
    setText(ui.headerSub, "app_sub")
  end
  api.syncPagerTitles()
  api.updatePrintMeta()
  pcall(function()
    local pos = 0
    if ui.page then pos = ui.page.getCurrentItem() end
    api.rebuildActionBar(pos)
  end)
end

--- 顶栏 Clear：按当前页清空
function api.clearForCurrentPage()
  local pos = 0
  if ui.page then pos = ui.page.getCurrentItem() end
  if pos == 2 then
    api.runBg(function()
      api.clearlog()
      return true
    end, function()
      api.refreshLogcat()
    end, "io")
  elseif pos == 3 then
    if ui.textEdit then ui.textEdit.setText(nil) end
  elseif pos == 1 then
    table.clear(S.variableNode)
    S.varQuery = ""
    if ui.varSearch then ui.varSearch.setText("") end
    api.refreshVars()
  elseif pos == 5 then
    api.viewTreeCollapseAll()
  else
    api.clearPrints()
  end
end

if not table.clear then
  function table.clear(t)
    if t then for k in pairs(t) do t[k] = nil end end
  end
end

function api.chainGlobal(name, handler)
  local prev = rawget(_G, name)
  _G[name] = function(...)
    local r = handler(...)
    if type(prev) == "function" then pcall(prev, ...) end
    return r
  end
end

function api.isNight()
  if this.isNightMode and this.isNightMode() then return true end
  local mode = activity.getResources().getConfiguration().uiMode
  -- UI_MODE_NIGHT_MASK=0x30, NIGHT_YES=0x20
  if type(mode) == "number" then
    return math.floor(mode / 16) % 4 == 2
  end
  return false
end

function api.resolveTheme(force)
  if S.themeReady and not force then return end
  local src = api.isNight() and vc.DARK or vc.LIGHT
  for k, v in pairs(src) do c[k] = v end
  c.muted = c.onSurfaceVariant
  S.dm = activity.getResources().getDisplayMetrics()
  S.themeReady = true
end

-- 启动时用固定色板
api.resolveTheme(true)

function api.dp(n)
  return J.TypedValue.applyDimension(J.TypedValue.COMPLEX_UNIT_DIP, n, S.dm)
end

function api.roundBg(color, radiusDp, strokeColor, strokeDp)
  local d = J.GradientDrawable()
  d.setShape(0)
  local fill = type(color) == "number" and color or c.surface
  d.setColor(fill)
  d.setCornerRadius(api.dp(radiusDp or 16))
  if type(strokeColor) == "number" then
    d.setStroke(math.max(1, math.floor(api.dp(strokeDp or 1))), strokeColor)
  end
  return d
end

function api.applyRound(view, color, radiusDp, strokeColor, strokeDp)
  if not view then return end
  view.setBackground(api.roundBg(color, radiusDp, strokeColor, strokeDp))
  view.setClipToOutline(true)
end

function api.vibrate(v)
  if not v then return end
  v.performHapticFeedback(
    J.HapticFeedbackConstants.CONTEXT_CLICK,
    J.HapticFeedbackConstants.FLAG_IGNORE_GLOBAL_SETTING)
end

function api.activityAlive()
  if activity.isFinishing() then return false end
  if activity.isDestroyed and activity.isDestroyed() then return false end
  return true
end

function api.toast(msg)
  J.Toast.makeText(activity, tostring(msg), J.Toast.LENGTH_SHORT).show()
end

function api.clipboard()
  return activity.getSystemService(J.Context.CLIPBOARD_SERVICE)
end

function api.clipboardSet(text)
  api.clipboard().setPrimaryClip(J.ClipData.newPlainText("vConsole", tostring(text or "")))
end

function api.clipboardGet()
  local ok, text = pcall(function()
    local clip = api.clipboard().getPrimaryClip()
    if clip and clip.getItemCount() > 0 then
      return tostring(clip.getItemAt(0).coerceToText(activity))
    end
    return ""
  end)
  return ok and text or ""
end

function api.dumpValue(v)
  if type(v) == "table" and type(dump) == "function" then
    local ok, s = pcall(dump, v)
    if ok and s then return s end
  end
  return tostring(v)
end

function api.truncate(s, n)
  s, n = tostring(s or ""), n or 120
  local ok, len = pcall(function() return utf8.len(s) end)
  if ok and len and len > n then
    local ok2, sub = pcall(function() return utf8.sub(s, 1, n) end)
    if ok2 and sub then return sub .. "…" end
  end
  if #s > n then return s:sub(1, n) .. "…" end
  return s
end

-- 日志级别 needles → S.ERROR_NEEDLES / S.WARN_NEEDLES

function api.messageHas(msg, needles)
  for i = 1, #needles do
    if msg:find(needles[i], 1, true) then return true end
  end
  return false
end

function api.levelForMessage(msg)
  msg = tostring(msg or "")
  if api.messageHas(msg, S.ERROR_NEEDLES) or msg:find("Runtime%s-error") then
    return "error"
  end
  if msg:find("xTask", 1, true) == 1 or api.messageHas(msg, S.WARN_NEEDLES) then
    return "warn"
  end
  return "log"
end

function api.colorForLevel(level)
  api.resolveTheme()
  if level == "error" then return c.error end
  if level == "warn" then return c.warning end
  if level == "info" then return c.success end
  return c.onSurface
end

function api.colorForMessage(msg)
  return api.colorForLevel(api.levelForMessage(msg))
end

function api.readlog(filter)
  local ok, out = pcall(function()
    local p = io.popen("logcat -d -v long " .. (filter or ""))
    if not p then return "" end
    local s = p:read("*a") or ""
    p:close()
    s = s:gsub("%-+ beginning of[^\n]*\n", "")
    if #s == 0 then s = api.t("empty_logcat_body") end
    return s
  end)
  return ok and out or api.t("logcat_unavail")
end

function api.clearlog()
  pcall(function()
    local p = io.popen("logcat -c")
    if p then p:close() end
  end)
end

function api.sendHostMsg(msg)
  if S.suppressHostMirror then return end
  pcall(function() activity.sendMsg(tostring(msg or "")) end)
end

-- ─── 悬浮钮（延迟创建，等 dynamicColor 后再 loadlayout） ─

function api.paintBubble(err)
  if not S.bubble then return end
  api.resolveTheme()
  local fill = err and c.errorContainer or c.primaryContainer
  local stroke = err and c.error or c.outline
  local fg = err and c.onErrorContainer or c.onPrimaryContainer
  api.applyRound(S.bubbleIds.card, fill, 24, stroke, 1.25)
  api.applyRound(S.bubbleIds.badge, c.error, 4.5)
  if S.bubbleIds.label then
    S.bubbleIds.label.setTextColor(fg)
    S.bubbleIds.label.setText(err and "!" or "VC")
  end
  if S.bubbleIds.badge then
    S.bubbleIds.badge.setVisibility(err and J.View.VISIBLE or J.View.GONE)
  end
  S.bubble.setElevation(api.dp(10))
  S.bubble.setTranslationZ(api.dp(4))
  S.bubble.setAlpha(0.96)
  if S.bubbleIds.card then
    S.bubbleIds.card.setElevation(api.dp(10))
    S.bubbleIds.card.setTranslationZ(api.dp(4))
  end
end

function api.ensureBubble()
  if S.bubble then return true end
  api.resolveTheme(true)
  S.bubbleIds = {}
  local view = loadlayout({
    J.FrameLayout,
    id = "card",
    layout_width = "48dp",
    layout_height = "48dp",
    clickable = true,
    focusable = true,
    {
      J.TextView,
      id = "label",
      layout_gravity = "center",
      text = "VC",
      textSize = "13sp",
      textStyle = "bold",
      textColor = c.onPrimaryContainer,
      gravity = "center",
    },
    {
      J.View,
      id = "badge",
      layout_width = "9dp",
      layout_height = "9dp",
      layout_gravity = "top|end",
      layout_marginTop = "4dp",
      layout_marginEnd = "4dp",
      visibility = "gone",
    },
  }, S.bubbleIds)
  if view then
    S.bubble = view
    api.paintBubble(false)
    if api.wireBubbleTouch then api.wireBubbleTouch() end
    return true
  end
  return false
end

function api.setBubbleError(on)
  S.hasError = on and true or false
  api.paintBubble(S.hasError)
end

function api.removeBubble()
  if not S.bubbleAttached or not S.bubble then return end
  if S.bubbleHost == "wm" then
    S.wm.removeView(S.bubble)
  elseif S.bubble.getParent() then
    S.bubble.getParent().removeView(S.bubble)
  end
  S.bubbleAttached = false
  S.bubbleHost = nil
end

function api.makeContentLp(x, y)
  local lp = J.FrameLayout.LayoutParams(api.dp(48), api.dp(48))
  lp.gravity = J.Gravity.TOP | J.Gravity.START
  lp.leftMargin = x
  lp.topMargin = y
  return lp
end

function api.makeWmLp(x, y)
  local lp = J.WindowManager.LayoutParams()
  lp.width = J.WindowManager.LayoutParams.WRAP_CONTENT
  lp.height = J.WindowManager.LayoutParams.WRAP_CONTENT
  lp.gravity = J.Gravity.TOP | J.Gravity.START
  lp.flags = J.WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
    | J.WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
    | J.WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
  lp.format = J.PixelFormat.TRANSLUCENT
  lp.x = x
  lp.y = y
  return lp
end

function api.getBubbleXY()
  if S.bubbleHost == "content" and S.bubbleLp then
    return S.bubbleLp.leftMargin or 0, S.bubbleLp.topMargin or 0
  end
  if S.bubbleLp then return S.bubbleLp.x or 0, S.bubbleLp.y or 0 end
  return 0, 0
end

function api.setBubbleXY(x, y)
  if not S.bubbleLp or not S.bubble then return end
  if S.bubbleHost == "content" then
    S.bubbleLp.leftMargin = x
    S.bubbleLp.topMargin = y
    S.bubble.setLayoutParams(S.bubbleLp)
  else
    S.bubbleLp.x = x
    S.bubbleLp.y = y
    S.wm.updateViewLayout(S.bubble, S.bubbleLp)
  end
end

function api.screenSize()
  local w, h = S.dm.widthPixels, S.dm.heightPixels
  if this.getWidth then
    local tw, th = this.getWidth(), this.getHeight()
    if tw and tw > 0 then w = tw end
    if th and th > 0 then h = th end
  end
  return w, h
end

function api.clampBubble(x, y)
  local w = S.bubble.getWidth()
  local h = S.bubble.getHeight()
  if w <= 0 then w = api.dp(48) end
  if h <= 0 then h = api.dp(48) end
  local sw, sh = api.screenSize()
  local maxX = math.max(0, sw - w)
  local maxY = math.max(0, sh - h)
  if x < 0 then x = 0 elseif x > maxX then x = maxX end
  if y < 0 then y = 0 elseif y > maxY then y = maxY end
  return math.floor(x), math.floor(y)
end

function api.snapBubble()
  local w = S.bubble.getWidth()
  if w <= 0 then w = api.dp(48) end
  local x, y = api.getBubbleXY()
  local sw = select(1, api.screenSize())
  if x + w / 2 < sw / 2 then
    x = api.dp(8)
  else
    x = math.floor(sw - w - api.dp(8))
  end
  api.setBubbleXY(api.clampBubble(x, y))
end

function api.resolveContentRoot()
  local androidR = bindClass "android.R"
  local root = activity.findViewById(androidR.id.content)
  if root then return root end
  if this.getDecorView then return this.getDecorView() end
  return nil
end

function api.attachBubble()
  if S.bubbleAttached or not api.activityAlive() then return end
  if not api.ensureBubble() then return end
  local sw, sh = api.screenSize()
  local x = math.floor(sw - api.dp(64))
  local y = math.floor(sh * 0.35)

  S.contentRoot = api.resolveContentRoot()
  if S.contentRoot then
    S.bubbleLp = api.makeContentLp(x, y)
    S.contentRoot.addView(S.bubble, S.bubbleLp)
    S.bubbleHost = "content"
    S.bubbleAttached = true
  else
    -- 回退 WindowManager（无 content 时）
    local ok = pcall(function()
      S.bubbleLp = api.makeWmLp(x, y)
      S.wm.addView(S.bubble, S.bubbleLp)
      S.bubbleHost = "wm"
    end)
    S.bubbleAttached = ok
  end

  if S.bubbleAttached then
    api.setBubbleError(S.hasError)
  else
    activity.sendMsg("[vConsole] attach bubble failed")
  end
end

function api.wireBubbleTouch()
  if not S.bubbleIds or not S.bubbleIds.card then return end
  S.bubbleIds.card.onTouch = function(v, e)
    local action = e.getActionMasked()
    local rx, ry = e.getRawX(), e.getRawY()
    if action == J.MotionEvent.ACTION_DOWN then
      S.drag.downX, S.drag.downY = rx, ry
      S.drag.startX, S.drag.startY = api.getBubbleXY()
      S.drag.moved, S.drag.dragging = false, true
      local parent = v.getParent()
      if parent and parent.requestDisallowInterceptTouchEvent then
        parent.requestDisallowInterceptTouchEvent(true)
      end
      return true
    elseif action == J.MotionEvent.ACTION_MOVE and S.drag.dragging then
      local dx, dy = rx - S.drag.downX, ry - S.drag.downY
      if not S.drag.moved and (dx * dx + dy * dy) > (S.touchSlop * S.touchSlop) then
        S.drag.moved = true
      end
      if S.drag.moved then
        api.setBubbleXY(api.clampBubble(S.drag.startX + dx, S.drag.startY + dy))
      end
      return true
    elseif action == J.MotionEvent.ACTION_UP or action == J.MotionEvent.ACTION_CANCEL then
      S.drag.dragging = false
      local parent = v.getParent()
      if parent and parent.requestDisallowInterceptTouchEvent then
        parent.requestDisallowInterceptTouchEvent(false)
      end
      if S.drag.moved then
        api.snapBubble()
      else
        api.vibrate(v)
        api.showSheet()
      end
      return true
    end
    return false
  end
end

-- ─── 面板布局（系统控件） ───────────────────────────────
function api.spacer(w)
  return { J.View, layout_width = w or "8dp", layout_height = "1dp" }
end

function api.hairline()
  return {
    J.View,
    layout_width = "match",
    layout_height = "1dp",
    BackgroundColor = c.outline,
  }
end

function api.compactButtonMetrics(btn, minHDp, padHDp)
  if not btn then return end
  btn.setMinimumHeight(api.dp(minHDp or 36))
  btn.setMinHeight(api.dp(minHDp or 36))
  btn.setMinimumWidth(0)
  btn.setMinWidth(0)
  btn.setPadding(
    math.floor(api.dp(padHDp or 10)),
    math.floor(api.dp(4)),
    math.floor(api.dp(padHDp or 10)),
    math.floor(api.dp(4)))
  btn.setIncludeFontPadding(false)
  btn.setAllCaps(false)
  if btn.setStateListAnimator then
    btn.setStateListAnimator(nil)
  end
  if btn.setElevation then
    btn.setElevation(0)
  end
end

function api.applyButtonTheme(btn, bg, fg, radiusDp, minHDp)
  if not btn then return end
  api.resolveTheme()
  local bgInt = type(bg) == "number" and bg or 0
  local fgInt = type(fg) == "number" and fg or c.primary
  local r = radiusDp or 12
  api.compactButtonMetrics(btn, minHDp or 36, 12)
  if bgInt == 0 then
    btn.setBackgroundColor(0)
  else
    api.applyRound(btn, bgInt, r)
  end
  btn.setTextColor(fgInt)
end

function api.tonalBtn(id, text)
  return {
    J.Button,
    id = id,
    text = text,
    layout_width = "0dp",
    layout_weight = 1,
    layout_height = "40dp",
    minHeight = "40dp",
    textSize = "12sp",
    includeFontPadding = false,
    BackgroundColor = c.secondaryContainer,
    textColor = c.onSecondaryContainer,
  }
end

function api.textBtn(id, text)
  return {
    J.Button,
    id = id,
    text = text,
    layout_width = "0dp",
    layout_weight = 1,
    layout_height = "36dp",
    minHeight = "36dp",
    textSize = "12sp",
    includeFontPadding = false,
    BackgroundColor = 0,
    textColor = c.primary,
  }
end

function api.filterBtn(id, text)
  return {
    J.Button,
    id = id,
    text = text,
    layout_width = "wrap",
    layout_height = "32dp",
    minHeight = "32dp",
    minWidth = "0dp",
    textSize = "12sp",
    includeFontPadding = false,
    paddingLeft = "10dp",
    paddingRight = "10dp",
    paddingTop = "0dp",
    paddingBottom = "0dp",
    BackgroundColor = 0,
    textColor = c.onSurfaceVariant,
    layout_marginEnd = "4dp",
  }
end

function api.printsPage()
  return {
    J.LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
    BackgroundColor = c.surface,
    {
      J.LinearLayout,
      orientation = "horizontal",
      layout_width = "match",
      layout_height = "36dp",
      gravity = "center_vertical",
      paddingLeft = "10dp",
      paddingRight = "4dp",
      BackgroundColor = c.surfaceContainerHigh,
      layout_marginStart = "10dp",
      layout_marginEnd = "10dp",
      layout_marginTop = "6dp",
      focusable = true,
      focusableInTouchMode = true,
      {
        J.TextView,
        text = "⌕",
        textSize = "14sp",
        textColor = c.onSurfaceVariant,
        layout_marginEnd = "4dp",
      },
      {
        J.EditText,
        id = "printSearch",
        layout_width = "0dp",
        layout_weight = 1,
        layout_height = "match",
        textSize = "13sp",
        textColor = c.onSurface,
        hint = api.t("search_logs"),
        singleLine = true,
        BackgroundColor = 0,
        paddingTop = "0dp",
        paddingBottom = "0dp",
        imeOptions = "actionSearch",
      },
      {
        J.Button,
        id = "printSearchClear",
        text = "×",
        layout_width = "32dp",
        layout_height = "32dp",
        minHeight = "32dp",
        minWidth = "32dp",
        textSize = "16sp",
        BackgroundColor = 0,
        textColor = c.primary,
        visibility = "gone",
      },
    },
    {
      J.HorizontalScrollView,
      layout_width = "match",
      layout_height = "wrap",
      horizontalScrollBarEnabled = false,
      {
        J.LinearLayout,
        id = "printFilterChips",
        orientation = "horizontal",
        layout_width = "wrap",
        layout_height = "wrap",
        gravity = "center_vertical",
        paddingLeft = "8dp",
        paddingRight = "8dp",
        paddingTop = "4dp",
        paddingBottom = "2dp",
          api.filterBtn("pf_all", api.t("all")),
          api.filterBtn("pf_error", api.t("error")),
          api.filterBtn("pf_warn", api.t("warn")),
          api.filterBtn("pf_info", api.t("info")),
          api.filterBtn("pf_log", api.t("log")),
      },
    },
    {
      J.TextView,
      id = "printMeta",
      layout_width = "match",
      layout_height = "wrap",
      paddingLeft = "12dp",
      paddingRight = "12dp",
      paddingTop = "2dp",
      paddingBottom = "2dp",
      text = api.tf("entries", 0),
      textSize = "11sp",
      textColor = c.onSurfaceVariant,
    },
    {
      J.FrameLayout,
      layout_width = "match",
      layout_height = "0dp",
      layout_weight = 1,
      {
        J.LinearLayout,
        id = "printEmpty",
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        layout_gravity = "center",
        gravity = "center",
        padding = "20dp",
        {
          J.TextView,
          id = "printEmptyTitle",
          text = api.t("no_logs"),
          textSize = "14sp",
          textStyle = "bold",
          textColor = c.onSurface,
          gravity = "center",
        },
        {
          J.TextView,
          id = "printEmptyHint",
          text = api.t("no_logs_hint"),
          textSize = "12sp",
          textColor = c.onSurfaceVariant,
          gravity = "center",
          layout_marginTop = "6dp",
        },
      },
      {
        J.ListView,
        id = "printList",
        layout_width = "match",
        layout_height = "match",
        DividerHeight = 0,
        FastScrollEnabled = true,
        overScrollMode = 2,
      },
    },
  }
end

function api.buildSheetContent()
  for k in pairs(ui) do ui[k] = nil end
  return loadlayout({
    J.LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
    BackgroundColor = c.surface,
    {
      J.LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      paddingTop = "4dp",
      {
        J.LinearLayout,
        orientation = "horizontal",
        layout_width = "match",
        layout_height = "wrap",
        gravity = "center_vertical",
        paddingLeft = "12dp",
        paddingRight = "4dp",
        paddingTop = "4dp",
        paddingBottom = "2dp",
        {
          J.LinearLayout,
          orientation = "vertical",
          layout_width = "0dp",
          layout_weight = 1,
          layout_height = "wrap",
          {
            J.TextView,
            text = "vConsole",
            textSize = "16sp",
            textStyle = "bold",
            textColor = c.onSurface,
          },
          {
            J.TextView,
            id = "headerSub",
            text = api.t("app_sub"),
            textSize = "11sp",
            textColor = c.onSurfaceVariant,
            layout_marginTop = "0dp",
          },
        },
        {
          J.Button,
          id = "headerClear",
          text = api.t("clear"),
          layout_width = "wrap",
          layout_height = "32dp",
          minHeight = "32dp",
          minWidth = "0dp",
          textSize = "12sp",
          paddingLeft = "10dp",
          paddingRight = "10dp",
          BackgroundColor = 0,
          textColor = c.primary,
        },
        {
          J.Button,
          id = "headerExport",
          text = api.t("export"),
          layout_width = "wrap",
          layout_height = "32dp",
          minHeight = "32dp",
          minWidth = "0dp",
          textSize = "12sp",
          paddingLeft = "10dp",
          paddingRight = "10dp",
          BackgroundColor = 0,
          textColor = c.primary,
        },
        {
          J.Button,
          id = "headerLang",
          text = api.t("lang"),
          layout_width = "wrap",
          layout_height = "32dp",
          minHeight = "32dp",
          minWidth = "0dp",
          textSize = "12sp",
          paddingLeft = "10dp",
          paddingRight = "10dp",
          BackgroundColor = 0,
          textColor = c.primary,
        },
      },
      {
        J.HorizontalScrollView,
        layout_width = "match",
        layout_height = "wrap",
        horizontalScrollBarEnabled = false,
        {
          J.LinearLayout,
          id = "tabBar",
          orientation = "horizontal",
          layout_width = "wrap",
          layout_height = "wrap",
          gravity = "center_vertical",
          paddingLeft = "6dp",
          paddingRight = "6dp",
          paddingTop = "2dp",
          paddingBottom = "4dp",
          api.filterBtn("tab_prints", api.t("tab_prints")),
          api.filterBtn("tab_vars", api.t("tab_vars")),
          api.filterBtn("tab_logcat", api.t("tab_logcat")),
          api.filterBtn("tab_text", api.t("tab_text")),
          api.filterBtn("tab_control", api.t("tab_control")),
          api.filterBtn("tab_views", api.t("tab_views")),
        },
      },
      api.hairline(),
    },
    {
      J.ViewPager,
      id = "page",
      layout_width = "match",
      layout_height = "0dp",
      layout_weight = 1,
      overScrollMode = 2,
      pagesWithTitle = {
        {
          api.printsPage(),
          {
            J.LinearLayout,
            orientation = "vertical",
            layout_width = "match",
            layout_height = "match",
            {
              J.LinearLayout,
              orientation = "horizontal",
              layout_width = "match",
              layout_height = "36dp",
              gravity = "center_vertical",
              paddingLeft = "10dp",
              paddingRight = "10dp",
              focusable = true,
              focusableInTouchMode = true,
              {
                J.TextView,
                id = "varPath",
                text = api.t("node"),
                textSize = "11sp",
                textColor = c.success,
                layout_marginEnd = "6dp",
              },
              {
                J.EditText,
                id = "varSearch",
                layout_width = "0dp",
                layout_height = "match",
                layout_weight = 1,
                textSize = "12sp",
                textColor = c.onSurface,
                hint = api.t("search_vars"),
                singleLine = true,
                BackgroundColor = 0,
                paddingTop = "0dp",
                paddingBottom = "0dp",
                imeOptions = "actionSearch",
              },
            },
            {
              J.ListView,
              id = "varList",
              layout_width = "match",
              layout_height = "0dp",
              layout_weight = 1,
              DividerHeight = 0,
              FastScrollEnabled = true,
              overScrollMode = 2,
            },
          },
          {
            J.LinearLayout,
            orientation = "vertical",
            layout_width = "match",
            layout_height = "match",
            {
              J.HorizontalScrollView,
              layout_width = "match",
              layout_height = "wrap",
              horizontalScrollBarEnabled = false,
              {
                J.LinearLayout,
                id = "logcatChips",
                orientation = "horizontal",
                layout_width = "wrap",
                layout_height = "wrap",
                gravity = "center_vertical",
                paddingLeft = "6dp",
                paddingRight = "6dp",
                paddingTop = "4dp",
                paddingBottom = "2dp",
                api.filterBtn("lc_all", api.t("all")),
                api.filterBtn("lc_lua", api.t("lc_lua")),
                api.filterBtn("lc_tcc", api.t("lc_tcc")),
                api.filterBtn("lc_e", api.t("lc_e")),
                api.filterBtn("lc_w", api.t("lc_w")),
                api.filterBtn("lc_i", api.t("lc_i")),
                api.filterBtn("lc_d", api.t("lc_d")),
                api.filterBtn("lc_v", api.t("lc_v")),
              },
            },
            {
              J.ListView,
              id = "logcatList",
              layout_width = "match",
              layout_height = "0dp",
              layout_weight = 1,
              DividerHeight = 0,
              FastScrollEnabled = true,
              overScrollMode = 2,
            },
          },
          {
            J.LinearLayout,
            orientation = "vertical",
            layout_width = "match",
            layout_height = "match",
            focusable = true,
            focusableInTouchMode = true,
            {
              J.ScrollView,
              layout_width = "match",
              layout_height = "match",
              fillViewport = true,
              overScrollMode = 2,
              {
                J.EditText,
                id = "textEdit",
                layout_width = "match",
                layout_height = "wrap",
                minHeight = "140dp",
                padding = "12dp",
                textSize = "12sp",
                textColor = c.onSurface,
                hint = api.t("text_buffer"),
                gravity = "start|top",
                BackgroundColor = 0,
                textIsSelectable = true,
                inputType = "textMultiLine",
              },
            },
          },
          {
            J.LinearLayout,
            orientation = "vertical",
            layout_width = "match",
            layout_height = "match",
            {
              J.ScrollView,
              layout_width = "match",
              layout_height = "0dp",
              layout_weight = 1,
              fillViewport = true,
              {
                J.LinearLayout,
                orientation = "vertical",
                layout_width = "match",
                layout_height = "wrap",
                padding = "10dp",
                {
                  J.LinearLayout,
                  layout_width = "match",
                  layout_height = "wrap",
                  api.tonalBtn("ctrlFinish", api.t("finish")),
                  api.spacer("6dp"),
                  api.tonalBtn("ctrlRecreate", api.t("recreate")),
                },
                {
                  J.LinearLayout,
                  layout_width = "match",
                  layout_height = "wrap",
                  layout_marginTop = "6dp",
                  api.tonalBtn("ctrlRestart", api.t("restart")),
                  api.spacer("6dp"),
                  api.tonalBtn("ctrlKill", api.t("kill")),
                },
                {
                  J.TextView,
                  id = "ctrlInspectLabel",
                  text = api.t("inspect"),
                  textSize = "11sp",
                  textColor = c.onSurfaceVariant,
                  layout_marginTop = "10dp",
                  layout_marginBottom = "4dp",
                },
                {
                  J.LinearLayout,
                  layout_width = "match",
                  layout_height = "wrap",
                  api.tonalBtn("ctrlDevice", api.t("device")),
                  api.spacer("6dp"),
                  api.tonalBtn("ctrlMem", api.t("memory")),
                },
                {
                  J.LinearLayout,
                  layout_width = "match",
                  layout_height = "wrap",
                  layout_marginTop = "6dp",
                  api.tonalBtn("ctrlIntent", api.t("intent")),
                  api.spacer("6dp"),
                  api.tonalBtn("ctrlViews", api.t("views")),
                },
                {
                  J.LinearLayout,
                  layout_width = "match",
                  layout_height = "wrap",
                  layout_marginTop = "6dp",
                  api.tonalBtn("ctrlPaths", api.t("paths")),
                  api.spacer("6dp"),
                  api.tonalBtn("ctrlGc", api.t("gc")),
                },
                {
                  J.TextView,
                  id = "ctrlToolsLabel",
                  text = api.t("tools"),
                  textSize = "11sp",
                  textColor = c.onSurfaceVariant,
                  layout_marginTop = "10dp",
                  layout_marginBottom = "4dp",
                },
                {
                  J.LinearLayout,
                  layout_width = "match",
                  layout_height = "wrap",
                  api.tonalBtn("ctrlPause", api.t("pause_log")),
                  api.spacer("6dp"),
                  api.tonalBtn("ctrlScreen", api.t("screen_on")),
                },
                {
                  J.LinearLayout,
                  layout_width = "match",
                  layout_height = "wrap",
                  layout_marginTop = "6dp",
                  api.tonalBtn("ctrlHide", api.t("hide_bubble")),
                  api.spacer("6dp"),
                  api.tonalBtn("ctrlHist", api.t("eval_hist")),
                },
                {
                  J.TextView,
                  id = "ctrlEvalLabel",
                  text = api.t("eval_hint"),
                  textSize = "11sp",
                  textColor = c.onSurfaceVariant,
                  layout_marginTop = "10dp",
                },
              },
            },
            api.hairline(),
            {
              J.LinearLayout,
              orientation = "horizontal",
              layout_width = "match",
              layout_height = "40dp",
              gravity = "center_vertical",
              paddingLeft = "8dp",
              paddingRight = "6dp",
              layout_margin = "8dp",
              focusable = true,
              focusableInTouchMode = true,
              {
                J.EditText,
                id = "ctrlCode",
                layout_width = "0dp",
                layout_weight = 1,
                layout_height = "match",
                textSize = "12sp",
                textColor = c.onSurface,
                hint = api.t("code_hint"),
                BackgroundColor = 0,
                paddingLeft = "8dp",
                paddingRight = "6dp",
                paddingTop = "0dp",
                paddingBottom = "0dp",
              },
              {
                J.Button,
                id = "ctrlRun",
                text = api.t("run"),
                layout_width = "wrap",
                layout_height = "32dp",
                minHeight = "32dp",
                minWidth = "0dp",
                textSize = "12sp",
                paddingLeft = "12dp",
                paddingRight = "12dp",
                BackgroundColor = c.primary,
                textColor = c.onPrimary,
              },
            },
          },
          -- Views 树页
          {
            J.LinearLayout,
            orientation = "vertical",
            layout_width = "match",
            layout_height = "match",
            {
              J.TextView,
              id = "viewTreeMeta",
              layout_width = "match",
              layout_height = "wrap",
              textSize = "11sp",
              textColor = c.onSurfaceVariant,
              paddingLeft = "12dp",
              paddingRight = "12dp",
              paddingTop = "6dp",
              paddingBottom = "2dp",
              text = api.t("views_meta"),
            },
            {
              J.ListView,
              id = "viewTreeList",
              layout_width = "match",
              layout_height = "0dp",
              layout_weight = 1,
              DividerHeight = 0,
              FastScrollEnabled = true,
              overScrollMode = 2,
            },
          },
        },
        {
          api.t("tab_prints"),
          api.t("tab_vars"),
          api.t("tab_logcat"),
          api.t("tab_text"),
          api.t("tab_control"),
          api.t("tab_views"),
        },
      },
    },
    {
      J.LinearLayout,
      id = "actionBar",
      orientation = "horizontal",
      layout_width = "match",
      layout_height = "44dp",
      gravity = "center_vertical",
      paddingLeft = "6dp",
      paddingRight = "6dp",
      paddingTop = "4dp",
      paddingBottom = "4dp",
      BackgroundColor = c.surfaceContainerLow,
    },
  }, ui)
end

function api.preferredSheetSize()
  local sw, sh = api.screenSize()
  local w = math.min(math.floor(sw - api.dp(20)), math.floor(sw * 0.94))
  local h = math.min(math.floor(sh * 0.62), math.max(api.dp(340), math.floor(sh * 0.56)))
  return w, h
end

-- J.AppCompatDialog 直接 setContentView，无 AlertDialog contentPanel 留白
function api.applySheetLayout(content, dialog)
  local dw, dh = api.preferredSheetSize()
  local MATCH = -1
  content.setMinimumHeight(dh)
  local lp = content.getLayoutParams()
  if lp then
    lp.width = MATCH
    lp.height = dh
    content.setLayoutParams(lp)
  else
    content.setLayoutParams(J.FrameLayout.LayoutParams(MATCH, dh))
  end
  if not dialog then return end
  local win = dialog.getWindow()
  if win then
    win.setBackgroundDrawable(J.ColorDrawable(0))
    win.getDecorView().setPadding(0, 0, 0, 0)
    if win.setDimAmount then win.setDimAmount(0.45) end
    local attrs = win.getAttributes()
    attrs.width = dw
    attrs.height = dh
    attrs.gravity = J.Gravity.CENTER
    win.setAttributes(attrs)
    if win.setLayout then win.setLayout(dw, dh) end
  end
  content.requestLayout()
end

function api.highlightQuery(text, query)
  text = tostring(text or "")
  query = tostring(query or "")
  if query == "" then return text end
  api.resolveTheme()
  -- Spannable 下标是 UTF-16；用 Java String 搜索避免中文/emoji 错位
  local jText = luajava.newInstance("java.lang.String", text)
  local jQ = luajava.newInstance("java.lang.String", query)
  local lower = jText.toLowerCase()
  local q = jQ.toLowerCase()
  local start = lower.indexOf(q)
  if start < 0 then return text end
  local span = J.SpannableStringBuilder(text)
  local bg = J.BackgroundColorSpan(c.secondaryContainer)
  local fg = J.ForegroundColorSpan(c.onSecondaryContainer)
  local qLen = q.length()
  while start >= 0 do
    local stop = start + qLen
    if stop > start then
      span.setSpan(bg, start, stop, S.spanFlags)
      span.setSpan(fg, start, stop, S.spanFlags)
    end
    start = lower.indexOf(q, stop)
  end
  return span
end

function api.entryMatches(entry)
  if S.printFilter ~= "all" and entry.level ~= S.printFilter then
    return false
  end
  if S.printQuery ~= "" then
    local q = S.printQuery:lower()
    local hay = tostring(entry.full or ""):lower()
    if not hay:find(q, 1, true) then return false end
  end
  return true
end

function api.updatePrintMeta()
  if not ui.printMeta then return end
  local n = #S.printData
  local total = #S.printStore
  local label
  if S.printFilter == "all" and S.printQuery == "" then
    label = api.tf("entries", total)
  else
    local q = S.printQuery ~= "" and (" · \"" .. S.printQuery .. "\"") or ""
    label = api.tf("filtered_meta", n, total, S.printFilter, q)
  end
  ui.printMeta.setText(label)
  if ui.headerSub then
    ui.headerSub.setText(api.tf("logs_meta", total, S.printFilter))
  end
end

function api.setPrintEmptyVisible(show)
  if ui.printEmpty then
    ui.printEmpty.setVisibility(show and J.View.VISIBLE or J.View.GONE)
  end
  if ui.printList then
    ui.printList.setVisibility(show and J.View.GONE or J.View.VISIBLE)
  end
end

function api.rebuildPrintList()
  table.clear(S.printData)
  table.clear(S.printFull)
  for _, entry in ipairs(S.printStore) do
    if api.entryMatches(entry) then
      local shown = entry.shown
      if S.printQuery ~= "" then
        shown = api.highlightQuery(entry.shown, S.printQuery)
      end
      S.printData[#S.printData + 1] = {
        txt = {
          text = shown,
          textColor = entry.color or c.onSurface,
        },
      }
      S.printFull[#S.printData] = entry.full
    end
  end
  if S.printAdp then S.printAdp.notifyDataSetChanged() end
  api.setPrintEmptyVisible(#S.printData == 0)
  api.updatePrintMeta()
end

function api.pushStore(entry)
  S.printStore[#S.printStore + 1] = entry
  while #S.printStore > S.MAX_PRINT do
    table.remove(S.printStore, 1)
  end
  if api.entryMatches(entry) then
    local shown = entry.shown
    if S.printQuery ~= "" then
      shown = api.highlightQuery(entry.shown, S.printQuery)
    end
    local row = {
      txt = {
        text = shown,
        textColor = entry.color or c.onSurface,
      },
    }
    if S.printAdp then
      S.printAdp.add(row)
    else
      S.printData[#S.printData + 1] = row
    end
    S.printFull[#S.printData] = entry.full
    api.setPrintEmptyVisible(false)
  end
  api.updatePrintMeta()
end

function api.appendPrintEntry(full, level, color, withTime)
  if S.loggingPaused and level ~= "error" then return end
  level = level or api.levelForMessage(full)
  color = color or api.colorForLevel(level)
  local ts = ""
  pcall(function() ts = S.dateFmt.format(J.System.currentTimeMillis()) end)
  local shown
  if withTime then
    shown = (ts ~= "" and (ts .. " ") or "") .. api.truncate(full, 100)
  else
    shown = api.truncate(full, 120)
  end
  if level == "error" or level == "warn" then
    api.setBubbleError(true)
  end
  api.pushStore {
    full = full,
    shown = shown,
    color = color,
    level = level,
    ts = ts,
  }
end

function api.copyFilteredPrints()
  local lines = {}
  for _, entry in ipairs(S.printStore) do
    if api.entryMatches(entry) then
      lines[#lines + 1] = entry.full or ""
    end
  end
  if #lines == 0 then api.toast(api.t("nothing_copy")); return end
  api.clipboardSet(table.concat(lines, "\n"))
  api.toast(api.tf("copied_n", #lines))
end

function api.scrollPrintToBottom()
  if not ui.printList or not S.printAdp then return end
  local n = S.printAdp.getCount()
  if n > 0 then ui.printList.setSelection(n - 1) end
end

function api.pushEvalHistory(src)
  src = tostring(src or ""):match("^%s*(.-)%s*$") or ""
  if src == "" then return end
  for i = #S.evalHistory, 1, -1 do
    if S.evalHistory[i] == src then table.remove(S.evalHistory, i) end
  end
  S.evalHistory[#S.evalHistory + 1] = src
  while #S.evalHistory > S.MAX_EVAL_HISTORY do table.remove(S.evalHistory, 1) end
end

function api.runtimeMemText()
  local lines = {}
  local rt = J.Runtime.getRuntime()
  local used = (rt.totalMemory() - rt.freeMemory()) / (1024 * 1024)
  local total = rt.totalMemory() / (1024 * 1024)
  local max = rt.maxMemory() / (1024 * 1024)
  lines[#lines + 1] = string.format("Java heap: %.1f / %.1f MB (max %.1f)", used, total, max)
  lines[#lines + 1] = string.format("Lua GC: %.1f KB", collectgarbage("count"))
  local am = activity.getSystemService(J.Context.ACTIVITY_SERVICE)
  local mi = luajava.newInstance("android.app.ActivityManager$MemoryInfo")
  am.getMemoryInfo(mi)
  lines[#lines + 1] = string.format(
    "System avail: %.0f MB%s",
    mi.availMem / (1024 * 1024),
    mi.lowMemory and " · LOW" or "")
  return table.concat(lines, "\n")
end

function api.deviceInfoText()
  local lines = {
    "=== Device / Runtime ===",
    "Model: " .. tostring(J.Build.MODEL),
    "Device: " .. tostring(J.Build.DEVICE),
    "Brand: " .. tostring(J.Build.BRAND),
    "Android: " .. tostring(J.Build.VERSION.RELEASE)
      .. " (SDK " .. tostring(J.Build.VERSION.SDK_INT or J.Build.VERSION.SDK) .. ")",
    "ABI: " .. tostring(J.Build.SUPPORTED_ABIS
      and tostring(J.Build.SUPPORTED_ABIS[0]) or J.Build.CPU_ABI),
  }
  local pkg = activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0)
  local vc = pkg.versionCode
  if pkg.getLongVersionCode then vc = pkg.getLongVersionCode() end
  lines[#lines + 1] = "Package: " .. tostring(pkg.packageName)
  lines[#lines + 1] = "Version: " .. tostring(pkg.versionName) .. " (" .. tostring(vc) .. ")"
  S.dm = activity.getResources().getDisplayMetrics()
  lines[#lines + 1] = string.format(
    "Display: %dx%d · density %.2f · %.0fdpi",
    S.dm.widthPixels, S.dm.heightPixels, S.dm.density, S.dm.densityDpi)
  local conf = activity.getResources().getConfiguration()
  local locale = conf.locale
  if not locale and conf.getLocales then locale = conf.getLocales().get(0) end
  lines[#lines + 1] = "Locale: " .. tostring(locale)
  lines[#lines + 1] = "Orientation: " .. (conf.orientation == 2 and "landscape" or "portrait")
  if this.getLuaPath then lines[#lines + 1] = "Lua path: " .. tostring(this.getLuaPath()) end
  if this.getLuaDir then lines[#lines + 1] = "Lua dir: " .. tostring(this.getLuaDir()) end
  lines[#lines + 1] = "Files: " .. activity.getFilesDir().getAbsolutePath()
  lines[#lines + 1] = "Cache: " .. activity.getCacheDir().getAbsolutePath()
  local ext = activity.getExternalFilesDir(nil)
  if ext then lines[#lines + 1] = "Ext files: " .. ext.getAbsolutePath() end
  if this.getMediaDir then
    lines[#lines + 1] = "Media: " .. this.getMediaDir().getAbsolutePath()
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = api.runtimeMemText()
  if S.lastCrashPath then
    lines[#lines + 1] = "Last crash: " .. tostring(S.lastCrashPath)
  end
  return table.concat(lines, "\n")
end

function api.intentExtrasText()
  local lines = { "=== Intent ===" }
  local intent = activity.getIntent()
  lines[#lines + 1] = "Action: " .. tostring(intent.getAction())
  lines[#lines + 1] = "Data: " .. tostring(intent.getDataString())
  lines[#lines + 1] = "Type: " .. tostring(intent.getType())
  lines[#lines + 1] = "Flags: 0x" .. string.format("%x", intent.getFlags())
  local extras = intent.getExtras()
  if extras then
    local keys = extras.keySet().toArray()
    local n = keys.length
    lines[#lines + 1] = "Extras (" .. n .. "):"
    for i = 0, math.min(n - 1, 80) do
      local k = tostring(keys[i])
      local v = extras.get(k)
      lines[#lines + 1] = "  " .. k .. " = " .. api.truncate(tostring(v), 120)
    end
  else
    lines[#lines + 1] = "Extras: (none)"
  end
  return table.concat(lines, "\n")
end

-- ─── 视图树（可展开） ───────────────────────────────────
function api.viewIdName(v)
  local id = v.getId()
  if not id or id <= 0 then return "" end
  local okn, name = pcall(function()
    return activity.getResources().getResourceEntryName(id)
  end)
  if okn and name then return "@" .. name end
  return string.format("#0x%x", id)
end

function api.viewBriefExtra(v)
  local extra = ""
  if v.getText then
    local ok, t = pcall(function() return tostring(v.getText() or "") end)
    if ok and t ~= "" then
      return '"' .. api.truncate(t:gsub("%s+", " "), 28) .. '"'
    end
  end
  if v.getContentDescription then
    local ok, d = pcall(function() return v.getContentDescription() end)
    if ok and d then
      local s = tostring(d)
      if s ~= "" then return "desc=" .. api.truncate(s, 24) end
    end
  end
  return extra
end

function api.viewNodeFrom(v, depth)
  local childN = 0
  if v.getChildCount then childN = v.getChildCount() or 0 end
  return {
    view = v,
    depth = depth or 0,
    expanded = false,
    children = nil, -- 懒加载
    childCount = childN,
    className = v.getClass().getSimpleName(),
    idName = api.viewIdName(v),
  }
end

function api.viewNodeLoadChildren(node)
  if node.children then return end
  node.children = {}
  local v = node.view
  if not v or not v.getChildCount then return end
  local n = v.getChildCount() or 0
  local lim = math.min(n, 80)
  for i = 0, lim - 1 do
    local child = v.getChildAt(i)
    if child then
      if S.viewOnlyVisible and child.getVisibility() ~= J.View.VISIBLE then
        -- skip GONE / INVISIBLE
      else
        node.children[#node.children + 1] = api.viewNodeFrom(child, node.depth + 1)
      end
    end
  end
  if n > lim then
    node.children[#node.children + 1] = {
      view = nil,
      depth = node.depth + 1,
      expanded = false,
      children = {},
      childCount = 0,
      className = "… +" .. (n - lim) .. " more",
      idName = "",
      stub = true,
    }
  end
end

function api.viewTreeFlatten(node, out)
  out = out or {}
  out[#out + 1] = node
  if node.expanded and node.childCount > 0 then
    api.viewNodeLoadChildren(node)
    for _, ch in ipairs(node.children or {}) do
      api.viewTreeFlatten(ch, out)
    end
  end
  return out
end

function api.viewTreeRowLabel(node)
  if node.stub then return string.rep("  ", node.depth) .. node.className end
  local mark = "  "
  if node.childCount > 0 then
    mark = node.expanded and "▾ " or "▸ "
  end
  local pad = string.rep("  ", node.depth)
  local id = node.idName ~= "" and (" " .. node.idName) or ""
  local wh, flags, extra = "", "", ""
  local v = node.view
  if v then
    local okW, dims = pcall(function()
      return string.format(" %dx%d", v.getWidth(), v.getHeight())
    end)
    if okW then wh = dims end
    local okF, f = pcall(function()
      local parts = {}
      local vv = v.getVisibility()
      if vv == J.View.GONE then parts[#parts + 1] = "G"
      elseif vv == J.View.INVISIBLE then parts[#parts + 1] = "I" end
      if v.isClickable() then parts[#parts + 1] = "c" end
      if #parts > 0 then return " [" .. table.concat(parts, "") .. "]" end
      return ""
    end)
    if okF then flags = f end
    local e = api.viewBriefExtra(v)
    if e ~= "" then extra = " " .. e end
  end
  local kids = node.childCount > 0 and string.format(" {%d}", node.childCount) or ""
  return pad .. mark .. node.className .. id .. wh .. kids .. flags .. extra
end

function api.viewNodeDetail(node)
  if not node or node.stub or not node.view then return api.t("views_empty") end
  local v = node.view
  local lines = { "=== " .. api.t("views_detail") .. " ===" }
  lines[#lines + 1] = "Class: " .. tostring(v.getClass().getName())
  lines[#lines + 1] = "Simple: " .. node.className
  local idn = node.idName
  if idn == "" then idn = "(none)" end
  lines[#lines + 1] = "Id: " .. idn
  lines[#lines + 1] = string.format("Size: %dx%d", v.getWidth(), v.getHeight())
  pcall(function()
    lines[#lines + 1] = string.format(
      "Location: (%d,%d)", v.getLeft(), v.getTop())
  end)
  local vv = v.getVisibility()
  local vis = "VISIBLE"
  if vv == J.View.GONE then vis = "GONE"
  elseif vv == J.View.INVISIBLE then vis = "INVISIBLE" end
  lines[#lines + 1] = "Visibility: " .. vis
  lines[#lines + 1] = "Enabled: " .. tostring(v.isEnabled())
  lines[#lines + 1] = "Clickable: " .. tostring(v.isClickable())
  lines[#lines + 1] = "Focusable: " .. tostring(v.isFocusable())
  lines[#lines + 1] = string.format("Alpha: %.2f", v.getAlpha() or 1)
  pcall(function()
    lines[#lines + 1] = string.format(
      "Padding: L%d T%d R%d B%d",
      v.getPaddingLeft(), v.getPaddingTop(),
      v.getPaddingRight(), v.getPaddingBottom())
  end)
  if v.getText then
    local ok, t = pcall(function() return tostring(v.getText() or "") end)
    if ok and t ~= "" then lines[#lines + 1] = "Text: " .. t end
  end
  if v.getContentDescription then
    local ok, d = pcall(function() return v.getContentDescription() end)
    if ok and d then lines[#lines + 1] = "Desc: " .. tostring(d) end
  end
  lines[#lines + 1] = "Children: " .. tostring(node.childCount)
  return table.concat(lines, "\n")
end

function api.viewTreeRebuildFlat()
  table.clear(S.viewTreeFlat)
  table.clear(S.viewTreeData)
  if S.viewTreeRoot then
    api.viewTreeFlatten(S.viewTreeRoot, S.viewTreeFlat)
  end
  for _, node in ipairs(S.viewTreeFlat) do
    S.viewTreeData[#S.viewTreeData + 1] = {
      line = {
        text = api.viewTreeRowLabel(node),
        textColor = c.onSurface,
      },
    }
  end
  if ui.viewTreeMeta then
    ui.viewTreeMeta.setText(api.tf("views_meta", #S.viewTreeFlat))
  end
  if S.viewTreeAdp then S.viewTreeAdp.notifyDataSetChanged() end
end

function api.viewTreeRefresh()
  local root = activity.getWindow().getDecorView()
  S.viewTreeRoot = api.viewNodeFrom(root, 0)
  S.viewTreeRoot.expanded = true
  api.viewNodeLoadChildren(S.viewTreeRoot)
  -- 默认展开一层 content
  for _, ch in ipairs(S.viewTreeRoot.children or {}) do
    if ch.childCount > 0 and ch.depth < 2 then
      ch.expanded = true
    end
  end
  api.viewTreeRebuildFlat()
end

function api.viewTreeCollapseAll()
  local function collapse(node)
    if not node then return end
    node.expanded = false
    if node.children then
      for _, ch in ipairs(node.children) do collapse(ch) end
    end
  end
  if S.viewTreeRoot then
    collapse(S.viewTreeRoot)
    S.viewTreeRoot.expanded = true
  end
  api.viewTreeRebuildFlat()
end

function api.ensureViewTreeAdp()
  if S.viewTreeAdp or not ui.viewTreeList then return end
  S.viewTreeAdp = J.LuaAdapter(activity, S.viewTreeData, {
    J.TextView,
    layout_width = "match",
    textSize = "11sp",
    paddingLeft = "8dp",
    paddingRight = "8dp",
    paddingTop = "6dp",
    paddingBottom = "6dp",
    singleLine = true,
    ellipsize = "middle",
    id = "line",
  })
  ui.viewTreeList.setAdapter(S.viewTreeAdp)
  ui.viewTreeList.onItemClick = function(_, v, _, d)
    api.vibrate(v)
    local node = S.viewTreeFlat[d]
    if not node or node.stub then return end
    if node.childCount > 0 then
      node.expanded = not node.expanded
      if node.expanded then api.viewNodeLoadChildren(node) end
      api.viewTreeRebuildFlat()
    else
      api.openTextInPanel(api.t("views_detail"), api.viewNodeDetail(node))
    end
  end
  ui.viewTreeList.onItemLongClick = function(_, v, _, d)
    api.vibrate(v)
    local node = S.viewTreeFlat[d]
    if not node then return true end
    api.openTextInPanel(api.t("views_detail"), api.viewNodeDetail(node))
    return true
  end
end

function api.dumpViewTree(root, maxDepth)
  -- 纯文本导出（仍给 Control 长备份 / 兼容）
  maxDepth = maxDepth or 8
  local MAX_LINES = 600
  local lines = { "=== View hierarchy ===" }
  local function walk(v, depth)
    if not v or depth > maxDepth or #lines >= MAX_LINES then return end
    local node = api.viewNodeFrom(v, depth)
    lines[#lines + 1] = api.viewTreeRowLabel(node):gsub("▾ ", "  "):gsub("▸ ", "  ")
    local n = node.childCount
    if n > 0 and depth < maxDepth then
      local lim = math.min(n, 64)
      for i = 0, lim - 1 do
        local child = v.getChildAt(i)
        if child then
          if S.viewOnlyVisible and child.getVisibility() ~= J.View.VISIBLE then
            -- skip
          else
            walk(child, depth + 1)
          end
        end
        if #lines >= MAX_LINES then break end
      end
    end
  end
  root = root or activity.getWindow().getDecorView()
  walk(root, 0)
  if #lines >= MAX_LINES then
    lines[#lines + 1] = "… truncated at " .. MAX_LINES .. " lines"
  end
  return table.concat(lines, "\n")
end

function api.openTextInPanel(title, body)
  if ui.textEdit then
    ui.textEdit.setText(tostring(body or ""))
    if ui.page then ui.page.setCurrentItem(3, false) end
    if ui.headerSub then ui.headerSub.setText(tostring(title or "Text")) end
  else
    api.clipboardSet(body)
    api.toast(api.t("copied_panel"))
  end
end

function api.runGcAndReport()
  local before = api.runtimeMemText()
  collectgarbage("collect")
  J.Runtime.getRuntime().gc()
  local after = api.runtimeMemText()
  local msg = "GC done\n-- before --\n" .. before .. "\n-- after --\n" .. after
  info("GC done")
  api.openTextInPanel(api.t("mem_gc"), msg)
end

function api.toggleKeepScreenOn()
  S.keepScreenOn = not S.keepScreenOn
  local w = activity.getWindow()
  local f = bindClass "android.view.WindowManager$LayoutParams".FLAG_KEEP_SCREEN_ON
  if S.keepScreenOn then
    w.addFlags(f)
  else
    w.clearFlags(f)
  end
  api.toast(S.keepScreenOn and api.t("keep_screen_on") or api.t("keep_screen_off"))
  info("keepScreenOn=" .. tostring(S.keepScreenOn))
  if ui.ctrlScreen then
    ui.ctrlScreen.setText(S.keepScreenOn and api.t("screen_off") or api.t("screen_on"))
  end
end

function api.toggleLoggingPause()
  S.loggingPaused = not S.loggingPaused
  api.toast(S.loggingPaused and api.t("logging_paused") or api.t("logging_resumed"))
  info(S.loggingPaused and "logging paused" or "logging resumed")
  if ui.ctrlPause then
    ui.ctrlPause.setText(S.loggingPaused and api.t("resume_log") or api.t("pause_log"))
  end
end

function api.hideBubbleTemporarily()
  api.removeBubble()
  api.toast(api.t("bubble_hidden"))
end

function api.clearPrints()
  table.clear(S.printStore)
  table.clear(S.printData)
  table.clear(S.printFull)
  if S.printAdp then S.printAdp.clear() end
  api.setPrintEmptyVisible(true)
  api.setBubbleError(false)
  api.updatePrintMeta()
end

function log(color, withTime, ...)
  if not api.activityAlive() then return ... end
  local parts = {}
  local args = { ... }
  for i = 1, #args do
    parts[#parts + 1] = tostring(args[i])
    if i < #args then parts[#parts + 1] = "  " end
  end
  local full = table.concat(parts)
  local level = "log"
  if color == c.error then
    level = "error"
  elseif color == c.warning then
    level = "warn"
  elseif color == c.success then
    level = "info"
  elseif color == c.muted then
    level = "log"
  else
    level = api.levelForMessage(full)
  end
  api.appendPrintEntry(full, level, color or api.colorForLevel(level), withTime and true or false)
  return ...
end

-- 同步宿主 LuaActivity.logs
function api.pullHostLogs()
  local logs = J.LuaActivityClass.logs
  if not logs then return end
  local size = logs.size()
  if size <= S.hostLogsCursor then return end
  for i = S.hostLogsCursor, size - 1 do
    local msg = logs.get(i)
    if msg then
      local s = tostring(msg)
      local last = S.printStore[#S.printStore]
      if not last or last.full ~= s then
        api.appendPrintEntry(s, api.levelForMessage(s), nil, false)
      end
    end
  end
  S.hostLogsCursor = size
end

function print(...)
  local parts = {}
  local args = { ... }
  for i = 1, #args do
    parts[#parts + 1] = tostring(args[i])
    if i < #args then parts[#parts + 1] = "    " end
  end
  local msg = table.concat(parts)
  api.appendPrintEntry(msg, "log", c.primary, true)
  S.suppressHostMirror = true
  S.hostLogsCursor = S.hostLogsCursor + 1
  pcall(function() activity.sendMsg(msg) end)
  S.suppressHostMirror = false
  return ...
end

-- printf：格式化后走 print 通路（面板 + sendMsg）
function printf(fmt, ...)
  local ok, formatted = pcall(string.format, fmt, ...)
  if ok then
    print(formatted)
  else
    print(fmt, ...)
  end
end

function safe_error(...)
  local parts = {}
  local args = { ... }
  for i = 1, #args do
    parts[#parts + 1] = tostring(args[i])
    if i < #args then parts[#parts + 1] = "  " end
  end
  local full = table.concat(parts)
  api.appendPrintEntry(full, "error", c.error, true)
  api.sendHostMsg(full)
  return ...
end

function explain(...)
  local parts = {}
  local args = { ... }
  for i = 1, #args do parts[i] = tostring(args[i]) end
  api.appendPrintEntry(table.concat(parts, "  "), "log", c.muted, true)
  return ...
end

function info(...)
  local parts = {}
  local args = { ... }
  for i = 1, #args do parts[i] = tostring(args[i]) end
  api.appendPrintEntry(table.concat(parts, "  "), "info", c.success, true)
  return ...
end

function warning(...)
  local parts = {}
  local args = { ... }
  for i = 1, #args do parts[i] = tostring(args[i]) end
  api.appendPrintEntry(table.concat(parts, "  "), "warn", c.warning, true)
  return ...
end

function error(a, b)
  api.appendPrintEntry(tostring(a), "error", c.error, true)
  return S.hostError(a, b)
end

function assert(a, ...)
  if not a then
    local parts = {}
    local args = { ... }
    for i = 1, #args do parts[i] = tostring(args[i]) end
    api.appendPrintEntry(table.concat(parts, "  "), "error", c.error, true)
  end
  return S.hostAssert(a, ...)
end

function api.crashDir()
  local dir
  pcall(function()
    dir = this.getMediaDir().getAbsolutePath() .. "/crash"
  end)
  if not dir then
    pcall(function()
      dir = activity.getExternalFilesDir(nil).getAbsolutePath() .. "/crash"
    end)
  end
  if not dir then
    dir = activity.getFilesDir().getAbsolutePath() .. "/crash"
  end
  pcall(function() J.File(dir).mkdirs() end)
  return dir
end

function api.writeTextFileJava(path, text)
  local ok = pcall(function()
    local jstr = luajava.newInstance("java.lang.String", tostring(text or ""))
    local bytes = jstr.getBytes("UTF-8")
    local fos = J.FileOutputStream(path)
    fos.write(bytes)
    fos.close()
  end)
  if ok then return true end
  local f = io.open(path, "w")
  if not f then return false end
  f:write(tostring(text or ""))
  f:close()
  return true
end

function api.buildExportText(limit)
  local lines = {}
  lines[#lines + 1] = api.t("export_banner")
  pcall(function()
    lines[#lines + 1] = "file: " .. tostring(this.getLuaPath())
    lines[#lines + 1] = "time: " .. tostring(S.fileStampFmt.format(J.System.currentTimeMillis()))
  end)
  lines[#lines + 1] = ""
  local start = 1
  if limit and #S.printStore > limit then
    start = #S.printStore - limit + 1
  end
  for i = start, #S.printStore do
    local e = S.printStore[i]
    lines[#lines + 1] = string.format("[%s] %s", e.level or "log", e.full or "")
  end
  return table.concat(lines, "\n")
end

function api.exportPrints(share)
  api.pullHostLogs()
  local body = api.buildExportText()
  local stamp = "export"
  pcall(function() stamp = S.fileStampFmt.format(J.System.currentTimeMillis()) end)
  local path = api.crashDir() .. "/vconsole_" .. stamp .. ".txt"
  if not api.writeTextFileJava(path, body) then
    api.toast(api.t("export_failed"))
    return nil
  end
  S.lastCrashPath = path
  api.toast(api.tf("saved", path))
  info("exported → " .. path)
  if share then
    pcall(function()
      local intent = J.Intent(J.Intent.ACTION_SEND)
      intent.setType("text/plain")
      intent.putExtra(J.Intent.EXTRA_TEXT, body)
      intent.putExtra(J.Intent.EXTRA_SUBJECT, "vConsole export")
      activity.startActivity(J.Intent.createChooser(intent, api.t("share_logs")))
    end)
  end
  return path
end

function api.snapshotCrash(title, exception, msg)
  local stamp = "crash"
  pcall(function() stamp = S.fileStampFmt.format(J.System.currentTimeMillis()) end)
  local path = api.crashDir() .. "/vconsole_crash_" .. stamp .. ".txt"
  local lines = {
    "=== vConsole crash snapshot ===",
    "title: " .. tostring(title),
    "message: " .. tostring(msg),
  }
  pcall(function()
    lines[#lines + 1] = "file: " .. tostring(this.getLuaPath())
    lines[#lines + 1] = "model: " .. tostring(J.Build.MODEL)
    lines[#lines + 1] = "sdk: " .. tostring(J.Build.VERSION.SDK_INT or J.Build.VERSION.SDK)
  end)
  if exception then
    pcall(function()
      if exception.stackTraceToString then
        lines[#lines + 1] = "stack:\n" .. tostring(exception.stackTraceToString())
      elseif exception.getStackTrace then
        local st = exception.getStackTrace()
        local n = st.length
        local buf = {}
        for i = 0, math.min(n - 1, 40) do
          buf[#buf + 1] = tostring(st[i])
        end
        lines[#lines + 1] = "stack:\n" .. table.concat(buf, "\n")
      end
    end)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "--- recent prints ---"
  local start = math.max(1, #S.printStore - 80)
  for i = start, #S.printStore do
    local e = S.printStore[i]
    lines[#lines + 1] = string.format("[%s] %s", e.level or "log", e.full or "")
  end
  if api.writeTextFileJava(path, table.concat(lines, "\n")) then
    S.lastCrashPath = path
    api.appendPrintEntry("crash saved → " .. path, "info", c.success, true)
  end
  return path
end

-- LuaActivity.sendError → runFunc("onError", title, exception)
S.prevOnError = rawget(_G, "onError")
function onError(title, exception)
  local msg
  pcall(function()
    if exception and exception.getMessage then
      msg = tostring(title) .. ": " .. tostring(exception.getMessage())
    else
      msg = tostring(title) .. ": " .. tostring(exception)
    end
  end)
  msg = msg or (tostring(title) .. ": " .. tostring(exception))
  api.appendPrintEntry(msg, "error", c.error, true)
  pcall(function() api.snapshotCrash(title, exception, msg) end)
  if type(S.prevOnError) == "function" then
    local ok, ret = pcall(S.prevOnError, title, exception)
    if ok and ret ~= nil then return ret end
  end
  return "log"
end

-- ─── Vars ───────────────────────────────────────────────
-- Span 须在主题色就绪后创建（int 构造，nil 会落到 Parcel 构造失败）
function api.isVConsoleGlobalKey(k)
  if type(k) ~= "string" then return false end
  if S.VC_HIDDEN_GLOBALS[k] then return true end
  if k:find("^__vConsole", 1) then return true end
  return false
end

function api.ensureVarSpans()
  if S.colorKey then return end
  api.resolveTheme()
  S.colorKey = J.ForegroundColorSpan(c.primary)
  S.colorArrow = J.ForegroundColorSpan(c.success)
  S.colorTable = J.ForegroundColorSpan(c.warning)
end

function api.varAdd(meta, str)
  S.variableData[#S.variableData + 1] = {
    kv = { text = str, textColor = c.muted },
  }
  S.variableKv[#S.variableData] = meta
end

function api.refreshVars()
  if not ui.varList then return end
  api.ensureVarSpans()
  local tab = _ENV
  table.clear(S.variablePath)
  table.clear(S.variableData)

  for i, key in ipairs(S.variableNode) do
    if type(tab[key]) == "table" then
      tab = tab[key]
    else
      S.variableNode[i] = nil
    end
  end

  local pathParts = {}
  for i, key in ipairs(S.variableNode) do
    pathParts[i] = tostring(key)
  end
  local pathStr = table.concat(pathParts, "/")
  if #pathStr > 0 then pathStr = pathStr .. "/" end
  local q = S.varQuery or ""
  if q ~= "" then
    ui.varPath.setText("node: /" .. pathStr .. "  ⌕" .. q)
  else
    ui.varPath.setText("node: /" .. pathStr)
  end

  if #S.variableNode > 0 then api.varAdd(1, "← parent") end
  api.varAdd(2, "serialize node")

  local qLower = q:lower()
  -- 根环境跳过 vConsole 自身注入的全局，避免污染 Vars
  local atRoot = (#S.variableNode == 0)
  for k, v in pairs(tab) do
    if atRoot and api.isVConsoleGlobalKey(k) then
      -- skip
    else
      local rawK, rawV = k, v
      local ks = type(k) == "string" and tostring(k) or string.format("[%s]", tostring(k))
      -- 筛选：匹配键名（忽略大小写）
      if qLower ~= "" and not ks:lower():find(qLower, 1, true) then
        -- skip
      else
        local vs = tostring(v)
        if vs then
          vs = api.truncate(vs, 80)
          if type(rawV) == "string" then
            vs = string.format('"%s"', vs)
          elseif type(rawV) == "table" then
            vs = string.format("%s => {...}", vs)
            S.variablePath[tostring(rawK)] = rawK
          end
          local line = string.format("%s => %s", ks, vs)
          local span = S.variableSpanCache[#S.variableData + 1]
          if not span then
            span = J.SpannableStringBuilder()
            S.variableSpanCache[#S.variableData + 1] = span
          end
          span.clearSpans()
          span.clear()
          span.append(line)
          local s1, e1 = utf8.find(line, "=>")
          if s1 then
            span.setSpan(S.colorKey, 0, utf8.len(ks), S.spanFlags)
            span.setSpan(S.colorArrow, s1 - 1, e1, S.spanFlags)
            if type(rawV) == "table" then
              local s2, e2 = utf8.find(line, "{%.%.%.}", e1)
              if s2 then span.setSpan(S.colorTable, s2 - 1, e2, S.spanFlags) end
            end
          end
          api.varAdd({ rawK, rawV }, span)
        end
      end
    end
  end
  if S.variableAdp then S.variableAdp.notifyDataSetChanged() end
end

function api.ensurePrintAdp()
  if S.printAdp or not ui.printList then return end
  S.printAdp = J.LuaAdapter(activity, S.printData, {
    J.TextView,
    layout_width = "match",
    textSize = "12sp",
    paddingLeft = "12dp",
    paddingRight = "12dp",
    paddingTop = "8dp",
    paddingBottom = "8dp",
    id = "txt",
  })
  ui.printList.setAdapter(S.printAdp)
  ui.printList.onItemClick = function(_, v, _, d)
    api.vibrate(v)
    ui.textEdit.setText(S.printFull[d] or "")
    ui.page.setCurrentItem(3, false)
  end
  ui.printList.onItemLongClick = function(_, v, _, d)
    api.vibrate(v)
    local full = S.printFull[d] or ""
    api.clipboardSet(full)
    api.toast(api.t("copied_line"))
    return true
  end
end

function api.markFilterButtons(ids, activeKey, keyOf)
  api.resolveTheme()
  for _, item in ipairs(ids) do
    local btn = ui[item[1]]
    if btn then
      local on = keyOf(item) == activeKey
      api.compactButtonMetrics(btn, 32, 10)
      btn.setTextColor(on and c.primary or c.onSurfaceVariant)
      if on then
        api.applyRound(btn, c.secondaryContainer, 16)
      else
        btn.setBackgroundColor(0)
      end
    end
  end
end

function api.setupPrintFilters()
  for _, item in ipairs(S.printFilterIds) do
    local btn = ui[item[1]]
    if btn then
      btn.onClick = function(v)
        api.vibrate(v)
        S.printFilter = item[3]
        api.markFilterButtons(S.printFilterIds, S.printFilter, function(o) return o[3] end)
        api.rebuildPrintList()
      end
    end
  end
  api.markFilterButtons(S.printFilterIds, S.printFilter, function(o) return o[3] end)
  if ui.printSearch then
    local TextWatcher = bindClass "android.text.TextWatcher"
    ui.printSearch.addTextChangedListener(TextWatcher({
      beforeTextChanged = function() end,
      onTextChanged = function() end,
      afterTextChanged = function(s)
        S.printQuery = tostring(s or ""):match("^%s*(.-)%s*$") or ""
        if ui.printSearchClear then
          ui.printSearchClear.setVisibility(
            S.printQuery ~= "" and J.View.VISIBLE or J.View.GONE)
        end
        api.rebuildPrintList()
      end,
    }))
  end
  if ui.printSearchClear then
    ui.printSearchClear.onClick = function(v)
      api.vibrate(v)
      S.printQuery = ""
      if ui.printSearch then ui.printSearch.setText("") end
      api.rebuildPrintList()
    end
  end
end

function api.ensureVarAdp()
  if S.variableAdp or not ui.varList then return end
  S.variableAdp = J.LuaAdapter(activity, S.variableData, {
    J.TextView,
    layout_width = "match",
    textSize = "11sp",
    paddingLeft = "12dp",
    paddingRight = "12dp",
    paddingTop = "7dp",
    paddingBottom = "7dp",
    singleLine = true,
    ellipsize = "end",
    id = "kv",
  })
  ui.varList.setAdapter(S.variableAdp)
  ui.varList.onItemClick = function(_, v, _, d)
    api.vibrate(v)
    local t = S.variableKv[d]
    if t == 1 then
      S.variableNode[#S.variableNode] = nil
      api.refreshVars()
    elseif t == 2 then
      local tab = _ENV
      for _, key in ipairs(S.variableNode) do tab = tab[key] end
      ui.textEdit.setText(api.dumpValue(tab))
      ui.page.setCurrentItem(3, false)
    elseif type(t) == "table" then
      if type(t[2]) == "table" then
        S.variableNode[#S.variableNode + 1] = t[1]
        api.refreshVars()
      else
        ui.textEdit.setText(tostring(t[2]))
        ui.page.setCurrentItem(3, false)
      end
    end
  end
  ui.varList.onItemLongClick = function(_, v)
    local path = table.concat(S.variableNode, "/")
    local key = tostring(v.getText()):match("(.+)%s=>")
    if ui.textEdit then
      ui.textEdit.setText(string.format("%s/%s", path, key or ""))
    end
    if ui.page then ui.page.setCurrentItem(3, false) end
    return true
  end
  if ui.varSearch then
    local TextWatcher = bindClass "android.text.TextWatcher"
    ui.varSearch.addTextChangedListener(TextWatcher({
      beforeTextChanged = function() end,
      onTextChanged = function() end,
      afterTextChanged = function(s)
        S.varQuery = tostring(s or ""):match("^%s*(.-)%s*$") or ""
        api.refreshVars()
      end,
    }))
    -- 回车：精确匹配 table 则进入该节点；否则只收起键盘（筛选已实时生效）
    ui.varSearch.onEditorAction = function(v, actionId)
      local q = tostring(v.getText() or ""):match("^%s*(.-)%s*$") or ""
      local key = S.variablePath[q]
      if key == nil then
        local ql = q:lower()
        for name, k in pairs(S.variablePath) do
          if tostring(name):lower() == ql then
            key = k
            break
          end
        end
      end
      if key ~= nil then
        S.variableNode[#S.variableNode + 1] = key
        S.varQuery = ""
        v.setText("")
        api.refreshVars()
      end
      pcall(function()
        activity.getSystemService(J.Context.INPUT_METHOD_SERVICE)
          .hideSoftInputFromWindow(v.getWindowToken(), 0)
      end)
      return true
    end
  end
end

function api.logcatLevelColor(level)
  api.resolveTheme()
  local L = tostring(level or "?"):upper()
  if L == "E" or L == "F" or L == "A" then return c.error end
  if L == "W" then return c.warning end
  if L == "I" then return c.success end
  if L == "D" then return c.primary end
  if L == "V" then return c.onSurfaceVariant end
  return c.onSurfaceVariant
end

function api.logcatLevelFill(level)
  api.resolveTheme()
  local L = tostring(level or "?"):upper()
  if L == "E" or L == "F" or L == "A" then return c.errorContainer end
  if L == "W" then return c.surfaceContainerHigh end
  if L == "I" then return c.secondaryContainer end
  if L == "D" then return c.primaryContainer end
  return c.surfaceContainer
end

-- long: [ 07-23 12:34:56.789  1234: 5678 E/Tag ]
-- threadtime / brief 兜底
function api.parseLogcatBlock(block)
  block = tostring(block or "")
  local level, tag, body = "?", "", block
  local hdr, rest = block:match("^(%[[^\n]*%])%s*\n?(.*)$")
  if hdr then
    local lv, tg = hdr:match("%s([VDIWEFA])/([^%]%s]+)")
    if not lv then lv, tg = hdr:match("%s([VDIWEFA])/([^%]]+)") end
    if lv then
      level = lv:upper()
      tag = (tg or ""):gsub("%s+$", "")
    end
    body = rest or ""
  else
    local lv, tg, msg = block:match("^%s*([VDIWEFA])/([^:%s]+)%s*:%s*(.*)$")
    if not lv then
      lv, tg, msg = block:match(
        "^%d%d%-%d%d%s+%d%d:%d%d:%d%d%.%d+%s+%d+%s+%d+%s+([VDIWEFA])%s+([^:]+):%s*(.*)$")
    end
    if lv then
      level = lv:upper()
      tag = (tg or ""):gsub("%s+$", "")
      body = msg or ""
    end
  end
  body = body:gsub("^%s+", ""):gsub("%s+$", "")
  local preview
  if tag ~= "" and body ~= "" then
    preview = tag .. " · " .. api.truncate(body:gsub("\n", " "), 90)
  elseif tag ~= "" then
    preview = tag
  else
    preview = api.truncate(block:gsub("\n", " "), 100)
  end
  return level, tag, preview, block
end

function api.ensureLogcatAdp()
  if S.logcatAdp or not ui.logcatList then return end
  api.resolveTheme()
  S.logcatAdp = J.LuaAdapter(activity, S.logcatData, {
    J.LinearLayout,
    orientation = "horizontal",
    layout_width = "match",
    layout_height = "wrap",
    gravity = "center_vertical",
    paddingLeft = "10dp",
    paddingRight = "10dp",
    paddingTop = "6dp",
    paddingBottom = "6dp",
    {
      J.TextView,
      id = "lvl",
      layout_width = "24dp",
      layout_height = "24dp",
      gravity = "center",
      textSize = "12sp",
      textStyle = "bold",
      includeFontPadding = false,
    },
    {
      J.TextView,
      id = "txt",
      layout_width = "0dp",
      layout_weight = 1,
      layout_height = "wrap",
      layout_marginStart = "8dp",
      textSize = "11sp",
      textColor = c.onSurface,
      maxLines = 2,
      ellipsize = "end",
    },
  })
  local AbsListView = bindClass "android.widget.AbsListView"
  if ui.logcatList.setOnScrollListener then
    local OnScrollListener = bindClass "android.widget.AbsListView$OnScrollListener"
    ui.logcatList.setOnScrollListener(OnScrollListener({
      onScrollStateChanged = function() end,
      onScroll = function()
        api.paintLogcatBadges()
      end,
    }))
  end
  ui.logcatList.setAdapter(S.logcatAdp)
  ui.logcatList.onItemClick = function(_, v, _, d)
    api.vibrate(v)
    ui.textEdit.setText(S.logcatFull[d] or "")
    ui.page.setCurrentItem(3, false)
  end
  ui.logcatList.onItemLongClick = function(_, v, _, d)
    api.vibrate(v)
    api.clipboardSet(S.logcatFull[d] or "")
    api.toast(api.t("copied_logcat"))
    return true
  end
end

function api.paintLogcatBadges()
  if not ui.logcatList then return end
  local n = ui.logcatList.getChildCount()
  for i = 0, n - 1 do
    local row = ui.logcatList.getChildAt(i)
    if row and row.getChildCount and row.getChildCount() > 0 then
      local badge = row.getChildAt(0)
      if badge and badge.getText then
        local t = tostring(badge.getText() or "")
        if t ~= "" then
          api.applyRound(badge, api.logcatLevelFill(t), 6)
          badge.setTextColor(api.logcatLevelColor(t))
        end
      end
    end
  end
end

-- 后台任务：优先 xTask(io)，其次 task，最后同步
-- 注意：Java 注入的 xTask/task 在 Luaj 里 type 常为 userdata，不能用 type=="function"
function api.runBg(bgFn, onMain, dispatcher)
  dispatcher = dispatcher or "io"
  local function deliver(result)
    if onMain then onMain(result) end
  end
  if xTask ~= nil then
    local ok = pcall(function()
      xTask(function()
        return bgFn()
      end, function(result)
        deliver(result)
      end, dispatcher)
    end)
    if ok then return true end
    ok = pcall(function()
      xTask {
        task = function() return bgFn() end,
        callback = function(result) deliver(result) end,
        dispatcher = dispatcher,
      }
    end)
    if ok then return true end
  end
  if task ~= nil then
    local ok = pcall(function()
      task(function()
        return bgFn()
      end, function(result)
        if result ~= nil then deliver(result) end
      end)
    end)
    if ok then return true end
  end
  local ok, result = pcall(bgFn)
  if ok then deliver(result) end
  return ok
end

function api.applyLogcatText(str)
  if not api.activityAlive() or not S.logcatAdp then return end
  if str == nil then str = "" end
  str = tostring(str)
  table.clear(S.logcatData)
  table.clear(S.logcatFull)
  local blocks = {}
  local n = 0
  str:gsub("[^\n]+", function(w)
    if n % 2 == 0 then
      if not w:find("^%[") then
        if #blocks > 0 then
          blocks[#blocks] = blocks[#blocks] .. "\n" .. w
        else
          blocks[1] = w
          n = n + 1
        end
      else
        blocks[#blocks + 1] = w
        n = n + 1
      end
    else
      blocks[#blocks] = blocks[#blocks] .. "\n" .. w
      n = n + 1
    end
  end)
  local start = 1
  if #blocks > S.MAX_LOGCAT then start = #blocks - S.MAX_LOGCAT + 1 end
  for i = start, #blocks do
    local level, _, preview, full = api.parseLogcatBlock(blocks[i])
    S.logcatData[#S.logcatData + 1] = {
      lvl = {
        text = level,
        textColor = api.logcatLevelColor(level),
        BackgroundColor = api.logcatLevelFill(level),
      },
      txt = {
        text = preview,
        textColor = c.onSurface,
      },
    }
    S.logcatFull[#S.logcatData] = full
  end
  if S.logcatAdp then S.logcatAdp.notifyDataSetChanged() end
  if ui.logcatList then
    ui.logcatList.post(function() api.paintLogcatBadges() end)
  end
end

function api.refreshLogcat()
  if not ui.logcatList then return end
  api.ensureLogcatAdp()
  local filter = S.logcatTypes[S.logcatPos] or ""
  -- xTask 后台读 logcat，主线程刷新列表
  api.runBg(function()
    return api.readlog(filter)
  end, function(str)
    api.applyLogcatText(str)
  end, "io")
end

function api.setupLogcatChips()
  local function paint()
    api.resolveTheme()
    for j, oid in ipairs(S.logcatChipIds) do
      local btn = ui[oid]
      if btn then
        local on = j == S.logcatPos
        api.compactButtonMetrics(btn, 32, 10)
        pcall(function()
          btn.setTextColor(on and c.primary or c.onSurfaceVariant)
          if on then
            api.applyRound(btn, c.secondaryContainer, 16)
          else
            btn.setBackgroundColor(0)
          end
        end)
      end
    end
  end
  for i, id in ipairs(S.logcatChipIds) do
    local btn = ui[id]
    if btn then
      btn.onClick = function(v)
        api.vibrate(v)
        S.logcatPos = i
        paint()
        api.refreshLogcat()
      end
    end
  end
  paint()
end

-- actionSpecs: item[1] = i18n key（共享 S.L），item[2] = handler
S.actionSpecs = {
  [0] = {
    { "clear", function() api.clearPrints() end },
    { "copy", function() api.copyFilteredPrints() end },
    { "bottom", function() api.scrollPrintToBottom() end },
    { "export", function() api.exportPrints(false) end },
    { "share", function() api.exportPrints(true) end },
    { "close", function() if S.sheet then S.sheet.dismiss() end end },
  },
  [1] = {
    { "refresh", function() api.refreshVars() end },
    { "root", function()
      table.clear(S.variableNode)
      S.varQuery = ""
      if ui.varSearch then ui.varSearch.setText("") end
      api.refreshVars()
    end },
    { "copy_path", function()
      local path = "/" .. table.concat(S.variableNode, "/")
      api.clipboardSet(path)
      api.toast(path)
    end },
    { "close", function() if S.sheet then S.sheet.dismiss() end end },
  },
  [2] = {
    { "clear", function()
      api.runBg(function()
        api.clearlog()
        return true
      end, function()
        api.refreshLogcat()
      end, "io")
    end },
    { "refresh", function() api.refreshLogcat() end },
    { "copy", function()
      local body = table.concat(S.logcatFull, "\n\n")
      if body == "" then api.toast(api.t("empty")); return end
      api.clipboardSet(body)
      api.toast(api.t("copied_logcat"))
    end },
    { "export", function()
      local body = table.concat(S.logcatFull, "\n\n")
      if body == "" then api.toast(api.t("empty_logcat")); return end
      local stamp = "logcat"
      pcall(function() stamp = S.fileStampFmt.format(J.System.currentTimeMillis()) end)
      local path = api.crashDir() .. "/vconsole_logcat_" .. stamp .. ".txt"
      if api.writeTextFileJava(path, body) then
        api.toast(api.tf("saved", path))
        info("logcat → " .. path)
      else
        api.toast(api.t("export_failed"))
      end
    end },
    { "close", function() if S.sheet then S.sheet.dismiss() end end },
  },
  [3] = {
    { "copy", function()
      api.clipboardSet(ui.textEdit.getText())
      api.toast(api.t("copied"))
    end },
    { "paste", function() ui.textEdit.setText(api.clipboardGet()) end },
    { "share", function()
      local body = tostring(ui.textEdit.getText() or "")
      if body == "" then api.toast(api.t("empty")); return end
      pcall(function()
        local intent = J.Intent(J.Intent.ACTION_SEND)
        intent.setType("text/plain")
        intent.putExtra(J.Intent.EXTRA_TEXT, body)
        activity.startActivity(J.Intent.createChooser(intent, api.t("share_text")))
      end)
    end },
    { "save", function()
      local body = tostring(ui.textEdit.getText() or "")
      if body == "" then api.toast(api.t("empty")); return end
      local stamp = "text"
      pcall(function() stamp = S.fileStampFmt.format(J.System.currentTimeMillis()) end)
      local path = api.crashDir() .. "/vconsole_text_" .. stamp .. ".txt"
      if api.writeTextFileJava(path, body) then
        api.toast(api.tf("saved", path))
        info("text → " .. path)
      else
        api.toast(api.t("save_failed"))
      end
    end },
    { "clear", function() ui.textEdit.setText(nil) end },
    { "close", function() if S.sheet then S.sheet.dismiss() end end },
  },
  [4] = {
    { "device", function() api.openTextInPanel(api.t("device"), api.deviceInfoText()) end },
    { "memory", function() api.openTextInPanel(api.t("memory"), api.runtimeMemText()) end },
    { "views", function()
      if ui.page then ui.page.setCurrentItem(5, true) end
      api.paintTabs(5)
      api.onPage(5)
    end },
    { "export", function() api.exportPrints(false) end },
    { "close", function() if S.sheet then S.sheet.dismiss() end end },
  },
  [5] = {
    { "refresh", function()
      api.ensureViewTreeAdp()
      api.viewTreeRefresh()
    end },
    { "views_collapse", function() api.viewTreeCollapseAll() end },
    { "views_only_vis", function()
      S.viewOnlyVisible = not S.viewOnlyVisible
      api.viewTreeRefresh()
      api.rebuildActionBar(5)
    end },
    { "export", function()
      api.openTextInPanel(api.t("views"), api.dumpViewTree(nil, 10))
    end },
    { "close", function() if S.sheet then S.sheet.dismiss() end end },
  },
}

function api.rebuildActionBar(pos)
  if not ui.actionBar then return end
  ui.actionBar.removeAllViews()
  for i, item in ipairs(S.actionSpecs[pos] or S.actionSpecs[0]) do
    local label = api.t(item[1])
    -- Views 页：仅可见开关显示当前状态
    if pos == 5 and item[1] == "views_only_vis" then
      label = S.viewOnlyVisible and api.t("views_only_vis") or api.t("views_all")
    end
    local btn = loadlayout({
      J.Button,
      text = label,
      layout_width = "0dp",
      layout_weight = 1,
      layout_height = "36dp",
      minHeight = "36dp",
      textSize = "12sp",
      includeFontPadding = false,
      BackgroundColor = 0,
      textColor = c.primary,
    }, {})
    api.applyButtonTheme(btn, c.secondaryContainer, c.onSecondaryContainer, 12, 32)
    if i > 1 then
      local lp = btn.getLayoutParams()
      if lp then
        if lp.setMarginStart then
          lp.setMarginStart(api.dp(4))
        else
          lp.leftMargin = api.dp(4)
        end
        btn.setLayoutParams(lp)
      end
    end
    btn.onClick = function(v)
      api.vibrate(v)
      item[2]()
    end
    ui.actionBar.addView(btn)
  end
end

function api.onPage(pos)
  api.rebuildActionBar(pos)
  if pos == 0 then
    api.pullHostLogs()
  elseif pos == 1 then
    api.ensureVarAdp()
    api.refreshVars()
  elseif pos == 2 then
    api.ensureLogcatAdp()
    api.refreshLogcat()
  elseif pos == 5 then
    api.ensureViewTreeAdp()
    if not S.viewTreeRoot then
      api.viewTreeRefresh()
    else
      api.viewTreeRebuildFlat()
    end
  end
end

function api.paintTabs(pos)
  api.resolveTheme()
  for i, id in ipairs(S.tabIds) do
    local btn = ui[id]
    if btn then
      local on = (i - 1) == pos
      api.compactButtonMetrics(btn, 32, 10)
      btn.setTextColor(on and c.primary or c.onSurfaceVariant)
      if on then
        api.applyRound(btn, c.secondaryContainer, 16)
      else
        btn.setBackgroundColor(0)
      end
    end
  end
end

function api.wireSheet()
  -- 适配器/筛选先建；失败会抛出（布局 id 固定，不应静默）
  api.ensurePrintAdp()
  api.ensureVarAdp()
  api.ensureLogcatAdp()
  api.setupLogcatChips()
  api.setupPrintFilters()
  api.rebuildPrintList()

  local ctrlIds = {
    "ctrlFinish", "ctrlRecreate", "ctrlRestart", "ctrlKill",
    "ctrlDevice", "ctrlMem", "ctrlIntent", "ctrlViews",
    "ctrlPaths", "ctrlGc", "ctrlPause", "ctrlScreen",
    "ctrlHide", "ctrlHist", "ctrlRun",
    "headerClear", "headerExport", "headerLang",
  }
  for _, id in ipairs(ctrlIds) do
    local btn = ui[id]
    if btn then
      if id == "ctrlKill" then
        api.applyButtonTheme(btn, c.errorContainer, c.onErrorContainer, 12, 40)
      elseif id == "ctrlRun" then
        api.applyButtonTheme(btn, c.primary, c.onPrimary, 12, 32)
      elseif id == "headerClear" or id == "headerExport" or id == "headerLang" then
        api.applyButtonTheme(btn, 0, c.primary, 0, 32)
      else
        api.applyButtonTheme(btn, c.secondaryContainer, c.onSecondaryContainer, 12, 40)
      end
    end
  end
  if ui.printSearchClear then
    api.compactButtonMetrics(ui.printSearchClear, 32, 4)
  end
  if ui.ctrlPause then
    ui.ctrlPause.setText(S.loggingPaused and api.t("resume_log") or api.t("pause_log"))
  end
  if ui.ctrlScreen then
    ui.ctrlScreen.setText(S.keepScreenOn and api.t("screen_off") or api.t("screen_on"))
  end
  if ui.ctrlCode and ui.ctrlCode.getParent() then
    api.applyRound(ui.ctrlCode.getParent(), c.surfaceContainerHigh, 12)
  end

  for i, id in ipairs(S.tabIds) do
    local btn = ui[id]
    if btn then
      btn.onClick = function(v)
        api.vibrate(v)
        if ui.page then ui.page.setCurrentItem(i - 1, true) end
        api.paintTabs(i - 1)
        api.onPage(i - 1)
      end
    end
  end
  api.paintTabs(0)

  if ui.headerClear then
    ui.headerClear.onClick = function(v)
      api.vibrate(v)
      api.clearForCurrentPage()
    end
  end
  if ui.headerExport then
    ui.headerExport.onClick = function(v)
      api.vibrate(v)
      api.exportPrints(false)
    end
  end
  if ui.headerLang then
    ui.headerLang.onClick = function(v)
      api.vibrate(v)
      api.toggleLang()
    end
  end

  pcall(function()
    ui.page.addOnPageChangeListener {
      onPageSelected = function(pos)
        api.paintTabs(pos)
        api.onPage(pos)
      end,
    }
  end)

  local function bindClick(btn, fn)
    if not btn then return end
    pcall(function()
      btn.onClick = function(v)
        api.vibrate(v)
        fn(v)
      end
    end)
  end

  bindClick(ui.ctrlFinish, function()
    if S.sheet then S.sheet.dismiss() end
    activity.finish()
  end)
  bindClick(ui.ctrlRecreate, function()
    if S.sheet then S.sheet.dismiss() end
    activity.recreate()
  end)
  bindClick(ui.ctrlRestart, function()
    if S.sheet then S.sheet.dismiss() end
    local intent = activity.getIntent()
    activity.finish()
    activity.startActivity(intent)
  end)
  bindClick(ui.ctrlKill, function()
    if S.sheet then S.sheet.dismiss() end
    api.removeBubble()
    os.exit()
  end)
  bindClick(ui.ctrlDevice, function()
    api.openTextInPanel(api.t("device"), api.deviceInfoText())
  end)
  bindClick(ui.ctrlMem, function()
    api.openTextInPanel(api.t("memory"), api.runtimeMemText())
  end)
  bindClick(ui.ctrlIntent, function()
    api.openTextInPanel(api.t("intent"), api.intentExtrasText())
  end)
  bindClick(ui.ctrlViews, function()
    if ui.page then ui.page.setCurrentItem(5, true) end
    api.paintTabs(5)
    api.onPage(5)
  end)
  bindClick(ui.ctrlPaths, function()
    local lines = { "=== Paths ===" }
    if this.getLuaPath then lines[#lines + 1] = "Lua: " .. tostring(this.getLuaPath()) end
    if this.getLuaDir then lines[#lines + 1] = "LuaDir: " .. tostring(this.getLuaDir()) end
    lines[#lines + 1] = "Files: " .. activity.getFilesDir().getAbsolutePath()
    lines[#lines + 1] = "Cache: " .. activity.getCacheDir().getAbsolutePath()
    local e = activity.getExternalFilesDir(nil)
    if e then lines[#lines + 1] = "Ext: " .. e.getAbsolutePath() end
    if this.getMediaDir then
      lines[#lines + 1] = "Media: " .. this.getMediaDir().getAbsolutePath()
    end
    lines[#lines + 1] = "Crash: " .. api.crashDir()
    if S.lastCrashPath then lines[#lines + 1] = "Last crash: " .. S.lastCrashPath end
    api.openTextInPanel(api.t("paths"), table.concat(lines, "\n"))
  end)
  bindClick(ui.ctrlGc, function()
    api.runGcAndReport()
  end)
  bindClick(ui.ctrlPause, function()
    api.toggleLoggingPause()
  end)
  bindClick(ui.ctrlScreen, function()
    api.toggleKeepScreenOn()
  end)
  bindClick(ui.ctrlHide, function()
    if S.sheet then S.sheet.dismiss() end
    api.hideBubbleTemporarily()
  end)
  bindClick(ui.ctrlHist, function()
    if #S.evalHistory == 0 then
      api.toast(api.t("no_eval_hist"))
      return
    end
    local last = S.evalHistory[#S.evalHistory]
    if ui.ctrlCode then ui.ctrlCode.setText(last) end
    api.toast(api.tf("loaded_eval", #S.evalHistory))
  end)
  if ui.ctrlHist then
    ui.ctrlHist.onLongClick = function(v)
      api.vibrate(v)
      if #S.evalHistory == 0 then
        api.toast(api.t("no_eval_hist"))
        return true
      end
      api.openTextInPanel(api.t("eval_history"), table.concat(S.evalHistory, "\n---\n"))
      return true
    end
  end
  bindClick(ui.ctrlRun, function()
    if not ui.ctrlCode then return end
    local src = tostring(ui.ctrlCode.getText() or "")
    local f, e = load(src)
    if f then
      local ok, ret = pcall(f)
      if ok then
        api.pushEvalHistory(src)
        ui.ctrlCode.setText("")
        if ret ~= nil then
          info("eval ok → " .. api.truncate(api.dumpValue(ret), 200))
          api.openTextInPanel(api.t("eval_result"), api.dumpValue(ret))
        else
          info("eval ok")
        end
      else
        safe_error(ret)
        api.toast(api.t("runtime_error"))
      end
    else
      safe_error(e)
      api.toast(api.t("syntax_error"))
    end
  end)

  api.rebuildActionBar(0)
  api.pullHostLogs()
  api.rebuildPrintList()
  api.applyI18n()
end

function api.showSheet()
  if not api.activityAlive() then return end
  api.loadLangPref()
  api.resolveTheme(true)
  if S.sheet and S.sheet.isShowing() then return end

  local content = api.buildSheetContent()
  local dw, dh = api.preferredSheetSize()
  content.setLayoutParams(J.FrameLayout.LayoutParams(-1, dh))
  content.setMinimumHeight(dh)

  S.sheet = J.AppCompatDialog(activity)
  S.sheet.setCancelable(true)
  S.sheet.setCanceledOnTouchOutside(true)
  if S.sheet.supportRequestWindowFeature then
    S.sheet.supportRequestWindowFeature(1) -- FEATURE_NO_TITLE
  elseif S.sheet.requestWindowFeature then
    S.sheet.requestWindowFeature(1)
  end
  local win = S.sheet.getWindow()
  if win then
    win.setBackgroundDrawable(J.ColorDrawable(0))
    win.getDecorView().setPadding(0, 0, 0, 0)
    local attrs = win.getAttributes()
    attrs.width = dw
    attrs.height = dh
    attrs.gravity = J.Gravity.CENTER
    attrs.dimAmount = 0.45
    win.setAttributes(attrs)
  end
  S.sheet.setContentView(content)
  S.sheet.setOnDismissListener(function()
    S.sheet = nil
    for k in pairs(ui) do ui[k] = nil end
    S.printAdp = nil
    S.variableAdp = nil
    S.logcatAdp = nil
    S.viewTreeAdp = nil
    S.viewTreeRoot = nil
    table.clear(S.viewTreeFlat)
    table.clear(S.viewTreeData)
  end)

  api.wireSheet()
  api.setBubbleError(false)

  api.applyRound(content, c.surface, 18)
  if ui.printSearch and ui.printSearch.getParent() then
    api.applyRound(ui.printSearch.getParent(), c.surfaceContainerHigh, 12)
  end
  if ui.actionBar then
    api.applyRound(ui.actionBar, c.surfaceContainerLow, 0)
  end

  S.sheet.show()
  api.applySheetLayout(content, S.sheet)
  content.post(function()
    if S.sheet then api.applySheetLayout(content, S.sheet) end
  end)
end

-- ─── Lifecycle（链式旧回调） ─────────────────────────────
api.chainGlobal("onDestroy", function()
  api.removeBubble()
  if S.sheet then
    S.sheet.dismiss()
    S.sheet = nil
  end
end)

api.chainGlobal("onConfigurationChanged", function()
  S.dm = activity.getResources().getDisplayMetrics()
  if S.bubbleAttached then api.snapBubble() end
end)

-- ─── Boot：仅在 setContentView 之后挂悬浮钮（不碰 statusBar / 主题） ───
do
  local logs = J.LuaActivityClass.logs
  if logs then S.hostLogsCursor = logs.size() end
end

function api.bootUi()
  if S.bootDone or not api.activityAlive() then return end
  S.bootDone = true
  api.loadLangPref()
  api.resolveTheme(true)
  api.attachBubble()
  if not S.bubbleAttached then
    local decor = api.resolveContentRoot()
    if decor and decor.post then
      decor.post(function()
        if not S.bubbleAttached then api.attachBubble() end
      end)
    end
  end
  local pkg = activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0)
  local label = tostring(pkg.applicationInfo.loadLabel(activity.getPackageManager()))
  info(string.format(
    "System: %s · Android %s (SDK %s) · %s %s",
    J.Build.MODEL,
    J.Build.VERSION.RELEASE,
    tostring(J.Build.VERSION.SDK_INT or J.Build.VERSION.SDK),
    label,
    tostring(pkg.versionName)))
  info("File: " .. tostring(this.getLuaPath()))
end

-- 等宿主 setContentView 触发 onContentChanged，再挂 UI
-- （require 在文件顶部时也不会在 dynamicColor 前 inflate）
api.chainGlobal("onContentChanged", function()
  if not S.bootDone then
    api.bootUi()
    return
  end
  if not S.bubble or not S.bubbleAttached or not S.bubble.getParent() then
    S.bubbleAttached = false
    api.attachBubble()
  end
end)

-- 若 require 在 setContentView 之后，content 已存在则下一帧启动
do
  local root = api.resolveContentRoot()
  if root and root.getChildCount and root.getChildCount() > 0 and root.post then
    root.post(function() api.bootUi() end)
  end
end

return true
