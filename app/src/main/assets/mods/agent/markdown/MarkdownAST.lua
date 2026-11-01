--- 块级扫描与轻量 AST 构建器：将 Markdown 内容解析为规整的块级节点序列（Block Nodes）。
--- 包含：text（普通段落/标题/引用/列表）、code（代码块卡片）、table（原生表格结构）。
--- 纯标准 Lua 实现，0 Android 依赖，可在 PC 单测环境下 100% 离线脱水运行。
local _M = {}

--- 表格行解析：支持转义管道符 \|，保留单元格对齐文本
function _M.splitTableRow(line)
  if not line or not line:find("|", 1, true) then return {} end
  -- 保护转义管道符 \|
  local clean = line:gsub("\\|", "\001PIPE\002")
  clean = clean:gsub("^%s*|", ""):gsub("|%s*$", "")
  local cells = {}
  for cell in (clean .. "|"):gmatch("(.-)|") do
    local text = cell:gsub("^%s*", ""):gsub("%s*$", "")
    -- 还原转义管道符
    text = text:gsub("\001PIPE\002", "|")
    cells[#cells + 1] = text
  end
  return cells
end

--- 分隔行检测：检测是否符合 | --- | :---: | 形式
function _M.isTableSeparator(line)
  if not line or not line:match("^%s*|") then return false end
  local cells = _M.splitTableRow(line)
  if #cells == 0 then return false end
  for _, cell in ipairs(cells) do
    if not cell:match("^:?%-+:?$") then return false end
  end
  return true
end

--- 将文本拆分成块级节点流（Blocks）
--- 返回数组：{ { type = "text"|"code"|"table", ... }, ... }
function _M.parseBlocks(content)
  content = tostring(content or ""):gsub("\r\n", "\n")
  local blocks = {}
  local lines = {}
  for line in (content .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end

  local i = 1
  local textBuffer = {}

  local function flushText()
    if #textBuffer > 0 then
      local joined = table.concat(textBuffer, "\n")
      if joined ~= "" then
        blocks[#blocks + 1] = { type = "text", text = joined }
      end
      textBuffer = {}
    end
  end

  while i <= #lines do
    local line = lines[i]

    -- 1. 代码块起始匹配 ``` (允许行首 0~3 空格)
    local sIndent, sFence, sLang = line:match("^(%s*)(```+)(.*)$")
    if sFence and #sIndent <= 3 then
      flushText()
      local lang = sLang:gsub("^%s*(.-)%s*$", "%1")
      local codeLines = {}
      local j = i + 1
      local closed = false
      while j <= #lines do
        local curLine = lines[j]
        local eIndent, eFence = curLine:match("^(%s*)(```+)%s*$")
        if eFence and #eIndent <= 3 and #eFence >= #sFence then
          closed = true
          break
        end
        codeLines[#codeLines + 1] = curLine
        j = j + 1
      end

      if closed then
        blocks[#blocks + 1] = {
          type = "code",
          lang = lang,
          code = table.concat(codeLines, "\n"),
        }
        i = j + 1
      else
        -- 未闭合代码块（流式输出中常见）：保留为代码块结构以供优雅渲染
        blocks[#blocks + 1] = {
          type = "code",
          lang = lang,
          code = table.concat(codeLines, "\n"),
          unclosed = true,
        }
        i = j
      end
    -- 2. 表格块匹配：表头行 + 分隔行 + 数据行
    elseif line:match("^%s*|") and lines[i + 1] and _M.isTableSeparator(lines[i + 1]) then
      flushText()
      local headerCells = _M.splitTableRow(line)
      local alignRow = lines[i + 1]
      local alignCells = _M.splitTableRow(alignRow)
      local alignments = {}
      for idx, cell in ipairs(alignCells) do
        local leftCol = cell:sub(1, 1) == ":"
        local rightCol = cell:sub(-1) == ":"
        if leftCol and rightCol then
          alignments[idx] = "center"
        elseif rightCol then
          alignments[idx] = "right"
        else
          alignments[idx] = "left"
        end
      end

      local dataRows = {}
      local rawTableLines = { line, nextLine }
      local j = i + 2
      while j <= #lines and lines[j]:match("^%s*|") do
        rawTableLines[#rawTableLines + 1] = lines[j]
        local rowCells = _M.splitTableRow(lines[j])
        dataRows[#dataRows + 1] = rowCells
        j = j + 1
      end

      blocks[#blocks + 1] = {
        type = "table",
        headers = headerCells,
        alignments = alignments,
        rows = dataRows,
        raw = table.concat(rawTableLines, "\n"),
      }
      i = j
    else
      -- 普通文本段（段落、标题、引用、列表等由行内渲染器处理）
      textBuffer[#textBuffer + 1] = line
      i = i + 1
    end
  end

  flushText()
  return blocks
end

return _M
