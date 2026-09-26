--- override/dx 代理链路基准测试（仅真机可运行：运行时 dex 生成依赖 DexClassLoader）
---
--- 用法：把本文件复制到任意工程目录，在 IDE 里运行本文件。
---
--- 覆盖路径：
---   0) 环境冒烟：未代理实例方法调用（提前暴露环境级问题）
---   1) override 类生成（每次都是全新的 dex 编译，Enhancer.create）
---   2) 代理实例创建
---   3) superCall 派发：Lua → 拦截器 → Lua 回调 → super（MethodProxy/executeMethod 缓存路径）
---   4) Lua 回调返回 nil → 类型化默认值（boolean）
---   5) toString 身份回退（getDefaultObjectMethodResult）
---   6) 基线：未代理 luajava 直调
---
--- 注意：Java 成员调用一律使用点调用（冒号会把 self 作为额外参数传入）。
--- 对比旧实现时：回退 MethodProxy/MethodProxyExecuter/Enhancer 三个文件后重跑，
--- 差异集中在 3)（旧的每次 superCall 两次反射全表扫描 + setAccessible）。

local System = luajava.bindClass("java.lang.System")
local ArrayList = luajava.bindClass("java.util.ArrayList")

local function nano() return System.nanoTime() end
local function fmtMs(ns) return string.format("%8.2f ms", ns / 1e6) end
local function fmtOps(ns, n) return string.format("%12.0f ops/s", n / (ns / 1e9)) end

local results = {}
local function record(label, ns, n)
    results[#results + 1] = string.format("%-34s %10d 次  %s  %s", label, n, fmtMs(ns), fmtOps(ns, n))
end

-- 带异常隔离的测量段：单段失败不影响后续；
-- 报错输出完整多行文本（"Arguments provided / Available overloads" 是诊断关键）
local function section(name, n, fn)
    for _ = 1, math.min(2000, n) do pcall(fn) end
    local t0 = nano()
    local ok, err = pcall(function()
        for _ = 1, n do fn() end
    end)
    local dt = nano() - t0
    if ok then
        record(name, dt, n)
        return true
    end
    local full = tostring(err)
    print(("  ! %s 异常:\n%s"):format(name, full))
    results[#results + 1] = ("! %s: %s"):format(name, (full:gsub("\r", "")))
    return false
end

-- ── 0) 环境冒烟：最基础的对象 + 带参方法调用 ──
print("== 0) 环境冒烟 ==")
local raw = ArrayList()
local okSmoke, smokeErr = pcall(function()
    raw:add("x")
    assert(raw:size() == 1, "size != 1")
end)
if okSmoke then
    print("  未代理 add/size 正常")
else
    print("  !! 未代理调用失败（环境级问题，与 override 无关）:\n" .. tostring(smokeErr))
end
print("")

-- 1) 类生成：每次都是全新类名 + 全量 dx 编译
print("-- 1) 类生成（Enhancer.create：全量 dx 编译）--")
local genN = 5
local genTotal = 0
local cls
for i = 1, genN do
    local t0 = nano()
    cls = ArrayList.override {
        add = function(superCall, v) return superCall(v) end,
        clear = function(superCall) superCall() end,
        size = function(superCall) return superCall() end,
        isEmpty = function(superCall) return nil end,
    }
    local dt = nano() - t0
    genTotal = genTotal + dt
    print(("  第 %d 次: %s"):format(i, fmtMs(dt)))
end
print(("  生成平均: %s/类"):format(fmtMs(genTotal / genN)))
print("")

-- 2) 实例创建
print("-- 2) 代理实例创建 --")
local instN = 200
local t0 = nano()
local inst
for _ = 1, instN do inst = cls.newInstance() end
record("实例创建", nano() - t0, instN)
print("")

-- 3) superCall 派发（缓存收益的主要观测点）
print("-- 3) superCall 派发（add → 拦截器 → Lua → super）--")
local dispatchN = 20000
section("add + superCall", dispatchN, function() inst.add("x") end)

-- 4) Lua 回调返回 nil → 类型化默认值（boolean）
print("-- 4) Lua 返回 nil → 默认值路径 --")
section("isEmpty 返回 nil → false", 20000, function() inst.isEmpty() end)

-- 5) equals/hashCode/toString 身份回退
print("-- 5) 身份回退路径 --")
section("toString 身份回退", 20000, function() inst.toString() end)
section("hashCode 身份回退", 20000, function() inst.hashCode() end)

-- 6) 基线：未代理 luajava 直调
print("-- 6) 基线（未代理 luajava 直调）--")
section("未代理 ArrayList:add", 20000, function() raw.add("x") end)

-- 正确性抽查
print("")
print("== 正确性抽查 ==")
print("  代理 size:", tostring(inst.size()), "(期望 ≥ " .. dispatchN + 2000 .. ")")
print("  isEmpty 默认:", tostring(inst.isEmpty()), "(期望 false)")
print("  基线 size:", tostring(raw.size()))

print("")
print("== 汇总 ==")
for _, line in ipairs(results) do print(line) end
