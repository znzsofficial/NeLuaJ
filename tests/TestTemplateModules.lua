local assets = ASSETS or "app/src/main/assets/"
local modules = assets .. "templates/shared/modules/"

-- Use the runtime's real UTF-8 functions, but replace Java's clock so elapsed
-- durations and Java dot-call conventions are checked deterministically.
local now = 10000000
local clockCalls = 0
local output = {}
local env = setmetatable({
  luajava = { bindClass = function(name)
    assert(name == "java.lang.System")
    return { nanoTime = function(...)
      assert(select("#", ...) == 0, "Java methods must use dot calls")
      clockCalls = clockCalls + 1
      return now
    end }
  end },
  print = function(text) output[#output + 1] = text end,
}, { __index = _G })
local TimeMeter = assert(loadfile(modules .. "TimeMeter.lua", "t", env))()
local ran = 0
local function work()
  ran = ran + 1
  now = now + 2500000
  return "ignored", 42
end
local duration, extra = TimeMeter.callAndCount(work)
assert(duration == 2500000 and extra == nil and ran == 1)
assert(tonumber(output[1]:match("^(.-) ms$")) == 2.5, "nanoseconds must display as milliseconds")

local reported = {}
local meter = TimeMeter(function(value) reported[#reported + 1] = value end)
assert(meter:callAndCount(work) == 2500000)
assert(reported[1] == 2500000 and #output == 1)
assert(TimeMeter:callAndCount(work) == 2500000, "module colon call")
assert(meter.callAndCount(work) == 2500000, "unbound dot call uses module callback")
assert(#reported == 1 and #output == 3)

local failure = {}
local before = clockCalls
local ok, err = pcall(function()
  meter:callAndCount(function() error(failure) end)
end)
assert(not ok and err == failure)
assert(clockCalls == before + 1 and #reported == 1, "failed work must not report completion")
local brokenCallback = TimeMeter(function() error(failure) end)
ok, err = pcall(function() brokenCallback:callAndCount(work) end)
assert(not ok and err == failure, "callback errors must propagate")
before = clockCalls
assert(not pcall(TimeMeter.callAndCount, "invalid"))
assert(clockCalls == before, "reject invalid work before starting the clock")

-- Keep Strings' global extensions local to this test environment.
local strings = {}
for key, value in pairs(string) do strings[key] = value end
local tables = {}
for key, value in pairs(table) do tables[key] = value end
local stringsEnv = setmetatable({ string = strings, table = tables }, { __index = _G })
local Strings = assert(loadfile(modules .. "Strings.lua", "t", stringsEnv))()
Strings.installLegacy(strings)
local function splitEquals(text, delimiter, limit, expected)
  local actual = strings.split(text, delimiter, limit)
  assert(#actual == #expected, "split segment count: " .. text .. " limit=" .. tostring(limit))
  for i, value in ipairs(expected) do
    assert(actual[i] == value, "split segment " .. i .. ": " .. tostring(actual[i]))
  end
end
for _, text in ipairs({ "a,b,c", "甲,乙,丙" }) do
  local a, b, c = utf8.match(text, "([^,]+),([^,]+),([^,]+)")
  splitEquals(text, ",", 1, { text })
  splitEquals(text, ",", 2, { a, b .. "," .. c })
  splitEquals(text, ",", 0, { a, b, c })
  splitEquals(text, ",", -1, { a, b, c })
  splitEquals(text, ",", nil, { a, b, c })
  splitEquals(text, ",", 4, { a, b, c })
end
splitEquals("甲界乙界丙", "界", 2, { "甲", "乙界丙" })
local patterned = Strings.splitPattern("甲 乙 丙", "%s+", 2)
assert(patterned[1] == "甲" and patterned[2] == "乙 丙")
splitEquals("甲乙", ",", 2, { "甲乙" })
splitEquals("", ",", 2, { "" })
-- The explicit module preserves empty fields instead of silently losing data.
splitEquals("a,,b,", ",", 0, { "a", "", "b", "" })
splitEquals("a,,b,", ",", -1, { "a", "", "b", "" })
splitEquals("a,,b,", ",", 2, { "a", ",b," })
print("ALL-PASS TestTemplateModules")
