<div align="center">

# NeLuaJ+

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/znzsofficial/NeLuaJ)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android-green)](https://developer.android.com)

**基于 LuaJ 的现代 Android 开发环境**

[English](README.md) | [简体中文](README_CN.md)

</div>

<br>

**NeLuaJ+** 是一个现代化的 Android Lua 开发环境，基于 LuaJ 引擎并在其基础上进行了深度扩展。它允许开发者使用 Lua 语言直接调用 Android API，编写原生 Android 应用。本项目完全拥抱 **AndroidX** 生态，集成了 **Kotlin 协程**、**Coil 3** 图片加载库，并提供了丰富的内置功能，以支持高效的移动端开发。

## ✨ 核心特性

根据代码库分析，NeLuaJ+ 提供了以下核心功能：

- **🚀 现代化技术栈**
    - **完全迁移至 AndroidX**：`LuaActivity` 继承自 `AppCompatActivity`，支持最新的 Android 组件和 Material Design。
    - **Kotlin 协程支持**：内置协程作用域 (`lifecycleScope`)，支持异步任务处理，告别传统线程管理的复杂性。
    - **Coil 3 图片加载**：集成最新的 Coil 3 库，支持高效的图片加载与缓存，通过 `lua` 接口可直接调用。

- **🔧 强大的 Lua 互操作性**
    - **原生 API 访问**：通过 `LuaJava` 桥接技术，可直接在 Lua 中调用 Java/Android 类库（如 `android.widget.TextView`）。
    - **全局环境增强**：内置 `activity`、`this`、`call` 等全局变量，以及 `print`、`printf` 等标准输出函数。
    - **布局动态加载**：提供 `loadlayout` 函数，支持将 Lua 表结构直接转换为 Android View 层次结构，实现声明式 UI 开发。

- **⚡ 内置实用工具**
    - **多线程与并发**：提供 `xTask`、`thread`、`timer` 等函数，轻松实现多线程操作和定时任务。
    - **网络请求**：内置 `okHttp` (基于 OkHttp) 和 `http` 模块，支持同步/异步网络请求。
    - **文件与数据**：集成 `json` 解析库和 `file` 操作模块，方便数据处理与本地存储。
    - **Dex 动态加载**：支持 `LuaDexLoader`，可在运行时加载外部 `.dex` 或 `.jar` 文件，实现插件化扩展。

## 🛠️ 快速开始

### 环境要求
- Android Studio Ladybug 或更高版本
- JDK 17+
- Android SDK 33+

### 构建项目
如果你想使用打包器生成发布版本，可前往：[NeLuaJ-Builder](https://github.com/znzsofficial/NeLuaJ-Builder)

1.  **克隆仓库**
    ```bash
    git clone https://github.com/znzsofficial/NeLuaJ.git
    cd NeLuaJ
    ```

2.  **编译 APK**
    ```bash
    ./gradlew assembleRelease
    ```
    编译产物位于 `app/build/outputs/apk/release/` 目录下。

## 📝 使用指南

### 1. Hello World
在 `main.lua` 中编写如下代码即可显示一个简单的界面：

```lua
require "import"
import "android.widget.*"
import "android.view.*"

-- 定义布局
layout = {
  LinearLayout,
  orientation="vertical",
  layout_width="match_parent",
  layout_height="match_parent",
  gravity="center",
  {
    TextView,
    text="Hello, NeLuaJ+!",
    textSize="24sp",
    textColor="#333333"
  },
  {
    Button,
    text="点击我",
    onClick=function(v)
      print("按钮被点击了！")
      Toast.makeText(activity, "欢迎使用 NeLuaJ+", Toast.LENGTH_SHORT).show()
    end
  }
}

-- 加载布局
activity.setContentView(loadlayout(layout))
```

### 2. 异步网络请求 (OkHttp)
NeLuaJ+ 提供了强大的 `okHttp` 模块用于处理异步网络请求。

```lua
-- GET 请求
okHttp.get("https://www.baidu.com", nil, function(code, body, response)
  print("响应代码: " .. code)
  print("内容长度: " .. #body)
end)

-- POST JSON 请求
local jsonData = '{"key": "value"}'
local headers = {["Content-Type"] = "application/json"}

okHttp.postJson("https://api.example.com/data", jsonData, headers, function(code, body, response)
  if code == 200 then
    print("成功: " .. body)
  else
    print("错误: " .. code)
  end
end)
```

## 📚 API 参考

以下是 `LuaActivity` 注入到 Lua 全局环境中的主要变量和函数：

| 变量/函数 | 描述 |
| :--- | :--- |
| `activity` / `this` | 当前的 `LuaActivity` 实例 (继承自 `AppCompatActivity`) |
| `print(msg)` | 在控制台或日志视图中输出信息 |
| `printf(fmt, ...)` | 格式化输出 |
| `loadlayout(table)` | 将 Lua 表解析为 Android View |
| `task(func, callback)` | 在后台线程执行函数，并在主线程回调结果 |
| `thread(func)` | 启动一个新的线程 |
| `timer(func, delay, period)` | 启动定时器 |
| `okHttp` | 异步 OkHttp 客户端实例 |
| `json` | JSON 解析库 |
| `ext` | 扩展库，提供 Lua 5.5 风格的二进制辅助函数：`pack`、`unpack`、`packsize` |
| `import` | 导入 Java 类 (需要 `require "import"`) |

## 📄 许可证

本项目基于 [Apache License 2.0](LICENSE) 开源。

---
**注意**：本项目处于活跃开发中，API 可能会随版本更新而变化。建议查阅源码 (`LuaActivity.kt`) 获取最新信息。

