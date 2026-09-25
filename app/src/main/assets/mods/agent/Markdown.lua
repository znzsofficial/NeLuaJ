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

--- 把文本段渲染为 Spanned，支持标题、列表、粗体、斜体和行内代码。
function _M.renderMarkdown(text)
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
