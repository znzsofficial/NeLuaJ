--- Pure inline renderer. Code spans and links are tokenized before emphasis.
local _M = {}

local function escape(text)
  return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function closing(source, start, opening, ending)
  local depth, i = 1, start
  while i <= #source do
    local char = source:sub(i, i)
    if char == "\\" then
      i = i + 2
    else
      if char == opening then depth = depth + 1 end
      if char == ending then depth = depth - 1 end
      if depth == 0 then return i end
      i = i + 1
    end
  end
end

function _M.render(source, linkHex, depth)
  source = tostring(source or "")
  depth = depth or 0
  if depth >= 8 then return escape(source) end
  local parts, tokens = {}, {}
  local function token(html)
    tokens[#tokens + 1] = html
    parts[#parts + 1] = "\001MD" .. #tokens .. "\002"
  end
  local i = 1
  while i <= #source do
    local char = source:sub(i, i)
    if char == "\\" and source:sub(i + 1, i + 1):match("%p") then
      token(escape(source:sub(i + 1, i + 1)))
      i = i + 2
    elseif char == "`" then
      local run = source:match("^`+", i)
      local search, finish = i + #run, nil
      while search <= #source do
        local first, last = source:find("`+", search)
        if not first then break end
        if last - first + 1 == #run then finish = first; break end
        search = last + 1
      end
      if finish then
        local code = source:sub(i + #run, finish - 1):gsub("\n", " ")
        if code:sub(1, 1) == " " and code:sub(-1) == " " and code:find("[^ ]") then
          code = code:sub(2, -2)
        end
        token("<m-code><font face='monospace'>" .. escape(code) .. "</font></m-code>")
        i = finish + #run
      else
        parts[#parts + 1] = run
        i = i + #run
      end
    elseif char == "[" then
      local labelEnd = closing(source, i + 1, "[", "]")
      local urlEnd = labelEnd and source:sub(labelEnd + 1, labelEnd + 1) == "("
        and closing(source, labelEnd + 2, "(", ")")
      local url = urlEnd and source:sub(labelEnd + 2, urlEnd - 1)
      if url and url:match("^https?://%S+$") then
        local label = _M.render(source:sub(i + 1, labelEnd - 1), linkHex, depth + 1)
        if linkHex then label = "<font color='" .. linkHex .. "'>" .. label .. "</font>" end
        token("<a href='" .. escape(url):gsub("'", "&#39;"):gsub('"', "&quot;") .. "'>" .. label .. "</a>")
        i = urlEnd + 1
      else
        parts[#parts + 1] = char
        i = i + 1
      end
    else
      parts[#parts + 1] = escape(char)
      i = i + 1
    end
  end
  local html = table.concat(parts)
  html = html:gsub("%*%*(.-)%*%*", "<b>%1</b>")
  html = html:gsub("(%f[%w_])__([^_]+)__(%f[^%w_])", "%1<b>%2</b>%3")
  html = html:gsub("%*([^*]-)%*", "<i>%1</i>")
  html = html:gsub("(%f[%w_])_([^_]+)_(%f[^%w_])", "%1<i>%2</i>%3")
  html = html:gsub("~~(.-)~~", "<s>%1</s>")
  return (html:gsub("\001MD(%d+)\002", function(index) return tokens[tonumber(index)] end))
end

return _M
