# 可选 Lua 工具 / Optional Lua utilities

本工程只包含创建时勾选的模块。下面的示例需要对应模块文件存在。
Only selected modules are copied into this project. Examples require their respective files.

Array、Strings、TimeMeter 和 ObjectAnimator 都返回模块表；普通 require 不安装全局名称，
也不改写 Lua 标准库。Java 方法使用点调用，计时器等 Lua 对象按示例使用冒号调用。
Require returns an API table. These four modules do not patch globals or standard libraries on import.

## Array：Java 类型数组

```lua
local Array = require "mods.Array"
local numbers = Array.from("int", { 1, 2, 3 })
local names = Array.of("java.lang.String", "Ada", nil, "Lin")
local values = Array.toTable(names)
print(values.n) -- 3; nil 槽位不会导致长度信息丢失
local empty = Array.new("java.lang.String", 4)
```

Java 数组下标从 0 开始，Lua 表下标从 1 开始。`toTable` 返回带 `n` 的 packed table，
用 `for i = 1, values.n` 遍历含 null 的数组，不能用 `ipairs`。
类型可传 Java Class、类全名或 `int`/`float` 等基本类型名。基本类型不能写入 nil。
Repeated class-name resolution is cached; packed tables preserve null slots with an explicit `n`.

旧代码可显式调用 `Array.installLegacy()` 安装 `arrayOf` 和 `arrayOfNulls`，
新代码推荐上面的模块接口。

## TimeMeter：独立、单调计时

```lua
local TimeMeter = require "mods.TimeMeter"
local timer = TimeMeter.new()
local ns, result = timer:measure(function(value)
  return value * value
end, 12)
print(ns / 1000000, result) -- 毫秒、144
local lapNs = timer:lap()
local totalNs = timer:elapsed()
timer:reset()
```

每个实例独立保存起点与检查点。`measure` 返回纳秒耗时及原函数全部返回值（包括 nil），
不自动打印；原函数错误向调用方传播。`lap` 返回距上一检查点的耗时，`elapsed` 返回
当前时刻距起点的耗时；两者都使用单调时钟。
Each timer has independent state. All durations are nanoseconds; divide by 1,000,000 for milliseconds.

旧 `TimeMeter(callback)`、`record`、`callAndCount` 保留回调行为；默认回调打印毫秒，
`callAndCount` 只返回耗时。`getTotalTime` 是最后检查点距起点的耗时，不等同于实时 `elapsed`。

## Strings：显式 Unicode 文本操作

```lua
local Strings = require "mods.Strings"
local fields = Strings.split("甲,,乙,丙", ",", 3) -- {"甲", "", "乙,丙"}
local chars = Strings.slice("你好世界", 2, 3) -- "好世"
local words = Strings.splitPattern("one  two", "%s+")
```

字符位置是从 1 开始的 Unicode 码点位置（不是字节或 UTF-16 单元），支持负索引；
slice 末端包含在结果中。表情组合/字素簇可能包含多个码点。
`contains/startsWith/endsWith/split` 按字面量匹配；Lua pattern 需显式调用 `splitPattern`。
split 保留空字段，正 limit 的最后一项保留未拆分余串；0/负 limit 不限次数。
旧工程迁移需要注意：以前隐式覆盖 string 的行为已取消，原先丢空字段的 split 行为也已修正。
若仍需字符串方法形式，显式调用 `Strings.installLegacy()`；标准 `string.len/find/gsub` 等保持原义。

常用格式化包括 `trim`、`padStart/padEnd`、`ellipsize`、`lines`、`join`。
大小写转换不是完整 Unicode case folding，不适合作为安全标识符归一化方法。

## ObjectAnimator

```lua
local Animator = require "mods.ObjectAnimator"
local fade = Animator.float(view, "alpha", { 0, 1 }, { duration = 200 })
fade.start()
-- 离开页面时按应用自己的生命周期管理：fade.cancel()
```

提供 `float/int/argb/objects/path/pointF/propertyValues` 和 `create(config)`；默认仅创建，
显式 `start()` 或 `start = true` 才播放。毫秒用于 duration/startDelay，
颜色采用有符号 32 位整数。`objects` 要求 TypeEvaluator。
点路径只使用公开 Android API，不依赖 AndroidX 内部 ObjectAnimatorUtils。

支持明确的旧配置调用适配；拒绝未知参数与冲突参数，不再通过 pairs 顺序随机应用配置。
`durationScale/frameDelay` 是进程全局设置，模块拒绝它们；多维动画可通过原生 `ofMultiFloat/ofMultiInt`
构造入口显式调用，不做不可靠的重载推断。模块不接管 Activity 生命周期，调用方管理动画取消。
See the module header for exact signatures and supported legacy payloads.

## RxLua 与 vConsole

- RxLua：`local rx = require "mods.rx"`，沿用原模块 API。
- vConsole：生成器已在入口追加 `require "vConsole"`。它是独立调试面板，会接入日志钩子，
  与上述纯工具模块不同。发布前按需要取消勾选或移除调用。

模板更新不会自动改写已创建工程的工具文件。迁移旧工程时先检查使用方式，再替换选中的模块。
Existing project files are never upgraded automatically; review callers before replacing old utilities.
