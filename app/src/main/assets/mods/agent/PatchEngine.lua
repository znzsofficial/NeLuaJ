--- 补丁引擎：SEARCH/REPLACE 块与 Unified Diff 的解析和应用。
--- 纯字符串算法，无任何环境依赖（activity/file/json），可在独立 LuaJ 运行时中测试。
--- 匹配策略分层：精确字面量 → 去首尾空行 → 行签名宽松匹配（忽略缩进/空白差异）。
local _M = {}

local function splitLines(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line:sub(-1) == "\r" then line = line:sub(1, -2) end
    lines[#lines + 1] = line
  end
  return lines
end

local function lineNumberAt(text, byteIndex)
  if not byteIndex or byteIndex < 1 then return 1 end
  local line = 1
  local pos = 1
  while true do
    local nl = text:find("\n", pos, true)
    if not nl or nl >= byteIndex then break end
    line = line + 1
    pos = nl + 1
  end
  return line
end

--- 把应用位置列表格式化为 "L12, L15-18" 形式，供结果回显
function _M.formatPatchLocations(locations)
  if type(locations) ~= "table" or #locations == 0 then return "" end
  local parts = {}
  for _, loc in ipairs(locations) do
    if loc.startLine == loc.endLine then
      parts[#parts + 1] = "L" .. tostring(loc.startLine)
    else
      parts[#parts + 1] = "L" .. tostring(loc.startLine) .. "-" .. tostring(loc.endLine)
    end
  end
  return table.concat(parts, ", ")
end

--- 应用 SEARCH/REPLACE 块
--- 格式: <<<<<<< SEARCH\nold\n=======\nnew\n>>>>>>> REPLACE

--- SEARCH 未整体命中时，找出在文件中分别存在的行，帮助模型定位差异
local function searchContextLines(original, searchContent)
  local origLines = {}
  for line in (original .. "\n"):gmatch("(.-)\n") do origLines[#origLines + 1] = line end
  local searchLines = {}
  for line in (searchContent .. "\n"):gmatch("(.-)\n") do
    local t = line:gsub("^%s*(.-)%s*$", "%1")
    if t ~= "" then searchLines[#searchLines + 1] = t end
  end
  local hints = {}
  for _, sl in ipairs(searchLines) do
    for i, ol in ipairs(origLines) do
      local ot = ol:gsub("^%s*", "")
      if ot == sl or ot:find(sl, 1, true) or sl:find(ot, 1, true) then
        hints[#hints + 1] = string.format("第 %d 行: %s", i, ol)
        break
      end
    end
  end
  if #hints > 0 then
    return "SEARCH 未整体匹配。以下行在文件中分别存在（可能被改动）:\n" .. table.concat(hints, "\n")
  end
  return ""
end

--- 行签名：去首尾空白并把连续空白折叠为单个空格，用于忽略缩进/空白差异的宽松匹配
local function lineSignature(line)
  return (line:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1"))
end

--- 计算每行起始字节位置（1 起）
local function computeLineStarts(text)
  local starts = { 1 }
  local pos = 1
  while true do
    local nl = text:find("\n", pos, true)
    if not nl then break end
    starts[#starts + 1] = nl + 1
    pos = nl + 1
  end
  return starts
end

--- 取第 i 行内容（不含行尾换行）
local function lineAt(text, starts, i)
  local p = starts[i]
  if not p then return nil end
  local e = starts[i + 1]
  if e then return text:sub(p, e - 2) end
  return text:sub(p)
end

--- 预计算每行的宽松签名
local function computeLineSigs(text, starts)
  local sigs = {}
  for i = 1, #starts do
    sigs[i] = lineSignature(lineAt(text, starts, i))
  end
  return sigs
end

--- 在 result 中按行签名找 searchLines 的宽松匹配窗口（忽略每行的缩进/空白差异），返回起止行号
local function fuzzyFindWindow(searchLines, resultSigs, resultCount)
  -- 跳过 search 首尾的空白行（上下文）
  local first, last = 1, #searchLines
  while first <= last and lineSignature(searchLines[first]) == "" do first = first + 1 end
  while last >= first and lineSignature(searchLines[last]) == "" do last = last - 1 end
  if first > last then return nil end

  local sigs = {}
  for i = first, last do sigs[#sigs + 1] = lineSignature(searchLines[i]) end

  for start = 1, resultCount do
    local matched = true
    for j = 1, #sigs do
      local ri = start + j - 1
      if ri > resultCount or resultSigs[ri] ~= sigs[j] then
        matched = false
        break
      end
    end
    if matched then
      return start, start + #sigs - 1
    end
  end
  return nil
end

--- 宽松整行替换：old 的行块在 text 中按行签名匹配后替换为 new（字面量替换失败时的回退）
function _M.fuzzyLineReplace(text, old, new, maxCount)
  local normalized = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  local count = 0
  while true do
    local starts = computeLineStarts(normalized)
    local l1, l2 = fuzzyFindWindow(splitLines(old), computeLineSigs(normalized, starts), #starts)
    if not l1 then break end
    local a = starts[l1]
    local b = starts[l2 + 1] and (starts[l2 + 1] - 2) or #normalized
    normalized = normalized:sub(1, a - 1) .. new .. normalized:sub(b + 1)
    count = count + 1
    if maxCount and maxCount > 0 and count >= maxCount then break end
  end
  if count == 0 then return nil, 0 end
  return normalized, count
end

local function applySearchReplace(original, patch)
  -- 统一行尾为 \n，避免 \r\n 差异导致匹配失败
  local result = original:gsub("\r\n", "\n"):gsub("\r", "\n")
  local applied = 0
  local locations = {}

  -- 逐个查找 SEARCH/REPLACE 块
  local pos = 1
  while true do
    local searchStart = patch:find("<<<<<<<%s*SEARCH", pos)
    if not searchStart then break end

    local separator = patch:find("=======", searchStart)
    if not separator then
      return nil, "缺少 ======= 分隔符"
    end

    local replaceEnd, replaceTail = patch:find(">>>>>>>%s*REPLACE", separator + 7)
    if not replaceEnd then
      return nil, "缺少 >>>>>>> REPLACE 结束标记"
    end

    -- 提取 SEARCH 和 REPLACE 内容（去掉首尾换行，统一 \n）
    local searchContent = patch:sub(searchStart, separator - 1)
    searchContent = searchContent:match("\n(.*)$") or ""
    searchContent = searchContent:gsub("\n$", "")
    searchContent = searchContent:gsub("\r\n", "\n"):gsub("\r", "\n")

    local replaceContent = patch:sub(separator + 7, replaceEnd - 1)
    replaceContent = replaceContent:match("^\n(.*)$") or replaceContent
    replaceContent = replaceContent:gsub("\n$", "")
    replaceContent = replaceContent:gsub("\r\n", "\n"):gsub("\r", "\n")

    -- 匹配策略：1) 精确  2) 去首尾空行的精确  3) 忽略空白差异的宽松匹配
    local foundStart, foundEnd = result:find(searchContent, 1, true)
    if not foundStart then
      local trimmed = searchContent:gsub("^%s*\n", ""):gsub("\n%s*$", "")
      if trimmed ~= "" then
        foundStart, foundEnd = result:find(trimmed, 1, true)
        if foundStart then searchContent = trimmed end
      end
    end
    if not foundStart then
      local starts = computeLineStarts(result)
      local l1, l2 = fuzzyFindWindow(splitLines(searchContent), computeLineSigs(result, starts), #starts)
      if l1 then
        foundStart = starts[l1]
        foundEnd = starts[l2 + 1] and (starts[l2 + 1] - 2) or #result
      end
    end
    if not foundStart then
      local hint = searchContextLines(result, searchContent)
      local extra = ""
      if hint ~= "" then extra = "\n\n" .. hint end
      return nil, "SEARCH 块未在文件中找到匹配:\n" .. searchContent:sub(1, 200) .. extra
    end

    local startLine = lineNumberAt(result, foundStart)
    local replaceLines = #splitLines(replaceContent)
    if replaceContent == "" then replaceLines = 0 end
    locations[#locations + 1] = {
      startLine = startLine,
      endLine = replaceLines == 0 and startLine or (startLine + replaceLines - 1),
    }
    result = result:sub(1, foundStart - 1) .. replaceContent .. result:sub(foundEnd + 1)
    applied = applied + 1
    -- 从本块 REPLACE 标记的精确结束位置继续扫描下一块。
    -- 历史 bug：固定 +20 会越过紧邻的下一块 SEARCH 标记（标记 15 字节 + 换行 1 字节），
    -- 导致多块补丁只应用第一块、后续块被静默丢弃。
    pos = (replaceTail or replaceEnd) + 1
  end

  if applied == 0 then
    return nil, "未找到有效的 SEARCH/REPLACE 块"
  end

  return result, applied, locations
end

--- 应用 Unified Diff
local function applyUnifiedDiff(original, patch)
  original = original:gsub("\r\n", "\n"):gsub("\r", "\n")
  local origLines = splitLines(original)
  local patchLines = splitLines(patch)
  local result = {}
  local origIdx = 1
  local locations = {}

  local i = 1
  while i <= #patchLines do
    local line = patchLines[i]

    -- 跳过文件头
    if line:match("^%-%-%-") or line:match("^%+%+%+") then
      i = i + 1

    -- hunk 头: @@ -old_start,old_len +new_start,new_len @@
    elseif line:match("^@@") then
      local oldStart = tonumber(line:match("@@ %-(%d+)")) or 1
      local newStart = tonumber(line:match("%+(%d+)")) or #result + 1
      -- 输出到 hunk 开始位置
      while origIdx < oldStart and origIdx <= #origLines do
        result[#result + 1] = origLines[origIdx]
        origIdx = origIdx + 1
      end
      i = i + 1

      local hunkStart = newStart
      local hunkEnd = newStart - 1
      -- 处理 hunk body
      while i <= #patchLines do
        local hline = patchLines[i]
        if hline:match("^@@") or hline:match("^%-%-%-") or hline:match("^%+%+%+") then
          break
        end
        if hline:match("^%+") then
          result[#result + 1] = hline:sub(2)
          hunkEnd = hunkEnd + 1
          i = i + 1
        elseif hline:match("^%-") then
          origIdx = origIdx + 1
          i = i + 1
        elseif hline:match("^ ") then
          result[#result + 1] = origLines[origIdx] or ""
          origIdx = origIdx + 1
          hunkEnd = hunkEnd + 1
          i = i + 1
        elseif hline == "" then
          -- 空行可能是 context
          i = i + 1
        else
          i = i + 1
        end
      end
      locations[#locations + 1] = {
        startLine = hunkStart,
        endLine = hunkEnd < hunkStart and hunkStart or hunkEnd,
      }
    else
      i = i + 1
    end
  end

  -- 复制剩余原始行
  while origIdx <= #origLines do
    result[#result + 1] = origLines[origIdx]
    origIdx = origIdx + 1
  end

  return table.concat(result, "\n"), math.max(1, #locations), locations
end

--- 主入口：自动判断格式并应用补丁
--- 返回 (newContent, appliedCount, locations) 或 (nil, err)
function _M.applyPatch(original, patch)
  -- 检测 SEARCH/REPLACE 格式
  if patch:find("<<<<<<<%s*SEARCH") then
    return applySearchReplace(original, patch)
  end

  -- 检测 Unified Diff 格式
  if patch:match("^%-%-%-") or patch:match("^@@") or patch:find("\n%-%-%-") then
    return applyUnifiedDiff(original, patch)
  end

  return nil, "无法识别补丁格式：需要 SEARCH/REPLACE 块或 Unified Diff"
end

--- 普通字符串替换（非模式匹配），替换所有出现或最多 count 次
--- 返回 (newText, count)；old 为空串时原样返回
function _M.plainReplace(text, old, new, maxCount)
  if old == "" then return text, 0 end
  local result = {}
  local pos = 1
  local count = 0
  while true do
    local s, e = text:find(old, pos, true)
    if not s then break end
    result[#result + 1] = text:sub(pos, s - 1)
    result[#result + 1] = new
    count = count + 1
    if maxCount and maxCount > 0 and count >= maxCount then
      result[#result + 1] = text:sub(e + 1)
      return table.concat(result), count
    end
    pos = e + 1
  end
  result[#result + 1] = text:sub(pos)
  return table.concat(result), count
end

return _M
