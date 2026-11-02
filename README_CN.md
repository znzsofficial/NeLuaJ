<div align="center">

# NeLuaJ+

[![Android CI](https://github.com/znzsofficial/NeLuaJ/actions/workflows/android.yml/badge.svg)](https://github.com/znzsofficial/NeLuaJ/actions/workflows/android.yml)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android-green)](https://developer.android.com)

**AI 加持的 Android Lua IDE**

[English](README.md) | [简体中文](README_CN.md)

</div>

<br>

**NeLuaJ+** 是一个在手机上用 Lua 构建 Android 应用的 IDE，并把 AI 编码代理内建进了开发流程。用 Lua 表声明式写界面、在设备上直接运行，还有一个面向当前工程的智能体，能随你一起读写、打补丁、搜索、运行乃至打包代码。

## ✨ 核心亮点

### 🤖 内建 AI 代理（`mods/agent`）

- **带真实工具的代理循环** —— `AgentTurn` 驱动文件操作、补丁、搜索、布局查询、运行和构建器交接。工具轮数默认不限，可配置上限；完整清单以[工具注册表](./app/src/main/assets/mods/agent/ToolRegistry.lua)为准。
- **并行读取与任务委托** —— 符合条件的只读工具批量并发；`run_subtask` 同时运行一个隔离子任务。文件变更通常需要确认，可配置工程内自动批准；MCP 工具当前不经确认执行，只连接可信服务器。
- **安全的代码执行** —— 模型生成的 Lua 跑在独立的 `:lua_sandbox` 进程里：无文件系统与 Android 访问、严格超时、白名单 HTTPS 出口；公开网页读取也经加固的只许公网的抓取器。
- **可恢复的文件变更** —— 支持的文件工具由 `ChangeSet` 保存快照，进行 fingerprint 冲突检测和按工程撤销/恢复；多路径恢复失败时尝试回滚，不是整个文件系统的事务，也不能替代备份。
- **上下文自我管理** —— 按模型上下文窗口自动压缩历史、待办计划注入提示词、本地 `SKILL.md` 技能，以及供廉价任务（标题、压缩、轻量子代理）使用的**辅助模型路由**。
- **MCP 支持** —— 经 Streamable HTTP 挂载外部 MCP 服务器，一键 `context7` / `deepwiki` 预设，单服务器连接测试。
- **会话工作台** —— 会话按工程持久化、自动生成标题、按会话的 token 用量、面板内搜索、导出、重新生成 / 编辑重发，以及带表格的 Markdown 渲染。详见 [docs/AIAgent.md](./docs/AIAgent.md)。

### ☕ 超越原版 LuaJ 的 Java 互操作

- **行为像 Java 对象的代理** —— 单方法接口直接用函数实现（`Runnable(function() ... end)`）；`luajava.createProxy(...)` 一个代理组合多个接口；`override` 只继承 Java **类**（传入接口会直接报错，应改用 `createProxy`）。被覆写方法的第一个参数是调用原实现的 `superCall`。Java 成员用点调用，冒号会把 `self` 当成额外参数，重载会选错。原始返回值按种类拆箱（`Boolean` / `Character` / `Number`），Lua 返回 `nil` 时变成类型化零值，而不是错误的强制转换。代理默认获得 Java 语义的 `equals` / `hashCode` / `toString`，可安全放进 `HashMap` 等容器。
- **确定性的成员选择** —— 重载评分有歧义时，`luajava.constructor` / `luajava.method` 按精确 public 参数类型选择成员；自动数值评分基于完整 64 位 Lua 整数判断范围，`byte` / `short` / `char` / `int` 重载按值而非截断结果胜出。
- **Kotlin 优先的桥接，不依赖 kotlin-reflect** —— `luajava.kotlinObject` / `luajava.kotlinCompanion` 访问 Kotlin `object` 与 companion 单例；`@JvmStatic` 成员可从 `bindClass` 直接调用。Java 与 Kotlin 成员统一使用点调用。
- **集合是一等公民** —— `luajava.iterate` 支持数组、`Map`、`Iterable` / `Iterator` 与 Kotlin `Sequence` 的泛型 `for` 遍历；`#` 对 Map 和所有集合生效；`luajava.toTable` / `toList` / `toSet` / `toMap` 在 Lua 表与 Java 容器间转换。
- **插件安全的动态加载** —— `loadDex` / `loadJar` 的类经 loader 感知缓存解析（`JavaClass` 以 `Class<?>` 为键、弱引用持有，loader 变更时失效包缓存），不同 `DexClassLoader` 的同名类相互独立，卸载的工程可被正常回收。
- **桥接层在项目源码内维护** —— 关键 `org.luaj.lib.jse` 桥接类在构建时由项目源码接管，UTF-8 正确的字符串内部实现、协程驱动的 `xTask`，均有本地单元测试回归。详见 [docs/LuaJRuntime.md](./docs/LuaJRuntime.md)。

```lua
import "java.lang.Runnable"
import "java.util.ArrayList"

-- 单方法接口用普通函数实现
local r = Runnable(function() print("run") end)

-- 继承 Java 类；superCall 调用原实现
local List = ArrayList.override {
  add = function(superCall, v)
    print("add:", v)
    return superCall(v)
  end,
}

-- 泛型 for 遍历 Java 容器
local items = ArrayList()
items.add("Hello")
for i, item in luajava.iterate(items) do
  print(i, item)
end
```

### 🧪 工程化

- `pwsh -File tests/run_tests.ps1` 自动发现桌面 Lua 套件，JVM 单测通过 Gradle 运行。数量以运行输出为准，不在 README 手写；详见[测试说明](./tests/README.md)。
- CI 执行文档/runner 检查、Lua 和 JVM 测试、运行时 JAR 接管校验及 Debug/Release 构建。构建通过不等于 Android 渲染或生命周期已经验收。

### 首页与工程工作流

按应用名、目录名或包名搜索工程，从实际打开记录继续开发，打开已有工程目录，或创建工程后进入 `main.lua`。会话列表读取元数据并按工程跳转；首页按可用宽度切换原生底栏与导航轨。见[首页指南](./app/src/main/assets/res/doc/home_zh.html)及[实现边界](./docs/HOME.md)。

## 🛠️ 快速开始

使用 JDK 17 和仓库内 Gradle wrapper。当前源码以 Android SDK 37 编译、target API 33，设备最低支持 API 26，三者含义不同；Android Studio 需兼容仓库锁定的插件版本。环境、验证、版本号与签名边界见[构建说明](./docs/BUILDING.md)。

```bash
git clone https://github.com/znzsofficial/NeLuaJ.git
cd NeLuaJ
./gradlew :app:assembleDebug
```

要把 Lua 工程打包成独立 APK，请使用配套构建器：[NeLuaJ-Builder](https://github.com/znzsofficial/NeLuaJ-Builder)。IDE ⇄ 构建器的交接协议见 [docs/BuilderHandoff.md](./docs/BuilderHandoff.md)。

## 📝 Hello World

```lua
import "android.widget.*"

local layout = {
  LinearLayout,
  orientation = "vertical",
  layout_width = "match_parent",
  layout_height = "match_parent",
  gravity = "center",
  {
    TextView,
    text = "Hello, NeLuaJ+!",
    textSize = "24sp",
  },
  {
    Button,
    text = "点我",
    onClick = function()
      print("Clicked!")
    end,
  },
}

activity.setContentView(loadlayout(layout))
```

Lua 运行时保留了熟悉的声明式开发体验——`loadlayout`、`luajava` 桥接、`task` / `thread` / `timer`、`okHttp`、`json`、动态 dex 加载——文档见 [docs/LuaJRuntime.md](./docs/LuaJRuntime.md)、[docs/LuaActivity.md](./docs/LuaActivity.md) 与 [docs/LuaLayout.md](./docs/LuaLayout.md)。

## 📚 文档

- **先从这里开始：**[文档总索引](./docs/README.md) · [源码构建](./docs/BUILDING.md)。
- **使用 IDE / 编写 Lua 应用：**[首页指南](./app/src/main/assets/res/doc/home_zh.html) · [应用内 API 文档目录](./app/src/main/assets/res/doc/agent_docs.md)。
- **维护项目：**[维护约束](./docs/MAINTENANCE.md) · [测试说明](./tests/README.md) · [设备验收](./docs/HOME_VALIDATION.md)。
- **实现说明：**[首页与编辑器](./docs/HOME.md) · [Agent](./docs/AIAgent.md) · [运行时](./docs/LuaJRuntime.md) · [Activity](./docs/LuaActivity.md) · [布局](./docs/LuaLayout.md) · [构建器交接](./docs/BuilderHandoff.md)。
- **历史背景：**[历史设计与记录](./docs/README.md#历史设计与记录)，不作为当前能力保证。

仓库维护文档以中文为主，应用内指南按目录提供中英文版本。HTML 文档可在应用的帮助页或本地浏览器阅读；GitHub 链接可能显示源码而非渲染页面。

`tests/bench_override.lua` 是仅真机可运行的 override/dx 基准。桌面 JVM 能生成 dex 字节，但不能加载。

## 📄 许可证

本项目基于 [Apache License 2.0](LICENSE) 开源。

---
**注**：项目处于活跃开发中，API 可能随版本变化；请以源码与上述文档为准。
