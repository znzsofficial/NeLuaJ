<div align="center">

# NeLuaJ+

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/znzsofficial/NeLuaJ)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android-green)](https://developer.android.com)

**Modern Android Development Environment based on LuaJ**

[English](README.md) | [简体中文](README_CN.md)

</div>

<br>

**NeLuaJ+** is a modernized Android Lua development environment, built upon the LuaJ engine and extensively enhanced. It allows developers to access Android APIs directly using Lua to create native Android applications. This project fully embraces the **AndroidX** ecosystem, integrating **Kotlin Coroutines**, the **Coil 3** image loading library, and providing rich built-in features to support efficient mobile development.

## ✨ Key Features

Based on code analysis, NeLuaJ+ offers these core capabilities:

- **🚀 Modern Tech Stack**
    - **Fully Migrated to AndroidX**: `LuaActivity` inherits from `AppCompatActivity`, supporting the latest Android components and Material Design.
    - **Kotlin Coroutines Support**: Built-in coroutine scope (`lifecycleScope`) for handling asynchronous tasks, moving away from complex thread management.
    - **Coil 3 Image Loading**: Integrates the latest Coil 3 library for efficient image loading and caching, accessible directly via `lua` interfaces.

- **🔧 Powerful Lua Interoperability**
    - **Native API Access**: Uses `LuaJava` bridging technology to directly call Java/Android classes (e.g., `android.widget.TextView`) from Lua.
    - **Global Environment Enhancements**: Built-in global variables like `activity`, `this`, `call`, and standard output functions `print`, `printf`.
    - **Dynamic Layout Loading**: Provides `loadlayout` function to convert Lua tables directly into Android View hierarchies, enabling declarative UI development.

- **⚡ Built-in Utilities**
    - **Multithreading & Concurrency**: Functions like `xTask`, `thread`, and `timer` for easy multithreading and scheduled tasks.
    - **Networking**: Built-in `okHttp` (based on OkHttp) and `http` modules supporting synchronous/asynchronous network requests.
    - **File & Data**: Integrated `json` parsing library and `file` operations module for data processing and local storage.
    - **Dynamic Dex Loading**: Supports `LuaDexLoader` to load external `.dex` or `.jar` files at runtime, enabling plugin-based extensions.

## 🛠️ Getting Started

### Requirements
- Android Studio Ladybug or higher
- JDK 17+
- Android SDK 33+

### Building the Project
If you want to package releases with the builder, visit: [NeLuaJ-Builder](https://github.com/znzsofficial/NeLuaJ-Builder)

1.  **Clone Repository**
    ```bash
    git clone https://github.com/znzsofficial/NeLuaJ.git
    cd NeLuaJ
    ```

2.  **Compile APK**
    ```bash
    ./gradlew assembleRelease
    ```
    The build artifact will be located in `app/build/outputs/apk/release/`.

## 📝 Usage Guide

### 1. Hello World
Write the following code in `main.lua` to display a simple interface:

```lua
require "import"
import "android.widget.*"
import "android.view.*"

-- Define Layout
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
    text="Click Me",
    onClick=function(v)
      print("Button Clicked!")
      Toast.makeText(activity, "Welcome to NeLuaJ+", Toast.LENGTH_SHORT).show()
    end
  }
}

-- Load Layout
activity.setContentView(loadlayout(layout))
```

### 2. Async Network Request (OkHttp)
NeLuaJ+ provides a powerful `okHttp` module for asynchronous networking.

```lua
-- GET Request
okHttp.get("https://www.google.com", nil, function(code, body, response)
  print("Response Code: " .. code)
  print("Body Length: " .. #body)
end)

-- POST JSON Request
local jsonData = '{"key": "value"}'
local headers = {["Content-Type"] = "application/json"}

okHttp.postJson("https://api.example.com/data", jsonData, headers, function(code, body, response)
  if code == 200 then
    print("Success: " .. body)
  else
    print("Error: " .. code)
  end
end)
```

## 📚 API Reference

Below are the main variables and functions injected into the global Lua environment by `LuaActivity`:

| Variable/Function | Description |
| :--- | :--- |
| `activity` / `this` | Current `LuaActivity` instance (inherits `AppCompatActivity`) |
| `print(msg)` | Output message to console or log view |
| `printf(fmt, ...)` | Formatted output |
| `loadlayout(table)` | Parse Lua table into Android View |
| `task(func, callback)` | Execute function in background thread, callback on main thread |
| `thread(func)` | Start a new thread |
| `timer(func, delay, period)` | Start a timer |
| `okHttp` | Asynchronous OkHttp client instance |
| `json` | JSON parsing library |
| `import` | Import Java class (requires `require "import"`) |

## 📄 License

This project is open source under the [Apache License 2.0](LICENSE).

---
**Note**: This project is under active development. APIs may change with versions. Please refer to the source code (`LuaActivity.kt`) for the latest information.
