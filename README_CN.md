<div align="center">

# NeLuaJ+

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/znzsofficial/NeLuaJ)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android-green)](https://developer.android.com)

**AI 加持的 Android Lua IDE**

[English](README.md) | [简体中文](README_CN.md)

</div>

<br>

**NeLuaJ+** 是一个在手机上用 Lua 构建 Android 应用的 IDE，并把 AI 编码代理内建进了开发流程。用 Lua 表声明式写界面、在设备上直接运行，还有一个面向当前工程的智能体，能随你一起读写、打补丁、搜索、运行乃至打包代码。

## ✨ 核心亮点

### 🤖 内建 AI 代理（`mods/agent`）

- **带真实工具的代理循环** —— 20 个内置工具跑在 `AgentTurn` 回合状态机上（generation 守卫、无硬上限工具循环）：文件读写、多格式**补丁引擎**（search-replace / 统一 diff / 整文件替换）、工程内搜索、工程运行器，以及把工程打包成 APK 的**构建器交接**。
- **并行与委托执行** —— 只读工具批量并发；`run_subtask` 派生隔离子代理并展示实时进度卡；破坏性操作需显式确认。
- **安全的代码执行** —— 模型生成的 Lua 跑在独立的 `:lua_sandbox` 进程里：无文件系统与 Android 访问、严格超时、白名单 HTTPS 出口；公开网页读取也经加固的只许公网的抓取器。
- **文件变更是事务** —— 每次修改都被 `ChangeSet` 快照，带 fingerprint 冲突检测、按工程的撤销/恢复，以及部分失败时的回滚。
- **上下文自我管理** —— 按模型上下文窗口自动压缩历史、待办计划注入提示词、本地 `SKILL.md` 技能，以及供廉价任务（标题、压缩、轻量子代理）使用的**辅助模型路由**。
- **MCP 支持** —— 经 Streamable HTTP 挂载外部 MCP 服务器，一键 `context7` / `deepwiki` 预设，单服务器连接测试。
- **会话工作台** —— 会话按工程持久化、自动生成标题、按会话的 token 用量、面板内搜索、导出、重新生成 / 编辑重发，以及带表格的 Markdown 渲染。详见 [docs/AIAgent.md](./docs/AIAgent.md)。

### ☕ 超越原版 LuaJ 的 Java 互操作

- **行为像 Java 对象的代理** —— 单方法接口直接用函数实现（`Runnable(function() ... end)`）；`luajava.createProxy(...)` 一个代理组合多个接口；`override` 可继承 Java 类，被覆写方法的第一个参数是调用原实现的 `superCall`。代理默认获得 Java 语义的 `equals` / `hashCode` / `toString`，可安全放进 `HashMap` 等容器。
- **确定性的成员选择** —— 重载评分有歧义时，`luajava.constructor` / `luajava.method` 按精确 public 参数类型选择成员；自动数值评分基于完整 64 位 Lua 整数判断范围，`byte` / `short` / `char` / `int` 重载按值而非截断结果胜出。
- **Kotlin 优先的桥接，不依赖 kotlin-reflect** —— `luajava.kotlinObject` / `luajava.kotlinCompanion` 访问 Kotlin `object` 与 companion 单例；`@JvmStatic` 成员可从 `bindClass` 直接调用。Java 与 Kotlin 成员统一使用点调用。
- **集合是一等公民** —— `luajava.iterate` 支持数组、`Map`、`Iterable` / `Iterator` 与 Kotlin `Sequence` 的泛型 `for` 遍历；`#` 对 Map 和所有集合生效；`luajava.toTable` / `toList` / `toSet` / `toMap` 在 Lua 表与 Java 容器间转换。
- **插件安全的动态加载** —— `loadDex` / `loadJar` 的类经 loader 感知缓存解析（`JavaClass` 以 `Class<?>` 为键、弱引用持有，loader 变更时失效包缓存），不同 `DexClassLoader` 的同名类相互独立，卸载的工程可被正常回收。
- **桥接层在项目源码内维护** —— 关键 `org.luaj.lib.jse` 桥接类在构建时由项目源码接管，UTF-8 正确的字符串内部实现、协程驱动的 `xTask`，均有本地单元测试回归。详见 [docs/LuaJRuntime.md](./docs/LuaJRuntime.md)。

```lua
import "java.lang.Runnable"

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
for i, item in luajava.iterate(someJavaList) do
  print(i, item)
end
```

### 🧪 工程化

- **Lua 代码库的 JVM 行为测试**：8 个套件 / 200+ 断言，桌面端 `.\tests\run_tests.ps1` 直接运行，无需设备。方法论与套件清单见 [tests/README.md](./tests/README.md)。
- Lua 改动过 **LuaC 语法门禁**；Kotlin 层由 Gradle 构建验证。

## 🛠️ 快速开始

环境要求：Android Studio Ladybug 及以上、JDK 17+、Android SDK 33+。

```bash
git clone https://github.com/znzsofficial/NeLuaJ.git
cd NeLuaJ
./gradlew assembleRelease
```

要把 Lua 工程打包成独立 APK，请使用配套构建器：[NeLuaJ-Builder](https://github.com/znzsofficial/NeLuaJ-Builder)。IDE ⇄ 构建器的交接协议见 [docs/BuilderHandoff.md](./docs/BuilderHandoff.md)。

## 📝 Hello World

```lua
import "android.widget.*"

layout = {
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

- [AI 代理](./docs/AIAgent.md) —— 工具、MCP、会话模型
- [构建器交接](./docs/BuilderHandoff.md) —— 打包用户工程
- [Lua 运行时](./docs/LuaJRuntime.md) · [LuaActivity](./docs/LuaActivity.md) · [布局](./docs/LuaLayout.md)
- [测试](./tests/README.md) —— 方法论、套件与新增方式

## 📄 许可证

本项目基于 [Apache License 2.0](LICENSE) 开源。

---
**注**：项目处于活跃开发中，API 可能随版本变化；请以源码与上述文档为准。
