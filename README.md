<div align="center">

# NeLuaJ+

[![Android CI](https://github.com/znzsofficial/NeLuaJ/actions/workflows/android.yml/badge.svg)](https://github.com/znzsofficial/NeLuaJ/actions/workflows/android.yml)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android-green)](https://developer.android.com)

**AI-powered Lua IDE for Android**

[English](README.md) | [简体中文](README_CN.md)

</div>

<br>

**NeLuaJ+** is a mobile IDE for building Android apps in Lua — with an AI coding agent built into the workflow. Declarative UIs from Lua tables, on-device execution, and a project-scoped agent that can read, patch, search, run, and even package your code alongside you.

## ✨ Highlights

### 🤖 Built-in AI Agent (`mods/agent`)

- **Agentic loop with real tools** — `AgentTurn` drives file operations, patches, search, layout queries, project execution and builder handoff. Tool rounds are unlimited by default, with an optional configured limit. The [tool registry](./app/src/main/assets/mods/agent/ToolRegistry.lua) is the source of the tool inventory.
- **Parallel reads & delegation** — eligible read-only batches run concurrently; `run_subtask` runs one isolated child task at a time. File changes normally require confirmation; project-local auto-approval is configurable. MCP tools currently execute without confirmation: connect only servers you trust.
- **Safe code execution** — model-written Lua runs in a separate `:lua_sandbox` process with no filesystem or Android access, strict timeouts, and an allow-listed HTTPS egress. Network reads go through a hardened public-only fetcher.
- **Recoverable file changes** — supported file tools use `ChangeSet` snapshots, fingerprint conflict detection and per-project undo/redo. Multi-file recovery attempts rollback; it is not a filesystem-wide transaction or a substitute for backups.
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
import "java.util.ArrayList"

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
local items = ArrayList()
items.add("Hello")
for i, item in luajava.iterate(items) do
  print(i, item)
end
```

### 🧪 Engineering

- Desktop Lua suites are discovered by `pwsh -File tests/run_tests.ps1`; JVM tests run through Gradle. Counts come from test output, not a handwritten README total. See [testing](./tests/README.md).
- CI runs documentation/runner checks, Lua and JVM tests, runtime JAR takeover verification, and Debug/Release builds. Build success does not prove Android rendering or lifecycle correctness.

### Home and project workflow

Search projects by app name, folder or package; continue from actual open history, open an existing project folder, or create a project and enter its `main.lua`. Conversation lists read metadata and provide project-aware navigation. The home shell switches between native bottom navigation and a rail by available width. See the [home guide](./app/src/main/assets/res/doc/home_en.html) and [implementation boundaries](./docs/HOME.md).

## 🛠️ Getting Started

Use JDK 17 and the checked-in Gradle wrapper. The current source compiles against Android SDK 37, targets API 33 and supports devices from API 26; these are different requirements. Use Android Studio compatible with the pinned plugins. See [building](./docs/BUILDING.md) for setup, verification, versioning and signing boundaries.

```bash
git clone https://github.com/znzsofficial/NeLuaJ.git
cd NeLuaJ
./gradlew :app:assembleDebug
```

To package your Lua projects into standalone APKs, use the companion builder: [NeLuaJ-Builder](https://github.com/znzsofficial/NeLuaJ-Builder). The IDE ⇄ builder handoff protocol is documented in [docs/BuilderHandoff.md](./docs/BuilderHandoff.md).

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

- **Start here:** [documentation index](./docs/README.md) · [build from source](./docs/BUILDING.md).
- **Use the IDE / write Lua apps:** [home guide](./app/src/main/assets/res/doc/home_en.html) · [bundled API catalog](./app/src/main/assets/res/doc/agent_docs.md).
- **Maintain the project:** [maintenance](./docs/MAINTENANCE.md) · [tests](./tests/README.md) · [device acceptance](./docs/HOME_VALIDATION.md).
- **Implementation:** [home/editor](./docs/HOME.md) · [Agent](./docs/AIAgent.md) · [runtime](./docs/LuaJRuntime.md) · [Activity](./docs/LuaActivity.md) · [layout](./docs/LuaLayout.md) · [builder handoff](./docs/BuilderHandoff.md).
- **History:** [historical design index](./docs/README.md#历史设计与记录) — retained for context, not current capability guarantees.

Repository maintenance documents are primarily Chinese; bundled guides include English versions where listed. Open bundled HTML through the app's Help page or a local browser; GitHub may show its source instead of rendering it.

`tests/bench_override.lua` is a device-only benchmark of the override/dx pipeline. A desktop JVM can generate the dex bytes, but it cannot load them.

## 📄 License

This project is open source under the [Apache License 2.0](LICENSE).

---
**Note**: This project is under active development. APIs may change between versions; refer to the source and the docs above for the current state.
