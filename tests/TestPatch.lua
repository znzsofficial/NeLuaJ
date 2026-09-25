local ASSETS = ASSETS or "app/src/main/assets/"

-- PatchEngine 行为测试：纯模块，独立 LuaJ 运行时
local PE = assert(loadfile(ASSETS .. "mods/agent/PatchEngine.lua"))()

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("PASS  " .. name)
  else
    failures = failures + 1
    print("FAIL  " .. name .. (detail and ("  [" .. tostring(detail) .. "]") or ""))
  end
end

-- ── SEARCH/REPLACE ──

-- 1. 精确匹配
local r, cnt, locs = PE.applyPatch(
  "local a = 1\nlocal b = 2\nprint(a)\n",
  "<<<<<<< SEARCH\nlocal b = 2\n=======\nlocal b = 3\n>>>>>>> REPLACE")
check("sr exact applies", r == "local a = 1\nlocal b = 3\nprint(a)\n" and cnt == 1, r)
check("sr exact location", type(locs) == "table" and locs[1] and locs[1].startLine == 2 and locs[1].endLine == 2)

-- 2. 多块顺序应用
r, cnt, locs = PE.applyPatch(
  "alpha\nbeta\ngamma\n",
  "<<<<<<< SEARCH\nalpha\n=======\nALPHA\n>>>>>>> REPLACE\n<<<<<<< SEARCH\ngamma\n=======\nGAMMA\n>>>>>>> REPLACE")
check("sr multi block", r == "ALPHA\nbeta\nGAMMA\n" and cnt == 2, r)
check("sr multi locations", locs[1].startLine == 1 and locs[2].startLine == 3)

-- 3. SEARCH 首尾空行（模型常带空行上下文）
r, cnt = PE.applyPatch(
  "alpha\nbeta\n",
  "<<<<<<< SEARCH\n\nalpha\n\n=======\nALPHA\n>>>>>>> REPLACE")
check("sr blank-line padding", r == "ALPHA\nbeta\n" and cnt == 1, r)

-- 4. 宽松匹配：缩进差异
r, cnt = PE.applyPatch(
  "if x then\n    doSomething()\nend\n",
  "<<<<<<< SEARCH\nif x then\n  doSomething()\nend\n=======\nif x then\n  doSomethingNew()\nend\n>>>>>>> REPLACE")
check("sr fuzzy indent", r == "if x then\n  doSomethingNew()\nend\n" and cnt == 1, r)

-- 5. CRLF 原文（结果统一为 \n）
r, cnt = PE.applyPatch(
  "a\r\nb\r\n",
  "<<<<<<< SEARCH\na\n=======\nx\n>>>>>>> REPLACE")
check("sr crlf normalized", r == "x\nb\n" and cnt == 1, r)

-- 6. 空替换 = 字面删除（只删匹配字节，不吞行；删除整行应由模型带上下文行）
r, cnt = PE.applyPatch(
  "a\nb\nc\n",
  "<<<<<<< SEARCH\nb\n=======\n>>>>>>> REPLACE")
check("sr deletion literal", r == "a\n\nc\n" and cnt == 1, r)

-- 7. 未命中 → 错误 + 上下文提示
r, err = PE.applyPatch(
  "alpha\nbeta\n",
  "<<<<<<< SEARCH\nalpha\ngamma\n=======\nX\n>>>>>>> REPLACE")
check("sr miss returns error", r == nil and err and err:find("未在文件中找到匹配", 1, true) ~= nil, err)
check("sr miss hint lines", err and err:find("第 1 行: alpha", 1, true) ~= nil, err)

-- 8. 缺分隔符 / 缺结束标记
r, err = PE.applyPatch("a\n", "<<<<<<< SEARCH\na\n>>>>>>> REPLACE")
check("sr missing separator", r == nil and err and err:find("=======", 1, true) ~= nil, err)
r, err = PE.applyPatch("a\n", "<<<<<<< SEARCH\na\n=======\nb")
check("sr missing replace mark", r == nil and err and err:find("REPLACE", 1, true) ~= nil, err)

-- 9. 无有效块
r, err = PE.applyPatch("a\n", "只是一段普通文本")
check("sr no blocks", r == nil and err ~= nil)

-- ── Unified Diff ──

-- 10. 简单 hunk（带上下文行；原文行尾换行被保留）
r, cnt, locs = PE.applyPatch(
  "a\nb\nc\nd\ne\n",
  "--- f.lua\n+++ f.lua\n@@ -1,5 +1,5 @@\n a\n-b\n+B\n c\n d\n e")
check("ud simple hunk", r == "a\nB\nc\nd\ne\n" and cnt >= 1, r)

-- 11. 多 hunk
r = (PE.applyPatch(
  "a\nb\nc\nd\ne\nf\n",
  "--- f\n+++ f\n@@ -1,2 +1,2 @@\n a\n-b\n+B\n@@ -5,2 +5,2 @@\n e\n-f\n+F"))
check("ud multi hunk", r == "a\nB\nc\nd\ne\nF\n", r)

-- 11b. 原文无行尾换行时结果也不引入
r = (PE.applyPatch(
  "a\nb\nc",
  "--- f\n+++ f\n@@ -1,3 +1,3 @@\n a\n-b\n+B\n c"))
check("ud no trailing nl preserved", r == "a\nB\nc", r)

-- ── 格式识别 ──

-- 12. 未知格式
r, err = PE.applyPatch("a\n", "???")
check("unknown format", r == nil and err and err:find("无法识别", 1, true) ~= nil, err)

-- ── plainReplace ──

local t, c = PE.plainReplace("aXbXc", "X", "Y")
check("pr replace all", t == "aYbYc" and c == 2)
t, c = PE.plainReplace("aXbXc", "X", "Y", 1)
check("pr maxCount", t == "aYbXc" and c == 1)
t, c = PE.plainReplace("abc", "", "Y")
check("pr empty old noop", t == "abc" and c == 0)
t, c = PE.plainReplace("abc", "z", "Y")
check("pr no match", t == "abc" and c == 0)

-- ── fuzzyLineReplace ──

t, c = PE.fuzzyLineReplace("  foo()\nbar\n", "foo()", "foo(1)")
check("flr indent-insensitive", t == "foo(1)\nbar\n" and c == 1, t)
t, c = PE.fuzzyLineReplace("a\nb\na\n", "a", "Z")
check("flr all occurrences", t == "Z\nb\nZ\n" and c == 2, t)
t, c = PE.fuzzyLineReplace("a\nb\n", "a", "Z", 1)
check("flr maxCount", t == "Z\nb\n" and c == 1, t)
t, c = PE.fuzzyLineReplace("a\nb\n", "nomatch", "Z")
check("flr no match", t == nil and c == 0)

-- ── formatPatchLocations ──

check("loc format single", PE.formatPatchLocations({ { startLine = 2, endLine = 2 } }) == "L2")
check("loc format range", PE.formatPatchLocations({ { startLine = 2, endLine = 2 }, { startLine = 5, endLine = 7 } }) == "L2, L5-7")
check("loc format empty", PE.formatPatchLocations({}) == "")

if failures == 0 then print("ALL-PASS") else print("FAILURES: " .. failures) end
