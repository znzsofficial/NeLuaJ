# NeLuaJ+ 测试方法说明

本项目是 AndroLua 系 IDE：业务逻辑几乎全部写在 `app/src/main/assets/` 下的 Lua 模块里，
Kotlin/Java 层承接运行时、平台传输、沙盒和布局分析等能力。测试策略围绕这个特点设计；维护约束和完整命令入口见 [docs/MAINTENANCE.md](../docs/MAINTENANCE.md)：

**能用纯 Lua 表达的逻辑，一律写成不依赖 Android 运行时的独立模块，在 JVM 上直接跑行为测试；
依赖 Android 视图/`luajava` 的 UI 层代码，用 LuaC 编译做语法门禁、必要时宿主替身测试装配，再上真机手工回归。**

构建机环境、SDK、签名与版本号见 [BUILDING.md](../docs/BUILDING.md)；本页专注测试机制，首页设备场景见 [HOME_VALIDATION.md](../docs/HOME_VALIDATION.md)。

## 验证分层

| 层 | 手段 | 何时跑 |
|---|---|---|
| ① 语法门禁 | `SyntaxCheck`（LuaC 只编译、不执行源码，多文件批量） | 改动任何 `.lua` 后 |
| ② 行为测试 | `Run` 驱动 + `Test*.lua` 套件（JVM，无需设备） | 改动被测模块后 / 提交前 |
| ③ Kotlin 编译 | `.\gradlew.bat :app:compileDebugKotlin` | 改动 Kotlin 层后 |
| ④ 真机回归 | 打包安装，按改动面手工验证 | 涉及 UI/loadlayout/权限/生命周期时 |
| ⑤ 文档清单 | `check_documentation_inventory.ps1`（只读文件/声明） | 改名、增删工具/模块/套件或修改文档后 |

第②层是主力：核心逻辑通过纯函数、依赖注入或最小宿主替身在 LuaJ 上执行真实源码。
`mods/agent/` 并非全部无平台依赖，TextUtil 实际位于 `mods/utils/TextUtil.lua`。
UI 套件模拟视图/宿主接口，只验证其调用与装配，不验证 Android 渲染、权限或生命周期。

## 快速开始

```powershell
# 在项目根目录执行
.\tests\run_tests.ps1                    # 跑 runner 当前发现的全部套件；总数看运行输出
.\tests\run_tests.ps1 TestPatch          # 只跑一个套件
.\tests\run_tests.ps1 -Check <file.lua>  # 语法检查（可传多个文件）
.\tests\check_documentation_inventory.ps1 # 无 JVM/Android 依赖的文档清单检查
```

脚本会自动做三件事：

1. 定位 luajpp.jar——按顺序找 `tests/libs/luajpp.jar`（仓库内置的纯 JSE 精简版，
   含 LuaC 编译器与 `org/luaj/lib/jse` 平台层，`com/androlua`、`org/luaj/android`
   等 Android 类已剔除）→ 兄弟仓库 `NeLuaJ+Builder/app/libs/luajpp.jar` 完整版 →
   本仓库 `app/libs/luajpp_nocglib.jar`（仅够 `-Check` 语法检查，行为测试会因缺
   `JavaClass` 报 `NoClassDefFoundError`）；也可用 `-Luajpp <路径>` 显式指定
2. 编译 `Run.java` / `SyntaxCheck.java` 到 `tests/out/`（已 gitignore）；编译失败立即停止，不沿用旧 class
3. 自动发现 `tests/Test*.lua`，逐套件执行，末尾输出 `ALL SUITES PASS` 或失败清单并以非零码退出；共享 bootstrap 在套件前设置 assets 模块搜索路径

CI/脚本判定标准：每个套件必须退出码为零且输出行首 `ALL-PASS` 才算通过；失败时应使用非零退出或抛出断言，且不得打印通过标记。单独出现 `FAILURES: n` 并不是 runner 的失败解析协议。`check_build_maintenance.ps1` 覆盖标记、退出码、语法错误和编译失败的传播。

## 运行原理

### Run.java（行为测试驱动）

```java
Globals globals = JsePlatform.standardGlobals();   // JSE 基础库，不是 Android 宿主
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

此表与 `tests/Test*.lua` 文件清单、runner 的发现约定相互核对，不维护断言总数。覆盖要点是人工摘要，不是从文件名推断的行为保证。

<!-- test-suites:start -->
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
| TestToolCancellation | `mods/agent/ToolExecutor.lua` | 后台工具取消、文件写锁、排队取消不落盘、已提交写入取消后仍同步一次 |
| TestMarkdownAST | `mods/agent/markdown/MarkdownAST.lua` | 块级解析、表格、未闭合代码块 |
| TestMarkdownRendering | `mods/agent/markdown/MarkdownInline.lua`、`mods/agent/markdown/TableComponent.lua` | 行内文本与表格组件的宿主替身验证 |
| TestAgentUi | `mods/agent/ChatUI.lua`、`mods/agent/ConvUi.lua` | UI 装配、确认/设置对话框、会话切换（非 Android 渲染） |
| TestMcpNotifications | `mods/agent/MCPProtocol.lua`、`mods/agent/McpHttpTransport.lua`、`mods/agent/McpSseTransport.lua` | 两种传输的通知与请求 ID 语义 |
| TestOpenAIClientCancellation | `mods/agent/OpenAIClient.lua` | 请求取消、重试和迟到回调 |
| TestAgentTurn | `mods/agent/AgentTurn.lua`、`mods/agent/Contracts.lua` | 流式快照隔离、无渲染执行、停止与过期回调、AI 写入前保存及成功后仅刷新一次 |
| TestSessionState | `mods/agent/SessionState.lua` | 会话工作集、快照与撤销/恢复 |
| TestChangeSet | `mods/agent/ChangeSet.lua`、`mods/agent/ToolExecutor.lua` | 新建/删除/重命名事务、二进制快照、回滚状态与历史持久化失败 |
| TestFileMutationService | `mods/files/FileMutationService.lua` | 统一入口、固定作用域、版本候选、取消收尾、恢复重播与主线程通知 |
| TestEditorSession | `mods/editor/EditorSession.lua`、`mods/utils/EditorUtil.lua` | 同文件强制刷新、旧缓冲区覆盖拦截、目录重命名/撤销路径映射与删除清空 |
| TestLayoutTools | `mods/agent/ToolSchemas.lua`、`mods/agent/ToolExecutor.lua`、`mods/agent/AgentChat.lua` | 布局工具 schema、策略和分发；不执行 Android 布局分析器 |
| TestToolRegistry | `mods/agent/ToolRegistry.lua`、`mods/agent/ToolSchemas.lua` | 注册元数据、兼容 schema、执行器策略和双语标签 |
| TestProjectContext | `mods/project/ProjectContext.lua`、`mods/utils/PathManager.lua` | 项目快照、路径与工程边界、过期归属；平台依赖用替身 |
| TestLayoutPreview | `activities/layouthelper/LayoutHelperActivity$loadlayout.lua` | 布局助手调用生产加载器、节点映射与编辑装饰；不证明 Android 渲染 |
| TestHomeShell | `activities/home/HomeActivity.lua`、`res/layout/home_layout.lua` | 首页命名宿主、生命周期分发、帮助回收列表的恒定壳加载、页面销毁重建；Android 依赖用替身 |
| TestHomeRows | `activities/home/HomeRows.lua` | 不变快照跳过绑定、行复用、连续区间通知与随机增删改重排回放；不代表帧率实测 |
| TestHomeNavigation | `activities/home/HomeNavigation.lua` | 独立创建页结果与 pending 去重、保存确认失败重试、请求归属与销毁抑制 |
| TestHomeProjects | `activities/home/ProjectsPage.lua` | 工程搜索、后台归属、权限/错误、未变刷新零额外绑定/最近卡片创建 |
| TestHomeConversations | `activities/home/ConversationsPage.lua` | 会话元信息、错误恢复、新建/打开、大列表未变跳过及单行更新 |
| TestCreateProject | `activities/main/CreateProject.lua` | 独立创建页控制器及真实 Activity/布局宿主替身流程、六模板选择、行内预览、异步生命周期与结果回传 |
| TestTemplateGenerator | `mods/project/templates/Generator.lua` | 参数与主题兼容、生成产物语法、模块复制、发布竞争、失败清理及真实 JVM 文件系统；不替代 Android 运行/打包验收 |
| TestTemplateScreen | `templates/shared/screen.lua.tpl` | 生成页面对运行时主题与 ActionBar 配置的响应；Android 依赖使用替身 |
| TestTemplateBehavior | `templates/` 生成产物 | 表单校验、清单回滚/重开/删除、存储写入校验、详情导航、WebView 资源与生命周期 |
| TestTemplateModules | `templates/shared/modules/TimeMeter.lua`、`templates/shared/modules/Strings.lua` | 可选计时模块的回调/单位与字符串限次拆分的数据保留 |
| TestTemplateArray | `templates/shared/modules/Array.lua` | Java 类型数组、null 槽位、边界检查与类绑定缓存 |
| TestTemplateTimeMeter | `templates/shared/modules/TimeMeter.lua` | 独立计时状态、检查点、重置及多返回值/异常 |
| TestTemplateStrings | `templates/shared/modules/Strings.lua` | Unicode 索引、字面量/pattern 分离、空字段保留与无全局副作用 |
| TestTemplateAnimator | `templates/shared/modules/ObjectAnimator.lua` | 动画类型分派、配置校验与启动顺序；不替代 Android 动画渲染验收 |
| TestHomeTranslations | `res/string/zh.lua`、`res/string/en.lua` | 双语键、格式参数与首页/编辑器资源引用 |
| TestEditorLeave | `mods/editor/LeaveGuard.lua`、`activities/main/MainActivity.lua` | 保存失败阻止离开、重试、取消、明确放弃与过期确认 |
| TestPendingNavigation | `mods/utils/ActivityUtil.lua` | 成功确认消费、失败保留、过期与替换请求 |
| TestConversationRecovery | `mods/agent/ConversationStore.lua` | 迁移失败保源、元数据索引与读取错误 |
| TestProjectRename | `mods/project/ProjectPersistence.lua` | 工程改名的关联状态与失败恢复 |
| TestSettingsAccessibility | `mods/settings/SettingsWiring.lua` | 设置开关与排序控件接线；不代替 TalkBack 实测 |
| TestTabletMode | `activities/main/TabletMode.lua` | 可用宽度与有效分栏、窄窗回退、偏好保持 |
| TestConversationList | `mods/agent/ConvList.lua` | 空态文案参数和会话信息的布局契约 |
<!-- test-suites:end -->

### 文档清单检查

```powershell
.\tests\check_documentation_inventory.ps1
```

该独立脚本无需加入 Lua runner，且不执行应用 Lua/PowerShell 源码：只读取文档、静态声明和文件清单。
检查本页套件表与 runner/磁盘清单、Agent 工具表与注册表、LuaLayout 模块清单、维护文档总索引及应用内完整目录。还检查选定文档的本地链接、HTML 实际标签中的本地资源、帮助目录的中英文目标，以及 BUILDING 的 SDK 数值与构建源码一致。
历史方案正文不参与当前行为核验，总索引保留其入口。检查器不是完整 Markdown/HTML/Lua 解析器，不检查所有锚点或 prose；文件存在不代表行为正确，也不执行动态 `require`、网络、UI 或 API 语义。
若 schema/runner 的声明或发现格式改变，必须同步检查器的静态提取方式；提取不到声明会失败，不会执行源码作为回退。

## 新增套件约定

1. 文件放 `tests/Test<Name>.lua`，首行声明 `local ASSETS = ASSETS or "app/src/main/assets/"`
2. 使用断言或 `check(name, cond)` 计数器；全部成功才打印 `ALL-PASS`，失败抛异常或 `os.exit(1)`，避免仅打印失败日志却返回零
3. 行为套件用 `assert(loadfile(ASSETS .. "<相对路径>"))()` 加载受信的被测模块，依赖用 `package.preload` 注入；纯清单检查不得执行应用源码
4. 临时文件写到 `os.getenv("TEMP")`，用例结束清理
5. 确认 runner 的 `Test*.lua` 自动发现包含新套件；辅助脚本不要使用该文件名前缀
6. 同步本页套件表并运行文档清单检查；不要手写套件/断言总数

## 范围外事项（需要真机）

- **UI 层**：`loadlayout`、`luajava.bindClass`、Fragment/Activity 生命周期、Dialog——
  JSE 没有 Android 渲染；语法与宿主替身测试均不能代替真机
- **Kotlin 层**：`compileDebugKotlin` 通过不代表行为正确；尤其注意本仓库约束——
  **用户打包的 APK 会继承 Java/manifest 层，该层只允许 additive 改动**，动过必须真机回归
- **集成路径**：权限门禁、编辑器↔首页跳转、AI 面板与 AgentTurn 的真实对话流
- **override / dx**：`tests/bench_override.lua` 只在真机跑。桌面最多用 `DexMaker.generate()` 检查字节码能否生成，不能加载 dex，因此覆盖不了 ART 校验和 `superCall` 的实际返回值

## 已知注意事项

- jar 查找顺序见「快速开始」；报 `NoClassDefFoundError: org/luaj/lib/jse/JavaClass`
  说明回退到了 nocglib 版。行为测试要求的 jar 必备项：`org/luaj` 核心 + `LuaC` 编译器
  （必须 luajpp 方言）+ `org/luaj/lib/jse` 平台层；Android 侧类（`com/androlua`、
  `org/luaj/android`）非必需，惰性类加载保证不触碰即无害
- 控制台中文显示乱码多为代码页问题，不影响断言（字符串比较在 JVM 内部按 UTF-8 进行）
- 手动执行单条命令的等价形式：
  ```powershell
  javac -encoding UTF-8 -cp <luajpp.jar> -d tests\out tests\Run.java tests\SyntaxCheck.java
  java -noverify -cp "<luajpp.jar>;tests\out" Run tests\TestTodo.lua
  ```
