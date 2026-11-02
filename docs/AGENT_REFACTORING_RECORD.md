# NeLuaJ+ Agent 系统与渲染体系架构级重构规划与实施记录

> **历史阶段记录，非当前验收报告。** 以下“已完工 100%”“彻底消除”等表述
> 是当时的结论，后续补审发现遗漏，不能作为质量保证。当前实现与验证边界以
> `AGENT_REFACTORING_MASTER.md` 为准。注册表已改为锁内分离批次、锁外取消；
> Lua 侧不再保留取消任务墓碑；并行停止、错误重试及过期确认已增加明确收口。
> 原有测试数量仅对应当时运行，不表示当前覆盖率。

> 本文档用于记录 Agent 调度底层、生命周期状态机、UI 渲染管道与 Markdown 排版体系的完整重构演进。
> **核心原则**：充分复用工程既有轮子（`com.nekolaska.ktx`、`LuaFileUtil`、`LuaJobWrapper`、`xTask`），绝不重复造轮子，严禁以打补丁掩盖底层架构缺陷。

---

## 一、 现状核心痛点归因（深度审查结论）

1. **调度层（Scheduler）**：
   - 原 `SubagentRunner` 在 Worker 线程中使用 `while not done do sleepMs(200)` 进行忙等轮询，极易引发 CPU 电池刺客与线程池饥饿死锁；
   - 原 `ToolExecutor` 采用 `local activeJob` 单例变量，导致并发只读工具批次派发时被反复覆盖，用户点击停止时先发任务脱缰。
2. **状态机（State Machine）**：
   - 原 `AgentTurn.finishStopped` 与异步工具结果缺少 `(turnSessionId, turnProjectPath, turnGeneration)` 三元组锁死，用户急切切换会话时，过期或停止回执被串写进新会话，导致后续 API 抛 400 校验错误。
3. **UI 渲染管线（UI Pipeline）**：
   - `ChatUI` 使用 `ScrollView + LinearLayout`，状态变动时使用 `removeAllViews()` 暴力全量重建视图树，带来剧烈 GC Thrashing 与帧率暴跌；
   - 高频流式输出（SSE tokens）与搜索输入无节流防抖机制。
4. **排版管道（Markdown Engine）**：
   - 基于单行脆弱正则缝合 `HtmlCompat`，多层块级嵌套易错乱；
   - `MarkdownTagHandler` 采用全局 `getSpans` 线性扫描，复杂度跌入 $O(N^2)$；
   - 表格排版依赖硬编码 3 个空格，比例字体下字符宽度不等必然错位。

---

## 二、 既有基础设施与复用规范（禁止重复造轮子）

经全面排查，工程内已存在完备的高性能轮子，后续重构必须强制优先对齐复用：

1. **`com.nekolaska.ktx.LuaValueExtension.kt`**：
   - Kotlin 调用 Lua 函数：直接调用 `luaValue.callLua(...)` 或 `luaValue.invokeLua(...)`；
   - 快速转值：`any.toLuaValue()`、`string.toLuaString()`、`list.toVarargs()`；
   - 安全检查：`luaValue.ifIsFunction()`、`luaValue.toJavaOrNull<T>()`。
2. **`org.luaj.android.xTask.kt`（含 `LuaJobWrapper`）**：
   - 后台任务与协程调度的中枢，内置 `job.cancel()`、`job.isActive()`、`job.isGc()`；
   - 并发任务注册直接对齐 `LuaJobWrapper` 强类型，消除无谓反射。
3. **`com.nekolaska.ktx.LuaValueFix.kt`**：
   - 官方适配的 LuaJ 混淆字段直接访问层（`bytes`, `offset`, `packageLib` 等），严禁在 Kotlin 内部写盲猜反射。
4. **`com.nekolaska.io.LuaFileUtil.kt`**：
   - 原子替换写入（`replaceText` / `writeOrCreate`），内置同目录临时文件原子替换与 `fsync` 刷盘，会话持久化与文件导出强制复用。

---

## 三、 分阶段重构路线与实施进度记录

```
┌────────────────────────────────────────────────────────────────────────┐
│ 阶段一：生命周期、并发调度与状态机加固 (P0)              [已完工 100%] │
├────────────────────────────────────────────────────────────────────────┤
│ ✓ 接入 CountDownLatch 轻量同步原语，彻底废除 Subagent 忙等轮询与死锁    │
│ ✓ 新增 AgentJobRegistry，深度复用 LuaJobWrapper 强类型，实现原子级全量取消 │
│ ✓ 注入 (turnSessionId, turnProjectPath, turnGeneration) 三元组时空守卫 │
│ ✓ 重构 MarkdownTagHandler 为 ArrayDeque 栈模型，闭合耗时降为 O(1)      │
│ ✓ 会话导出彻底重构为真实本地文件写入 + FileProvider 授权分享（无限制） │
│ ✓ 增加搜索防抖 (250ms) 与流式输出滚动节流 (100ms)                      │
│ ✓ 表单 Positive 按钮接管拦截，未填必填项时阻止 Dismiss 保护草稿         │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 阶段二：UI 渲染管线工业级重塑 (P1)                      [规划待推进]   │
├────────────────────────────────────────────────────────────────────────┤
│ • 迁移 ChatUI 对话列表至 RecyclerView + ListAdapter (DiffUtil)         │
│ • 消息气泡拆分模板化 ItemViewType（用户气泡/思考/文本/代码卡片/工具）  │
│ • 流式输出（SSE）引入无锁环形缓冲（Ring-Buffer）与 VSYNC 批量刷新      │
│ • 禁用 RecyclerView 默认变更动画，消除打字流式闪烁                     │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 阶段三：独立 AST 增量排版引擎演进 (P2)                  [规划待推进]   │
├────────────────────────────────────────────────────────────────────────┤
│ • 淘汰单行脆弱正则，引入轻量状态机 Lexer/Parser，输出不可变 AST 树      │
│ • 真正具备自适应排版能力的块级表格（HorizontalScrollView + TableLayout）│
│ • 解耦语法分析层与 Android Spanned 适配层，实现核心排版 100% 单测覆盖 │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 四、 阶段一实施明细与对齐记录（Audit Trail）

### 4.1 `SubagentRunner.lua` 同步挂起升级
- **实现位置**：`app/src/main/assets/mods/agent/SubagentRunner.lua`
- **实施细节**：
  - 封装 `createSyncEvent()`：在运行时直接使用 Java JSE 原生标准的 `java.util.concurrent.CountDownLatch(1)`；
  - Worker 线程调用 `syncEvent.await(180)` 进入操作系统级挂起（`WAITING`），完全出让 CPU 时间片；
  - 任务在主线程完成时调用 `syncEvent.notify()`（`latch.countDown()`）精准唤醒；
  - 兼容单测挂架：检测到单测同步完成时直接穿透返回，现有 13 套单测 100% 全绿通行。

### 4.2 `AgentJobRegistry.kt` 与 `ToolExecutor.lua` 并发取消加固
- **实现位置**：
  - `app/src/main/java/com/nekolaska/agent/AgentJobRegistry.kt`
  - `app/src/main/assets/mods/agent/ToolExecutor.lua`
- **实施细节**：
  - `AgentJobRegistry` 内部维护 `ConcurrentHashMap<Any, String>`；
  - 取消时直接解包 `LuaJobWrapper` 强类型执行 `job.cancel()`，消除反射；
  - `cancelAll()` 返回 `List<String>`（被取消工具名），彻底规避 Kotlin 高阶函数在 LuaJava 反射中的阻抗；
  - 任务回调返回时核对 `entry.cancelled`，已取消任务静默丢弃，严禁污染业务流。

### 4.3 `AgentTurn.lua` 时空错乱彻底防御
- **实现位置**：`app/src/main/assets/mods/agent/AgentTurn.lua`
- **实施细节**：
  - 闭包捕获启动时刻的 `(turnSessionId, turnProjectPath, turnGeneration)`；
  - `finishStopped` 与异步工具结果回调进入时调用 `isCurrentScope(turnScope)`；
  - 若用户在运行中切换了会话或工程，过期回调直接拦截丢弃，杜绝跨会话串写报废数据。

### 4.4 `MarkdownTagHandler.kt` $O(1)$ 栈优化与 DPI 动态适配
- **实现位置**：`app/src/main/java/com/nekolaska/ai/MarkdownTagHandler.kt`
- **实施细节**：
  - 采用标准 `kotlin.collections.ArrayDeque<Int>` 专有栈记录开启标签下标；
  - 标签闭合时安全出栈 `stack.removeLastOrNull()`，并严密校验 `start in 0 until output.length`；
  - 构造函数传入当前屏幕 `density`，线条厚度与呼吸间距自适应屏幕分辨率；
  - 闭合标签查找时间复杂度降为 $O(1)$。

### 4.5 真实文件导出与交互体验加固
- **会话导出**：废除纯内存 Intent 塞字符串，重构为写外部缓存 `.md` 文件 + `FileProvider` 授权流分享，彻底解除 100KB 与 1MB Binder 限制；
- **防抖与节流**：搜索输入增加 `250ms` 防抖，流式输出增加 `100ms` 滚动节流；
- **表单草稿保护**：Provider 与 Model 表单接管 Positive 按钮点击，校验失败保持弹窗常驻；
- **交互收口**：标题栏补充关闭按钮，多行输入框恢复 Enter 换行功能。

---

## 五、 质量验证结果

1. **纯 Lua 挂架单元测试**：
   - 指令：`pwsh -ExecutionPolicy Bypass -File ./tests/run_tests.ps1`
   - 结果：**13/13 测试套件 100% 全部通过（ALL SUITES PASS）**。
2. **Kotlin 原生编译**：
   - 指令：`./gradlew :app:compileDebugKotlin --rerun-tasks`
   - 结果：**BUILD SUCCESSFUL，零错误**。
3. **跨语言测试验证**：
   - 指令：`./gradlew :app:testDebugUnitTest --tests com.nekolaska.test.LuaFunction1InteropTest`
   - 结果：验证通过，LuaJ++ 深度适配动态代理与类型桥接。
