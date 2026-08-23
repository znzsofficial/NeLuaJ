# NeLuaJ+ 实现文档

本目录记录核心运行时组件的**实现思路**与**后续演进方案**，面向维护者与二次开发，不替代应用内 HTML 帮助（`app/src/main/assets/res/doc/`）。

| 文档 | 内容 |
|------|------|
| [LuaLayout.md](./LuaLayout.md) | 表驱动布局 `loadlayout`：解析、专用键、拆分结构、性能与后续 |
| [LuaActivity.md](./LuaActivity.md) | Lua 宿主 Activity：Globals 注入、生命周期、日志、辅助类、后续 |
| [AIAgent.md](./AIAgent.md) | 内置 AI 助手：入口、配置键、自动重试、MCP、工具确认、i18n |
| [BuilderHandoff.md](./BuilderHandoff.md) | 打开 NeLuaJ-Builder 的跨应用协议、发送前检查和同步约束 |
| [LuaJRuntime.md](./LuaJRuntime.md) | LuaJ JSE：桥接缓存、动态 ClassLoader、Globals、沙盒与 IO 维护约束 |

相关代码入口：

- `app/src/main/java/com/androlua/LuaLayout.kt` + `com/androlua/layout/*`
- `app/src/main/java/com/androlua/LuaActivity.kt` + `com/androlua/activity/*`
- Lua 侧：`org.luaj.android.loadlayout`、`environment.lua` / `mods.bootstrap`
