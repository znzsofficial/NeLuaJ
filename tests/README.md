# NeLuaJ+ 测试方法说明

本项目是 AndroLua 系 IDE：业务逻辑几乎全部写在 `app/src/main/assets/` 下的 Lua 模块里，
Kotlin/Java 层只提供运行时（LuaActivity、LuaFileUtil 等基础设施）。测试策略围绕这个特点设计：

**能用纯 Lua 表达的逻辑，一律写成不依赖 Android 运行时的独立模块，在 JVM 上直接跑行为测试；
依赖 Android 视图/`luajava` 的 UI 层代码，用 LuaC 编译做语法门禁，再上真机手工回归。**

## 验证分层

| 层 | 手段 | 何时跑 |
|---|---|---|
| ① 语法门禁 | `SyntaxCheck`（LuaC 编译加载，多文件批量） | 改动任何 `.lua` 后 |
| ② 行为测试 | `Run` 驱动 + `Test*.lua` 套件（JVM，无需设备） | 改动被测模块后 / 提交前 |
| ③ Kotlin 编译 | `.\gradlew.bat :app:compileDebugKotlin` | 改动 Kotlin 层后 |
| ④ 真机回归 | 打包安装，按改动面手工验证 | 涉及 UI/loadlayout/权限/生命周期时 |

第②层是主力：`mods/agent/` 下的核心模块（AgentTurn、PatchEngine、TodoManager、
ToolExecutor、SubagentRunner、ConversationStore、Markdown、ModelRegistry、TextUtil…）
全部是「configure 注入依赖 + 纯函数逻辑」的结构，因此可以在 LuaJ 上完整执行真实源码，
不需要模拟 Android。

## 快速开始

```powershell
# 在项目根目录执行
.\tests\run_tests.ps1                    # 跑全部 8 个套件（211 个断言）
.\tests\run_tests.ps1 TestPatch          # 只跑一个套件
.\tests\run_tests.ps1 -Check <file.lua>  # 语法检查（可传多个文件）
```

脚本会自动做三件事：

1. 定位 luajpp.jar（默认取兄弟仓库 `NeLuaJ+Builder/app/libs/luajpp.jar`；
   本仓库 `app/libs/luajpp_nocglib.jar` 只够语法检查，行为测试会缺 `JavaClass` 报
   `NoClassDefFoundError`，找不到完整版时可用 `-Luajpp <路径>` 显式指定）
2. 增量编译 `Run.java` / `SyntaxCheck.java` 到 `tests/out/`（已 gitignore）
3. 逐套件执行，末尾输出 `ALL SUITES PASS` 或失败清单并以非零码退出

CI/脚本判定标准：单个套件内部约定 `ALL-PASS`（全部通过）与
`FAILURES: n` + `os.exit(1)`（存在失败），`run_tests.ps1` 同时检查这两者。

## 运行原理

### Run.java（行为测试驱动）

```java
Globals globals = JsePlatform.standardGlobals();   // 含 io/os/string/table 等，不含 luajava
// 按脚本位置推导项目根（<root>/tests/*.lua），注入全局 ASSETS
globals.set("ASSETS", root.resolve("app/src/main/assets") + "/");
globals.load(reader, scriptPath).call();         // 直接执行测试脚本
```

- 测试脚本通过 `ASSETS .. "mods/agent/Xxx.lua"` 定位被测模块的真实源码，
  `loadfile` 后 `assert(...)()` 执行拿到模块表——**跑的就是仓库里的生产代码**，没有副本
- `ASSETS` 缺省回退 `"app/src/main/assets/"`（相对路径），所以从项目根手动执行也可以

### 依赖注入：package.preload 打桩

纯模块之间用 `require` 互相引用，但被测模块的部分依赖（如 TextUtil）在 JSE
环境没有全局注册。约定用 `package.preload` 预注册：

```lua
package.preload["mods.utils.TextUtil"] = assert(loadfile(ASSETS .. "mods/utils/TextUtil.lua"))
local TM = assert(loadfile(ASSETS .. "mods/agent/TodoManager.lua"))()
```

先 `preload` 真实模块再 `loadfile` 被测模块，被测模块内部 `require` 即命中缓存；
需要隔离依赖时也可以 preload 一个假实现（如 TestSubagent 对 json/请求层的打桩）。

### 环境差异打桩

被测模块引用的 AndroLua 全局（`file`、`json`、`this`、`Bean`…）在 JSE 不存在，
测试里按需注入最小假实现：

```lua
-- TestStoreIndex.lua：给 InitReader 依赖的 file.readall 打桩
file = { readall = function(p) local h = io.open(p, "rb"); ... end }
-- ConversationStore 未 configure 时自动回退 this.getSharedData —— JSE 里 this 为 nil，
-- 恰好覆盖了「无宿主环境」分支
```

## 套件清单

| 套件 | 被测模块 | 覆盖要点 |
|---|---|---|
| TestTodo | `mods/agent/TodoManager.lua` | 计划条目校验、状态归一化、UTF-8 截断、提交/回显 |
| TestPatch | `mods/agent/PatchEngine.lua` | 三种补丁格式（SEARCH-REPLACE/统一 diff/整文件替换）、多块定位、CRLF、失败提示 |
| TestRegistry | `mods/agent/ModelRegistry.lua` | 供应商/模型增删改、当前模型指针、辅助模型按身份持久化、旧格式迁移 |
| TestSubagent | `mods/agent/SubagentRunner.lua` | 子代理执行循环、工具确认/取消、轻量模型路由、进度上报 |
| TestParallel | `mods/agent/ToolExecutor.lua` | 只读工具白名单并行批、非法/越界/坏 JSON 拦截 |
| TestMarkdown | `mods/agent/Markdown.lua` | 代码块切分、表格行解析、分隔符识别、边界情况 |
| TestTextUtil | `mods/utils/TextUtil.lua` | utf8Cap 截断、fmtTokens 格式化 |
| TestStoreIndex | `mods/agent/ConversationStore.lua`、`mods/project/InitReader.lua` | 会话增删改、loadIndex 轻量索引与深隔离、未 configure 回退、readFields 批量直读 |

## 新增套件约定

1. 文件放 `tests/Test<Name>.lua`，首行声明 `local ASSETS = ASSETS or "app/src/main/assets/"`
2. 复制既有套件的骨架：`check(name, cond)` 计数器、末尾 `ALL-PASS` / `FAILURES: n` + `os.exit(1)`
3. 被测模块用 `assert(loadfile(ASSETS .. "<相对路径>"))()` 加载，依赖用 `package.preload` 注入
4. 临时文件写到 `os.getenv("TEMP")`，用例结束清理
5. 把套件名加进 `run_tests.ps1` 的 `$suites` 列表

## 范围外事项（需要真机）

- **UI 层**：`loadlayout`、`luajava.bindClass`、Fragment/Activity 生命周期、Dialog——
  JSE 没有 Android 类，只能过语法门禁
- **Kotlin 层**：`compileDebugKotlin` 通过不代表行为正确；尤其注意本仓库约束——
  **用户打包的 APK 会继承 Java/manifest 层，该层只允许 additive 改动**，动过必须真机回归
- **集成路径**：权限门禁、编辑器↔首页跳转、AI 面板与 AgentTurn 的真实对话流

## 已知注意事项

- 两个 luajpp.jar 的区别见「快速开始」第 1 条；报 `NoClassDefFoundError: org/luaj/lib/jse/JavaClass`
  说明用错了 nocglib 版
- 控制台中文显示乱码多为代码页问题，不影响断言（字符串比较在 JVM 内部按 UTF-8 进行）
- 手动执行单条命令的等价形式：
  ```powershell
  javac -encoding UTF-8 -cp <luajpp.jar> -d tests\out tests\Run.java tests\SyntaxCheck.java
  java -noverify -cp "<luajpp.jar>;tests\out" Run tests\TestTodo.lua
  ```
