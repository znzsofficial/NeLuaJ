local ASSETS = ASSETS or "app/src/main/assets/"

-- TextUtil 行为测试：纯模块，独立 LuaJ 运行时
local TU = assert(loadfile(ASSETS .. "mods/utils/TextUtil.lua"))()

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("PASS  " .. name)
  else
    failures = failures + 1
    print("FAIL  " .. name .. (detail ~= nil and ("  [" .. tostring(detail) .. "]") or ""))
  end
end

-- utf8Cap
check("cap short passthrough", TU.utf8Cap("abc", 10) == "abc")
check("cap ascii truncation", TU.utf8Cap("abcdef", 4) == "abcd")
check("cap utf8 whole chars", TU.utf8Cap(string.rep("好", 100), 10) == string.rep("好", 3))
check("cap utf8 boundary lead stripped", TU.utf8Cap("a" .. string.rep("好", 30), 4) == "a")
check("cap empty", TU.utf8Cap("", 5) == "")
check("cap nil safe", TU.utf8Cap(nil, 5) == "")

-- fmtTokens
check("fmt small", TU.fmtTokens(0) == "0")
check("fmt hundreds", TU.fmtTokens(999) == "999")
check("fmt k boundary", TU.fmtTokens(1000) == "1k")
check("fmt k floor", TU.fmtTokens(1234) == "1k")
check("fmt k round", TU.fmtTokens(999999) == "999k")
check("fmt m", TU.fmtTokens(1500000) == "1.5M")
check("fmt nil safe", TU.fmtTokens(nil) == "0")

if failures == 0 then print("ALL-PASS") else print("FAILURES: " .. failures) end
