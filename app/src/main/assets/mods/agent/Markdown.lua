--- Markdown 渲染辅助：HTML 转义、Spanned 渲染与代码块切分。
--- 从 ChatUI 原样抽出（零行为改动），供 ChatUI 与气泡渲染层共用。
--- HtmlCompat 延迟到首次渲染时绑定：模块加载零 Android 依赖，
--- splitCodeBlocks 可在独立 LuaJ 挂架中做行为测试。
local _M = {}

local HtmlCompat = nil

local function ensureHtmlCompat()
  if not HtmlCompat then
    HtmlCompat = luajava.bindClass("androidx.core.text.HtmlCompat")
  end
  return HtmlCompat
end

local function escapeHtml(text)
  text = text:gsub("&", "&amp;")
  text = text:gsub("<", "&lt;")
  text = text:gsub(">", "&gt;")
  return text
end

local MarkdownAST = nil
local okAst, astMod = pcall(require, "mods.agent.markdown.MarkdownAST")
if okAst and astMod then
  MarkdownAST = astMod
else
  pcall(function()
    local path = (ASSETS or "app/src/main/assets/") .. "mods/agent/markdown/MarkdownAST.lua"
    MarkdownAST = assert(loadfile(path))()
  end)
end

if MarkdownAST then
  _M.splitTableRow = MarkdownAST.splitTableRow
  _M.isTableSeparator = MarkdownAST.isTableSeparator
  _M.parseBlocks = MarkdownAST.parseBlocks
end

--- 十六进制颜色（#RRGGBB），供 <font color> 使用
local function hexColor(color)
  color = tonumber(color)
  if not color then return nil end
  return string.format("#%06X", color % 0x1000000)
end

--- 把文本段渲染为 Spanned。支持：标题（h1-h6）、有序/无序列表、嵌套列表项、
--- 任务列表（- [ ] / - [x]）、引用、分割线、管道表格、粗体、斜体、删除线、
--- 行内代码、链接与代码块。
--- opts.codeColor / opts.codeBg / opts.linkColor / opts.accentColor / opts.quoteColor：
--- 由调用方传入合适的前景色/背景色；缺省时采用自适应配色。
function _M.renderMarkdown(text, opts)
  opts = opts or {}
  local linkHex = hexColor(opts.linkColor)
  local function inline(source)
    local html = escapeHtml(source)
    local codeSpans = {}
    html = html:gsub("`([^`]+)`", function(code)
      local token = "\001CODE" .. tostring(#codeSpans + 1) .. "\002"
      -- 双层包裹：外层由 TagHandler 赋予现代圆角底色与微缩等宽，内层保证原生 HtmlCompat 降级时仍是 monospace
      codeSpans[#codeSpans + 1] = "<m-code><font face='monospace'>" .. code .. "</font></m-code>"
      return token
    end)
    local links = {}
    html = html:gsub("%[([^%]]+)%]%((https?://[^%)%s]+)%)", function(label, url)
      local token = "\001LINK" .. tostring(#links + 1) .. "\002"
      local styled = label
      if linkHex then styled = "<font color='" .. linkHex .. "'>" .. label .. "</font>" end
      links[#links + 1] = "<a href='" .. url:gsub("'", "&#39;") .. "'>" .. styled .. "</a>"
      return token
    end)
    html = html:gsub("%*%*(.-)%*%*", "<b>%1</b>")
    html = html:gsub("__([^_]+)__", "<b>%1</b>")
    html = html:gsub("%*([^*]-)%*", "<i>%1</i>")
    -- 仅匹配词边界下划线斜体，防止 snake_case（如 user_id_param）被误拆分为斜体
    html = html:gsub("(%f[%w_])_([^_]+)_(%f[^%w_])", "%1<i>%2</i>%3")
    html = html:gsub("^%s*_([^_]+)_%s*$", "<i>%1</i>")
    html = html:gsub("~~(.-)~~", "<s>%1</s>")
    html = html:gsub("\001LINK(%d+)\002", function(index) return links[tonumber(index)] end)
    html = html:gsub("\001CODE(%d+)\002", function(index) return codeSpans[tonumber(index)] end)
    return html
  end

  text = tostring(text or ""):gsub("\r\n", "\n")
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  local html = {}
  local inList = nil
  local function closeList()
    if inList then html[#html + 1] = "</" .. inList .. ">"; inList = nil end
  end

  --- 分隔行检测走模块级共享实现
  local isTableSeparator = _M.isTableSeparator

  local i = 1
  while i <= #lines do
    local line = lines[i]
    -- 表格块：表头行 + 分隔行 + 任意数据行，emit 真实 <table><tr><td> 标签
    if line:match("^%s*|") and lines[i + 1] and isTableSeparator(lines[i + 1]) then
      closeList()
      local tableHtml = { "<table>" }
      -- 表头行（<th>，TagHandler 同样用双空格间隔）
      tableHtml[#tableHtml + 1] = "<tr>"
      for _, cell in ipairs(_M.splitTableRow(line)) do
        tableHtml[#tableHtml + 1] = "<th>" .. inline(cell) .. "</th>"
      end
      tableHtml[#tableHtml + 1] = "</tr>"
      -- 数据行
      local j = i + 2
      while j <= #lines and lines[j]:match("^%s*|") do
        tableHtml[#tableHtml + 1] = "<tr>"
        for _, cell in ipairs(_M.splitTableRow(lines[j])) do
          tableHtml[#tableHtml + 1] = "<td>" .. inline(cell) .. "</td>"
        end
        tableHtml[#tableHtml + 1] = "</tr>"
        j = j + 1
      end
      tableHtml[#tableHtml + 1] = "</table>"
      html[#html + 1] = table.concat(tableHtml)
      i = j
    else
      local headingLevel, heading = line:match("^%s*(#+)%s+(.+)$")
      local taskMark, taskText = line:match("^%s*[-*+]%s+%[([ xX])%]%s+(.+)$")
      local bullet = line:match("^%s*[-*+]%s+(.+)$")
      local orderedNum, orderedText = line:match("^%s*(%d+)[%.%)]%s+(.+)$")
      local quote = line:match("^%s*>%s?(.*)$")
      local indent = #line:match("^%s*")
      if heading and #headingLevel <= 6 then
        closeList()
        local level = #headingLevel
        if level == 1 then
          html[#html + 1] = "<m-h1><big><big><b>" .. inline(heading) .. "</b></big></big></m-h1><br><br>"
        elseif level == 2 then
          html[#html + 1] = "<m-h2><big><b>" .. inline(heading) .. "</b></big></m-h2><br>"
        elseif level == 3 then
          html[#html + 1] = "<m-h3><b>" .. inline(heading) .. "</b></m-h3><br>"
        else
          html[#html + 1] = "<b>" .. inline(heading) .. "</b><br>"
        end
      elseif line:match("^%s*[-*_]%s*[-*_]%s*[-*_][%s-_*]*$") then
        closeList(); html[#html + 1] = "<m-hr/>"
      elseif taskMark then
        closeList()
        local isDone = (taskMark == "x" or taskMark == "X")
        if isDone then
          html[#html + 1] = "✓ <s>" .. inline(taskText) .. "</s><br>"
        else
          html[#html + 1] = "○ " .. inline(taskText) .. "<br>"
        end
      elseif bullet then
        if indent >= 2 and inList and html[#html] then
          html[#html] = html[#html]
            .. "<br>\194\160\194\160◦ " .. inline(bullet)
        else
          if inList ~= "ul" then closeList(); html[#html + 1] = "<ul>"; inList = "ul" end
          html[#html + 1] = "<li>" .. inline(bullet) .. "</li>"
        end
      elseif orderedNum and orderedText then
        closeList()
        html[#html + 1] = orderedNum .. ". " .. inline(orderedText) .. "<br>"
      elseif quote then
        closeList(); html[#html + 1] = "<m-quote><i>" .. inline(quote) .. "</i></m-quote><br>"
      elseif line:match("^%s*$") then
        closeList(); html[#html + 1] = "<br>"
      else
        closeList(); html[#html + 1] = inline(line) .. "<br>"
      end
      i = i + 1
    end
  end
  closeList()
  local compat = ensureHtmlCompat()
  local htmlText = table.concat(html)

  -- 统一通过增强版 MarkdownTagHandler 渲染自定义标签
  local ok, result = pcall(function()
    local ColorUtil = this.themeUtil
    local defaultTableBg = ColorUtil and ColorUtil.surface and ColorUtil.surface.containerHigh or 0x1A888888
    local tableBg = opts.tableBg or defaultTableBg
    local hrColor = ColorUtil and ColorUtil.outline and ColorUtil.outline.variant or 0x33888888
    local codeBg = opts.codeBg or (ColorUtil and ColorUtil.surface and ColorUtil.surface.containerHighest or 0x22888888)
    local codeText = opts.codeColor or 0
    local quoteStripe = opts.quoteColor or (ColorUtil and ColorUtil.primary and ColorUtil.primary.main or 0xFF4A90E2)
    local headingColor = opts.accentColor or 0
    local density = activity and activity.getResources() and activity.getResources().getDisplayMetrics().density or 2.0

    local HandlerClass = luajava.bindClass("com.nekolaska.ai.MarkdownTagHandler")
    local handler = HandlerClass(tableBg, hrColor, codeBg, codeText, quoteStripe, headingColor, density)
    return compat.fromHtml(htmlText, compat.FROM_HTML_MODE_LEGACY, nil, handler)
  end)
  if ok and result then return result end

  -- 回退机制（如纯单元测试环境或缺少新类）
  return compat.fromHtml(htmlText, compat.FROM_HTML_MODE_LEGACY)
end

--- 把内容拆分为文本段 + 代码块序列
function _M.splitCodeBlocks(content)
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

return _M
