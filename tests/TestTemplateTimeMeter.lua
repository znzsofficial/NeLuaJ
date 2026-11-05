local modules = (ASSETS or "app/src/main/assets/") .. "templates/shared/modules/"
local now, reads, binds, prints = 100, 0, 0, 0
local env = setmetatable({
  luajava = { bindClass = function(name)
    assert(name == "java.lang.System")
    binds = binds + 1
    return { nanoTime = function(...)
      assert(select("#", ...) == 0, "clock uses Java dot semantics")
      reads = reads + 1
      return now
    end }
  end },
  print = function() prints = prints + 1 end,
}, { __index = _G })
local Timer = assert(loadfile(modules .. "TimeMeter.lua", "t", env))()
assert(binds == 1 and prints == 0)
now = 150
local a = Timer.new()
now = 200
local b = Timer:new()
assert(a.start == 150 and b.start == 200 and Timer.start == 100)
assert(a.points ~= b.points and a.points ~= Timer.points)
now = 225
assert(a:lap() == 75 and #a.points == 2 and #b.points == 1)
now = 240
assert(a:elapsed() == 90 and b:elapsed() == 40)
assert(a:getTotalTime() == 75)
assert(a:reset() == a and a.start == 240 and #a.points == 1)
assert(b.start == 200 and Timer.start == 100)
local results = table.pack(a:measure(function(x, y, z)
  assert(x == "arg" and y == nil and z == 3)
  now = now + 10
  return "first", nil, "third", nil
end, "arg", nil, 3))
assert(results.n == 5 and results[1] == 10 and results[2] == "first")
assert(results[3] == nil and results[4] == "third" and results[5] == nil)
assert(#a.points == 1 and prints == 0)
local function work() now = now + 5 end
assert(table.pack(Timer.measure(work)).n == 1)
assert(Timer:measure(work) == 5)
assert(a.measure(work) == 5, "unbound dot uses module timer")
local reported = {}
local c = Timer(function(ns) reported[#reported + 1] = ns end)
assert(c:callAndCount(work) == 5 and reported[1] == 5)
local clone = c:newInstance()
assert(clone.points ~= c.points and clone.start == now)
assert(clone.callback == c.callback)
now = now + 7
assert(clone:record() == 7 and reported[2] == 7)
local failure = {}
local before = reads
local ok, err = pcall(function() c:measure(function() error(failure) end) end)
assert(not ok and err == failure and reads == before + 1 and #reported == 2)
before = reads
assert(not pcall(function() c:measure(false) end) and reads == before)
local injectedNow = 1
local injected = Timer.new({clock = function() return injectedNow end})
injectedNow = 6
assert(injected:elapsed() == 5 and injected:lap() == 5)
assert(reads == before, "injected clocks are isolated")
assert(prints == 0 and binds == 1)
-- Smoke test the actual bridge's bound nanoTime function, not just the fake.
local RealTimer = assert(loadfile(modules .. "TimeMeter.lua"))()
local real = RealTimer.new()
assert(real:elapsed() >= 0 and real:measure(function() end) >= 0)
print("ALL-PASS TestTemplateTimeMeter")
