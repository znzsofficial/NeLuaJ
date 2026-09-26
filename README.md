<div align="center">

# NeLuaJ+

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/znzsofficial/NeLuaJ)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android-green)](https://developer.android.com)

**AI-powered Lua IDE for Android**

[English](README.md) | [简体中文](README_CN.md)

</div>

<br>

**NeLuaJ+** is a mobile IDE for building Android apps in Lua — with an AI coding agent built into the workflow. Declarative UIs from Lua tables, on-device execution, and a project-scoped agent that can read, patch, search, run, and even package your code alongside you.

## ✨ Highlights

### 🤖 Built-in AI Agent (`mods/agent`)

- **Agentic loop with real tools** — 20 built-in tools behind `AgentTurn`, a turn state machine with generation guards and an unbounded tool loop: file read/write, a multi-format **patch engine** (search-replace / unified diff / whole-file), in-project search, a project runner, and a **builder handoff** that packages your project into an APK.
- **Parallel & delegated execution** — read-only tool batches run concurrently; `run_subtask` spawns isolated subagents with live progress cards; destructive operations require explicit confirmation.
- **Safe code execution** — model-written Lua runs in a separate `:lua_sandbox` process with no filesystem or Android access, strict timeouts, and an allow-listed HTTPS egress. Network reads go through a hardened public-only fetcher.
- **File changes are transactions** — every mutation is snapshotted by `ChangeSet` with fingerprint conflict detection, per-project undo/redo, and rollback on partial failure.
- **Context that manages itself** — automatic history compression against the model's context window, todo tracking injected into the prompt, local `SKILL.md` skills, and an **auxiliary model route** for cheap work (titles, compression, lightweight subagents).
- **MCP support** — attach external MCP servers over Streamable HTTP, one-click `context7` / `deepwiki` presets, per-server connection tests.
- **Conversation workspace** — named conversations persisted per project, auto-generated titles, per-conversation token usage, in-panel search, export, regenerate / edit-resend, and markdown rendering with tables. See [docs/AIAgent.md](./docs/AIAgent.md).

### ☕ Java interop beyond stock LuaJ

- **Proxies that behave like Java objects** — implement single-method interfaces with plain functions (`Runnable(function() ... end)`), combine multiple interfaces in one `luajava.createProxy(...)`, and subclass Java **classes** with `override` (interfaces are rejected and must use `createProxy`). The first argument of an overridden method is a `superCall` into the original implementation. Call Java members with a dot; a colon passes `self` and breaks overload resolution. Primitive returns are unboxed by kind (`Boolean`, `Character`, or `Number`), so a Lua `nil` becomes a typed zero instead of a bad cast. Proxies get Java-default `equals` / `hashCode` / `toString`, so they can safely live inside `HashMap` and friends.
- **Deterministic member selection** — `luajava.constructor` / `luajava.method` pick members by exact public parameter types when overload scoring is ambiguous; automatic numeric scoring is range-aware over full 64-bit Lua integers, so `byte` / `short` / `char` / `int` overloads are chosen by value, not by truncation.
- **Kotlin-first bridging, no kotlin-reflect** — `luajava.kotlinObject` / `luajava.kotlinCompanion` reach Kotlin `object` and companion singletons; `@JvmStatic` members are callable straight from `bindClass`. Java and Kotlin members share uniform dot-call semantics.
- **Collections as first-class citizens** — generic-`for` iteration over arrays, `Map`, `Iterable` / `Iterator` and Kotlin `Sequence` via `luajava.iterate`; `#` works on maps and every collection; `luajava.toTable` / `toList` / `toSet` / `toMap` convert between Lua tables and Java containers.
- **Plugin-safe dynamic loading** — `loadDex` / `loadJar` classes resolve through a loader-aware cache (`JavaClass` keyed by `Class<?>` with weak references; package caches invalidated on loader change), so same-named classes from different `DexClassLoader`s stay distinct and unloaded projects can be garbage-collected.
- **Maintained in-tree** — key `org.luaj.lib.jse` bridge classes are overridden from project source at build time, with UTF-8-correct string internals and coroutine-backed `xTask`; regression-covered by local unit tests. See [docs/LuaJRuntime.md](./docs/LuaJRuntime.md).

```lua
import "java.lang.Runnable"

-- single-method interface from a plain function
local r = Runnable(function() print("run") end)

-- subclass a Java class; superCall invokes the original method
local List = ArrayList.override {
  add = function(superCall, v)
    print("add:", v)
    return superCall(v)
  end,
}

-- iterate Java containers with generic for
for i, item in luajava.iterate(someJavaList) do
  print(i, item)
end
```

### 🧪 Engineering

- **JVM behavior tests** for the Lua codebase: 8 suites / 200+ assertions runnable on the desktop via `.\tests\run_tests.ps1` — no device required. Methodology and suite map in [tests/README.md](./tests/README.md).
- **LuaC syntax gate** for Lua changes; the Kotlin layer is verified with Gradle builds.

## 🛠️ Getting Started

Requirements: Android Studio Ladybug or higher, JDK 17+, Android SDK 33+.

```bash
git clone https://github.com/znzsofficial/NeLuaJ.git
cd NeLuaJ
./gradlew assembleRelease
```

To package your Lua projects into standalone APKs, use the companion builder: [NeLuaJ-Builder](https://github.com/znzsofficial/NeLuaJ-Builder). The IDE ⇄ builder handoff protocol is documented in [docs/BuilderHandoff.md](./docs/BuilderHandoff.md).

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
    text = "Click Me",
    onClick = function()
      print("Clicked!")
    end,
  },
}

activity.setContentView(loadlayout(layout))
```

The Lua runtime keeps the familiar declarative ergonomics — `loadlayout`, `luajava` bridging, `task` / `thread` / `timer`, `okHttp`, `json`, dynamic dex loading — documented in [docs/LuaJRuntime.md](./docs/LuaJRuntime.md), [docs/LuaActivity.md](./docs/LuaActivity.md) and [docs/LuaLayout.md](./docs/LuaLayout.md).

## 📚 Documentation

- [AI Agent](./docs/AIAgent.md) — tools, MCP, conversation model
- [Builder handoff](./docs/BuilderHandoff.md) — packaging user projects
- [Lua runtime](./docs/LuaJRuntime.md) · [LuaActivity](./docs/LuaActivity.md) · [Layout](./docs/LuaLayout.md)
- [Testing](./tests/README.md) — methodology, suites, how to add one

`tests/bench_override.lua` is a device-only benchmark of the override/dx pipeline. A desktop JVM can generate the dex bytes, but it cannot load them.

## 📄 License

This project is open source under the [Apache License 2.0](LICENSE).

---
**Note**: This project is under active development. APIs may change between versions; refer to the source and the docs above for the current state.
