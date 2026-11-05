local modules = (ASSETS or "app/src/main/assets/") .. "templates/shared/modules/"
local function copy(t)
  local result = {}
  for k, v in pairs(t) do result[k] = v end
  return result
end
local function unchanged(t, before)
  for k, v in pairs(t) do assert(before[k] == v, "mutated global: " .. tostring(k)) end
  for k, v in pairs(before) do assert(t[k] == v, "removed global: " .. tostring(k)) end
end
local beforeString, beforeTable, beforeGlobals = copy(string), copy(table), copy(_G)
local oldPath = package.path
package.path = modules .. "?.lua;" .. oldPath
local S = require "Strings"
package.path = oldPath
unchanged(string, beforeString)
unchanged(table, beforeTable)
unchanged(_G, beforeGlobals)
assert(type(S) == "table" and require("Strings") == S)
local function equal(actual, expected)
  assert(#actual == #expected, "field count " .. #actual .. " expected " .. #expected)
  for i, value in ipairs(expected) do assert(actual[i] == value, "field " .. i .. ": " .. tostring(actual[i])) end
end
local text = "A😀中é"
assert(S.length(text) == 4 and S.len(text) == 4)
assert(S.charAt(text, 2) == "😀" and S.charAt(text, -1) == "é")
assert(S.charAt(text, 0) == "" and S.charAt(text, 5) == "")
assert(S.slice(text, 2, 3) == "😀中" and S.slice(text, -3, -2) == "😀中")
assert(S.slice(text, 1, 0) == "" and S.slice(text, 8) == "")
assert(S.codePointAt(text, 2) == 0x1F600 and S.codePointAt(text, 3) == 0x4E2D)
assert(S.codePointAt(text, -1) == 233 and S.codePointAt(text, 0) == nil)
assert(S.codePointBefore(text, 3) == 0x1F600 and S.codePointBefore(text, 1) == nil)
assert(S.codePointBefore(text, 5) == 233)
assert(S.codePointCount(text, 2, 3) == 2 and S.codePointCount(text, 3, 1) == 0)
equal(S.toCharArray(text), {"A", "😀", "中", "é"})
assert(S.length("é") == 2, "code points are not graphemes")
assert(S.contains("x.a%[", ".a%[") and not S.contains("abc", "."))
assert(S.startsWith("[a", "[") and S.endsWith("a$", "$"))
assert(S.startsWith(text, "") and S.endsWith(text, ""))
assert(not S.endsWith("a", "aa") and not S.startsWith("a", "aa"))
assert(S.removePrefix("[😀", "[") == "😀" and S.removeSuffix("😀$", "$") == "😀")
assert(S.removeSuffix(text, "") == text and S.removePrefix(text, "x") == text)
assert(S.count("😀😀😀", "😀😀") == 1 and S.count(text, "") == 5)
assert(S.count("a.a.", ".") == 2 and S.count("abc", "z") == 0)
for _, limit in ipairs({0, -1, 8}) do equal(S.split(",😀,,中,", ",", limit), {"", "😀", "", "中", ""}) end
equal(S.split("a.b.c", ".", 2), {"a", "b.c"})
equal(S.split("a,b,c", ",", 1), {"a,b,c"})
equal(S.split("a,,b,", ",", 2), {"a", ",b,"})
equal(S.split("", ","), {""})
equal(S.split("abc", "%s+"), {"abc"})
equal(S.split("a%sb", "%s"), {"a", "b"})
equal(S.split("😀中", ""), {"", "😀", "中", ""})
equal(S.split("😀中", "", 2), {"", "😀中"})
equal(S.split("", ""), {"", ""})
equal(S.splitPattern("😀  中\t末", "%s+", 2), {"😀", "中\t末"})
equal(S.splitPattern("😀中", ""), {"", "😀", "中", ""})
equal(S.splitPattern("abc", "$"), {"abc", ""})
equal(S.splitPattern("abc", "()", 3), {"", "a", "bc"})
equal(S.splitPattern("ab", "x*"), {"", "a", "b", ""})
equal(S.splitPattern("a,b", "(,)"), {"a", "b"})
assert(not pcall(S.split, "a", ",", 1.5))
assert(S.join("😀", {"a", "b"}) == "a😀b" and S.join("/", "a", "b") == "a/b")
assert(S.trim(" \t😀\r\n") == "😀" and S.isBlank("\v\f\t "))
assert(S.trim(" 😀 ") == " 😀 ", "NBSP is not ASCII whitespace")
assert(S.padStart("😀", 4, "中x") == "中x中😀")
assert(S.padEnd("😀", 4, "中x") == "😀中x中")
assert(S.center("😀", 4, ".") == ".😀..")
assert(S.padStart(text, 2) == text and not pcall(S.padEnd, "a", 3, ""))
assert(S.ellipsize(text, 3) == "A😀…" and S.ellipsize(text, 0) == "")
assert(S.ellipsize(text, 1, "😀😀") == "😀" and S.ellipsize(text, 8) == text)
equal(S.lines("😀\r\n中\r末\n"), {"😀", "中", "末", ""})
equal(S.lines(""), {""})
assert(S.equalsIgnoreCase("ÄBC", "äbc") and not S.equalsIgnoreCase("ß", "ss"))
assert(S.capitalize("éclair") == "Éclair" and S.capitalize("") == "")
assert(S.indent("a\nb", 2) == "  a\n  b" and S.expandTabs("a\tb", 2) == "a  b")
assert(S.transform(text, function(s) return S.length(s) end) == 4)
local legacy = copy(string)
assert(S.installLegacy(legacy) == legacy)
assert(legacy.len == beforeString.len and legacy.lower == beforeString.lower)
assert(legacy.length(text) == 4 and legacy.at(text, 2) == "😀")
assert(legacy["repeat"]("😀", 2) == "😀😀")
local env = setmetatable({luajava = {bindClass = function() error("no Java needed") end}}, {__index = _G})
local other = assert(loadfile(modules .. "Strings.lua", "t", env))()
assert(other ~= S and other.slice(text, 2, 2) == "😀")
legacy.slice = function() error("must be local") end
assert(other.slice(text, 2, 2) == "😀" and S.slice(text, 2, 2) == "😀")
unchanged(string, beforeString)
unchanged(table, beforeTable)
print("ALL-PASS TestTemplateStrings")
