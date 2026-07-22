# LuaActivity 实现思路与后续方案

## 1. 定位

`LuaActivity` 是 NeLuaJ+ 的 **Lua 脚本宿主**：每个打开的 `.lua` 页面（或工程 `main.lua`）对应一个 Activity 实例，持有独立的 **LuaJ `Globals`**，并把 Android 能力注入全局环境。

```text
用户工程 / assets 脚本
        │
        ▼
  LuaActivity.onCreate
        │
        ├─ 解析 Intent 路径 → luaDir / luaFile / pageName
        ├─ LuaDexLoader 加载工程 libs
        ├─ JsePlatform.standardGlobals()
        ├─ 注入 activity/this/print/loadlayout/task/…
        ├─ initENV()（init.lua 等）
        ├─ doFile(luaFile)
        ├─ runFunc("onCreate")
        └─ 未 setContentView → showLogView
```

实现类：`com.androlua.LuaActivity`（`AppCompatActivity` + `LuaContext` + `ResourceFinder` + …）。

---

## 2. 职责边界

| 职责 | 位置 |
|------|------|
| 生命周期 → 调 Lua `onXxx` | `LuaActivity` 本体 |
| Globals 注入与 doFile | 本体 `onCreate` |
| 日志 / Toast / 错误页 | `sendMsg` + `logEvents` + `LogAdapter` + `LuaActivityUI` |
| 主题 / 动态色 | `LuaActivityTheme` + `LuaThemeUtil` |
| 导航 / result / 权限 / 文件 / 服务 | `com.androlua.activity.LuaActivity*` 辅助类 |
| 布局 | **不**在 Activity 内实现，委托 `LuaLayout` / `loadlayout` |

设计倾向：**Activity 变薄，能力进 helper**（与 `LuaLayout` 拆 `layout` 包同一思路）。

---

## 3. 启动与环境

### 3.1 路径与工程根

1. 默认 `luaDir = filesDir`，`luaFile = main.lua`。  
2. `Intent.data` 可指向文件或目录，覆盖 `luaDir` / `luaFile`。  
3. `checkProjectDir` 向上找工程根 → `luaRootDir`（供 `libs`、资源等）。  
4. `pageName` = 脚本名去掉扩展名，登记到 **`sLuaActivityMap[pageName]`**，供 `LuaActivity.getActivity("main")`。

### 3.2 Globals 注入（摘要）

| 名 | 含义 |
|----|------|
| `activity` / `this` | 当前 `LuaActivity` |
| `print` / `printf` | → `sendMsg`（Toast 受 `debug` 控制） |
| `loadlayout` | `LuaLayout` |
| `task` / `thread` / `timer` / `xTask` / `call` | 异步与主线程回调 |
| `res` / `json` / `file` / `okhttp` / `saf` / `Http` / `R` / `android` | 模块与包 |
| `lazy` | 惰性值 |

脚本侧工程环境另有 `environment.lua`（主界面）与 `mods.bootstrap`（二级页轻量环境），与 Activity 注入叠加，注意**勿在二级页 require 主界面 environment**。

### 3.3 init.lua 与 debug

- `initENV()` 读工程 `init.lua`（应用名、主题、`debug_mode` 等）。  
- `debug` / `debug_mode` 影响 Toast 等调试输出（见 `LuaActivityUI.showToast`）。  
- 用户文档：`res/doc/init_lua_zh.html`、`global_env.html`。

### 3.4 首帧 UI

- `doFile` + `onCreate` 后若未 `setContentView`（`isSetViewed == false`）→ **`showLogView`**（日志列表，便于空壳脚本调试）。  
- 运行时异常：`sendError` → 可选 `showLogView(true)`。

---

## 4. 生命周期与 Lua 回调

Activity 生命周期方法内普遍：

```text
super.xxx()
runFunc("onXxx", …)
```

`runFunc`：从 Globals 取函数并 `pcall` 风格调用；异常进 `sendError`。

重要回调（文档见 `LuaActivity.html`）：

| Lua | 时机 |
|-----|------|
| `onCreate` / `onStart` / `onResume` / `onPause` / `onStop` / `onDestroy` | 标准生命周期 |
| `onResult` / `onActivityResult` | 页面返回（推荐 `newActivity` + `result`） |
| `onError(title, exception)` | `sendError`；返回值控制日志粒度（`trace`/`log`/`message`/`title`） |
| `onConfigurationChanged` | 旋转等；Activity 会 `initSize()` |
| `onKey*` / `onTouchEvent` | 按键与触摸（若脚本定义） |
| `onContentChanged` | 内容视图变化，置 `isSetViewed` |

**`onDestroy`**：跑 Lua `onDestroy` → `LuaGcable` 清理 → 注销广播 → 从 `sLuaActivityMap` 移除。

脚本内若再定义 `onDestroy` 并 `require` 调试模块（如 vConsole），应 **链式** 旧回调，避免覆盖。

---

## 5. 日志与错误

```text
print / sendMsg
    → logEvents (MutableSharedFlow)
    → UI 线程：Toast(debug) + logAdapter + LuaActivity.logs
```

- **`LuaActivity.logs`**：进程级列表，有上限（如 5000）。  
- **`sendError`**：防重入 `handlingError`；优先 `onError` 返回值；默认拼 `title: message`。  
- **崩溃文件**：应用层另有 crash 目录（见 `backup_crash.html`）；vConsole 等可额外快照。

与 **vConsole** 的关系：vConsole 挂钩 `print`/`onError` 并镜像 `LuaActivity.logs`，应转发 `sendMsg` 以保持 Toast/logAdapter 一致。

---

## 6. 辅助类一览（`com.androlua.activity`）

| 类 | 职责 |
|----|------|
| `LuaActivityUI` | setContentView(表)、Fragment、日志页、Toast、Decor/Root |
| `LuaActivityTheme` | 动态色 / 主题种子 |
| `LuaActivityNavigation` | newActivity、result、ActivityResultLauncher |
| `LuaActivityPermissions` | 危险权限 / 存储权限 |
| `LuaActivityFiles` | 路径、扩展目录等 |
| `LuaActivityServices` | 绑定服务 |
| `LuaActivityImageLoader` | Coil 封装 |
| `LuaActivityStorage` | SharedPreferences 等 |
| `LuaActivityUtils` | 杂项（线程开关、版本名…） |

字段中大量 `internal`，供 helper 访问 `globals`、`luaDir` 等。

---

## 7. 导航与其它

- `LuaContext`：统一 `sendMsg` / `sendError` / `getLuaDir` / 宽高等，供 `LuaLayout`、`task`、网络库使用。  
- `ResourceFinder`：Lua 侧找资源文件。  
- `LuaMetaTable`：Java 侧元表扩展（若使用）。  
- 广播：`registerReceiver` 记入列表，`onDestroy` 统一反注册。

---

## 8. 已知限制

1. **一脚本一 Activity**：深栈多页面时实例多，Globals 不共享（有意隔离）。  
2. **`sLuaActivityMap` 按 pageName**：同名脚本多实例会互相覆盖 map 项。  
3. **主线程假设**：多数 UI API 要求主线程；`thread`/`task` 回传需 `call`。  
4. **`onError` 返回非约定值**：可能拦截默认日志，脚本需自觉。  
5. **与主工程 environment 耦合**：编辑器主界面逻辑在 assets，不在 Kotlin；改注入需两边对齐。

---

## 9. 后续可能的修改方案

### 9.1 短期

| 项 | 说明 |
|----|------|
| 继续抽离 onCreate | 把 Globals 注入列表收到 `LuaActivityBootstrap`，Activity 只调一行 |
| pageName 冲突 | map 键改为 `luaFile` 绝对路径或 `identityHashCode` |
| 日志背压 | `logEvents` 已有 buffer；可监控丢弃并计数 |
| 文档 | 与 `res/doc/LuaActivity.html` / `global_env.html` 保持同步 |

### 9.2 中期

| 项 | 说明 |
|----|------|
| 结构化日志 | `sendMsg` 支持 level；LogAdapter 已有分级展示，可打通 |
| 生命周期协程 | 更多 `lifecycleScope` 替代裸 thread，统一取消 |
| 权限/结果 API | 全面推荐 `permissionLauncher` / `resultLauncher`，弱化旧 requestCode |
| 多窗口 | 与 `RunWindowConfig`（freeform/adjacent）协作测试 `onConfigurationChanged` |

### 9.3 长期

| 项 | 说明 |
|----|------|
| 进程模型 | 可选多进程运行用户工程，隔离崩溃 |
| 调试协议 | 与 vConsole / PC 端统一调试通道（WebSocket） |
| 组件化 | `LuaFragment` 与 Activity 能力对齐（已有部分 Fragment 支持） |

### 9.4 不建议

- 在 `LuaActivity` 内重写布局解析（应保持 `LuaLayout` 单一实现）。  
- 全局可变 `sActivity` 作为唯一上下文（多 Activity 时易错；优先 `this`/`activity`）。  
- 无限制放大 `logs` 列表（内存）。

---

## 10. 修改时检查清单

- [ ] 新生命周期是否 `runFunc` 且异常进 `sendError`  
- [ ] 是否误阻塞主线程  
- [ ] `onDestroy` 是否释放广播 / Gcable / map 项  
- [ ] 注入 Globals 的新 API 是否写入 `global_env.html` / `LuaActivity.html`  
- [ ] 二级页是否误 require 主界面 `environment`  
- [ ] 与 `LuaLayout` / `print` / `onError` 契约是否破坏 vConsole 等调试工具  

---

## 11. 参考文件

```
app/src/main/java/com/androlua/LuaActivity.kt
app/src/main/java/com/androlua/activity/*.kt
app/src/main/java/com/androlua/LogAdapter.kt
app/src/main/java/org/luaj/android/print.kt
app/src/main/java/org/luaj/android/loadlayout.kt
app/src/main/assets/environment.lua
app/src/main/assets/mods/bootstrap.lua
app/src/main/assets/res/doc/LuaActivity.html
app/src/main/assets/res/doc/global_env.html
app/src/main/assets/res/doc/init_lua_zh.html
docs/LuaLayout.md
```
