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

--- 表格行解析：`| a | b |` → 单元格数组（保留空单元格）
function _M.splitTableRow(line)
  local body = line:gsub("^%s*|", ""):gsub("|%s*$", "")
  local cells = {}
  for cell in (body .. "|"):gmatch("(.-)|") do
    cells[#cells + 1] = cell:gsub("^%s*", ""):gsub("%s*$", "")
  end
  return cells
end

--- 分隔行：| --- | :---: | 之类只含 -、:、空白的行
function _M.isTableSeparator(line)
  if not line:match("^%s*|") then return false end
  local cells = _M.splitTableRow(line)
  if #cells == 0 then return false end
  for _, cell in ipairs(cells) do
    if not cell:match("^:?%-+:?$") then return false end
  end
  return true
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
--- opts.codeColor / opts.linkColor：内联代码与链接的着色（用户/AI 气泡底色不同，
--- 由调用方传入合适的前景色）；缺省时不着色。
function _M.renderMarkdown(text, opts)
  opts = opts or {}
  local codeOpen, codeClose = "<font face='monospace'>", "</font>"
  local codeHex = hexColor(opts.codeColor)
  if codeHex then
    codeOpen = "<font face='monospace' color='" .. codeHex .. "'>"
  end
  local linkHex = hexColor(opts.linkColor)
  local function inline(source)
    local html = escapeHtml(source)
    local codeSpans = {}
    html = html:gsub("`([^`]+)`", function(code)
      local token = "\001CODE" .. tostring(#codeSpans + 1) .. "\002"
      codeSpans[#codeSpans + 1] = codeOpen .. code .. codeClose
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
    html = html:gsub("_([^_]-)_", "<i>%1</i>")
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
    -- 表格块：表头行 + 分隔行 + 任意数据行。
    -- HtmlCompat.fromHtml 不支持 <table> 标签（单元格会被挤进同一行），
    -- 改为逐行等宽渲染——保留对齐且行为确定。
    if line:match("^%s*|") and lines[i + 1] and isTableSeparator(lines[i + 1]) then
      closeList()
      local rowLines = { "<font face='monospace'>" .. line .. "</font><br>" }
      local j = i + 2
      while j <= #lines and lines[j]:match("^%s*|") do
        rowLines[#rowLines + 1] = "<font face='monospace'>" .. lines[j] .. "</font><br>"
        j = j + 1
      end
      for k = 1, #rowLines do html[#html + 1] = rowLines[k] end
      i = j
    else
      local headingLevel, heading = line:match("^%s*(#+)%s+(.+)$")
      local taskMark, taskText = line:match("^%s*[-*+]%s+%[([ xX])%]%s+(.+)$")
      local bullet = line:match("^%s*[-*+]%s+(.+)$")
      local ordered = line:match("^%s*%d+[%.%)]%s+(.+)$")
      local quote = line:match("^%s*>%s?(.*)$")
      local indent = #line:match("^%s*")
      if heading and #headingLevel <= 6 then
        closeList()
        local level = #headingLevel
        if level == 1 then
          html[#html + 1] = "<big><big><b>" .. inline(heading) .. "</b></big></big><br><br>"
        elseif level == 2 then
          html[#html + 1] = "<big><b>" .. inline(heading) .. "</b></big><br>"
        elseif level == 3 then
          html[#html + 1] = "<b>" .. inline(heading) .. "</b><br>"
        else
          -- h4-h6：中号加粗，与正文区分即可
          html[#html + 1] = "<b>" .. inline(heading) .. "</b><br>"
        end
      elseif line:match("^%s*[-*_]%s*[-*_]%s*[-*_]%s*[-*_]%s*[-*_]%s*$") then
        closeList(); html[#html + 1] = "<hr>"
      elseif taskMark then
        -- 任务列表：[x] 完成 / [ ] 待办，渲染为勾选符号行（不进 <ul>）
        closeList()
        local mark = (taskMark == "x" or taskMark == "X") and "✓" or "○"
        html[#html + 1] = mark .. " " .. inline(taskText) .. "<br>"
      elseif bullet then
        if indent >= 2 and inList and html[#html] then
          -- 缩进列表项：并入上一条 <li>（<ul> 内裸文本会被解析器丢弃）
          html[#html] = html[#html]
            .. "<br>\194\160\194\160◦ " .. inline(bullet)
        else
          if inList ~= "ul" then closeList(); html[#html + 1] = "<ul>"; inList = "ul" end
          html[#html + 1] = "<li>" .. inline(bullet) .. "</li>"
        end
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
      i = i + 1
    end
  end
  closeList()
  local compat = ensureHtmlCompat()
  return compat.fromHtml(table.concat(html), compat.FROM_HTML_MODE_LEGACY)
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
