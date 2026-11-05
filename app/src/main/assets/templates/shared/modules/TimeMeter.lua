-- Monotonic nanoseconds; requiring does not print or install globals.
-- local TimeMeter = require "mods.TimeMeter"
-- local meter = TimeMeter.new() -- fresh start and independent points
-- meter:lap(); meter:elapsed(); meter:reset()
-- local ns, first, second = meter:measure(function() return "ok", nil end)
-- measure preserves all results, never prints, and propagates errors unchanged.
-- TimeMeter.measure(fn, ...) and TimeMeter:measure(fn, ...) also work.
-- new({clock=fn}) accepts an optional monotonic nanosecond clock for tests.
-- Compatibility: TimeMeter(callback), :newInstance(callback), :record(),
-- :getTotalTime(), and callAndCount(fn, ...) retain nanosecond callbacks.
-- Only record/callAndCount use callback (default: print milliseconds).
local nanoTime = luajava.bindClass("java.lang.System").nanoTime
local M = {}
local function defaultCallback(ns) print(tostring(ns / 1000000) .. " ms") end
M.callback = defaultCallback
M.clock = nanoTime

local function receiver(self)
  return self or M
end

function M.reset(self)
  self = receiver(self)
  local now = self.clock()
  self.points = { now }
  self.start = now
  return self
end

function M.new(options, colonOptions)
  if options == M then options = colonOptions end
  options = options or {}
  assert(type(options) == "table", "Expected timer options")
  local clock = options.clock or nanoTime
  local callback = options.callback or defaultCallback
  assert(type(clock) == "function", "Expected a clock function")
  assert(type(callback) == "function", "Expected a callback function")
  return M.reset(setmetatable({ clock = clock, callback = callback }, { __index = M }))
end

function M.newInstance(self, callback)
  if type(self) == "function" then callback, self = self, M end
  self = receiver(self)
  return M.new({ clock = self.clock, callback = callback or self.callback })
end

function M.addPoint(self)
  self = receiver(self)
  local now = self.clock()
  self.points[#self.points + 1] = now
  return now
end

function M.lap(self)
  self = receiver(self)
  local previous = self.points[#self.points]
  return self:addPoint() - previous
end

function M.elapsed(self)
  self = receiver(self)
  return self.clock() - self.start
end

function M.record(self)
  self = receiver(self)
  local ns = self:lap()
  self.callback(ns)
  return ns
end

function M.getTotalTime(self)
  self = receiver(self)
  return self.points[#self.points] - self.start
end

local function measure(self, fn, ...)
  assert(type(fn) == "function", "Expected a function to measure")
  local start = self.clock()
  local results = table.pack(fn(...))
  local duration = self.clock() - start
  return duration, table.unpack(results, 1, results.n)
end

function M.measure(self, ...)
  if type(self) == "function" then return measure(M, self, ...) end
  assert(type(self) == "table", "Expected a function to measure")
  return measure(self, ...)
end

local function callAndCount(self, fn, ...)
  local duration = measure(self, fn, ...)
  self.callback(duration)
  return duration
end

function M.callAndCount(self, ...)
  if type(self) == "function" then return callAndCount(M, self, ...) end
  assert(type(self) == "table", "Expected a function to measure")
  return callAndCount(self, ...)
end

M:reset()
return setmetatable(M, { __call = function(_, callback)
  return M:newInstance(callback)
end })
