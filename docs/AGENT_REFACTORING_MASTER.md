# NeLuaJ+ Agent 架构重构路线图与阶段实施细则（全景规划与推进档案）

> 本文档为 NeLuaJ+ Agent 底层调度、生命周期状态机、UI 渲染管道与 Markdown 排版体系的全生命周期重构指导手册。
> **核心工程原则**：优先复用既有优秀轮子（`com.nekolaska.ktx`、`LuaFileUtil`、`LuaJobWrapper`、`xTask`），彻底消除打补丁掩盖底层缺陷的坏味道。

---

## 目录
1. [阶段一：生命周期、并发调度与状态机加固 (P0) — [已全面完工验收]](#阶段一生命周期并发调度与状态机加固-p0--已全面完工验收)
2. [阶段二：UI 渲染管线工业级重塑 (P1) — [已全面完工验收]](#阶段二ui-渲染管线工业级重塑-p1--已全面完工验收)
3. [阶段三：独立 AST 增量排版引擎演进 (P2) — [本轮规划重点]](#阶段三独立-ast-增量排版引擎演进-p2--本轮规划重点)
4. [质量门禁与全量验证记录](#质量门禁与全量验证记录)

---

# 阶段一：生命周期、并发调度与状态机加固 (P0) — [已全面完工验收]

### 1.1 子代理事件挂起唤醒协调器（`SubagentRunner.lua`）
- 封装 `createSyncEvent()`，内部使用 JSE 标准原生的 `java.util.concurrent.CountDownLatch(1)`；
- Worker 线程调用 `syncEvent.await(180)`，出让 CPU 时间片进入操作系统级挂起（`WAITING`），超时或取消主动联动中断底层的 SSE 流与异步工具，杜绝脱缰后台任务。

### 1.2 并发任务原子追踪下沉（`AgentJobRegistry.kt` & `ToolExecutor.lua`）
- 在 `com.nekolaska.agent.AgentJobRegistry` 下沉线程安全注册表（`ConcurrentHashMap<Any, String>`）；
- 深度对齐工程内置的 `org.luaj.android.LuaJobWrapper` 强类型，纳秒级直接执行 `job.cancel()`；
- 采用 Job 墓碑（Tombstone）机制保留 `cancelled = true`，任务回调触发时静默丢弃残余结果，彻底消除了“取消拦截逃逸”漏洞；
- 将 MCP 异步工具完整纳入统一追踪，清除了逃逸的全局变量。

### 1.3 状态机时空守卫三元组（`AgentTurn.lua`）
- 闭包捕获启动时刻的 `(turnSessionId, turnProjectPath, turnGeneration)`；
- `finishStopped` 与 `executeToolCallsParallel` 路径全量注入 **Fail-Closed 模式** 时空守卫；
- 若已切出会话或工程，过期回调直接拦截丢弃，彻底杜绝跨工程/跨会话串写报废数据。

### 1.4 Markdown 标签闭合算法 $O(1)$ 栈优化（`MarkdownTagHandler.kt`）
- 引入 `kotlin.collections.ArrayDeque<Int>` 专有位置栈，标签打开压入、闭合安全出栈，耗时降为 $O(1)$；
- 严格限定 `start in 0 until output.length`，严密防范流式截断与空标签。

---

# 阶段二：UI 渲染管线工业级重塑 (P1) — [已全面完工验收]

### 2.1 复合卡片流展平器（`MessageItemFlattener.lua`）
- 将 `Session.messages()` 转换为与 UI 渲染一一对应的视觉卡片流（Visual Cards）：
  - `TYPE_USER (0)`：用户输入气泡（带头像与编辑重发操作）；
  - `TYPE_ASSISTANT (1)`：AI 复合消息卡片（思维链折叠 + Markdown/代码块 + 复制/重试操作）；
  - `TYPE_TOOL (2)`：工具调用与返回状态卡片（严格移植了原配对与孤立 Tool 兜底算法）；
  - `TYPE_STREAMING (4)`：独立流式动态卡片；
  - `TYPE_ERROR (5)`：请求错误与完整重试/设置/压缩上下文操作卡片；
  - `TYPE_WELCOME (6)`：空会话首屏引导卡片；
  - `TYPE_SUBTASK (7)`：子代理实时任务进度卡片。
- **稳定 ID（`stableId`）机制**：为每个卡片分配持久确定的 ID（如 `user_1`、`asst_2`、`tool_xxx`），供 `DiffUtil` 毫秒级计算比对。

### 2.2 双模虚拟化容器与交互全量闭环（`ChatUI.lua` & `ai_chat_panel.lua`）
- **真机环境**：优先采用 `RecyclerView` + `AgentChatAdapter`：
  - 接入 `LinearLayoutManager`，禁用默认变更动画（`setSupportsChangeAnimations(false)`）；
  - 刷新历史时直接走 `submitMessages(cards)` 异步增量更新，内存占用恒定，彻底终结了原先 `removeAllViews()` 暴力销毁上千 View 导致的 GC 抖动；
  - **搜索定位闭环**：`jumpToMessage` 适配 `LinearLayoutManager.scrollToPositionWithOffset`，真机搜索点击秒级精准平滑置顶；
  - **智能悬浮按钮闭环**：向 RecyclerView 注册 `OnScrollListener`，回看历史时 `btnJumpLatest` 丝滑弹出，一键直达底部；
  - **流式无闪烁渲染**：流式期间通过专用流式卡片接入，直接拿到当前 TextView 进行节流更新，绝不高频触发 `notifyItemChanged` 或修改 `Session.messages()`，防范任何数据被篡改。
- **单测环境**：保留原 `msgContainer` 降级能力，确保测试挂架无缝通行。

---

# 阶段三：独立 AST 增量排版引擎演进 (P2) — [本轮规划重点]

> **目标**：彻底推翻脆弱的单行正则与不可见控制字符占位符（`\001CODE\002`），构建可脱离 Android Framework 独立运行完备单测的现代不可变 AST 排版引擎，并为移动端带来真正具备列宽自适应与边框能力的表格组件。

### 3.1 为什么必须进行阶段三？（现有正则引擎硬伤）
1. **控制字符占位符魔法（Token Substitution 脏套路）**：
   使用 `\001CODE1\002` 和 `\001LINK1\002` 临时占位，如果用户代码里包含这些字节，或者解析阶段出现交错嵌套，占位符就会裸露在界面上或直接崩溃；
2. **块级嵌套（Block-level Nesting）完全无法处理**：
   单行正则一旦遇到“无序列表嵌套代码块”、“引用内嵌套有序列表”、“列表内多段落换行”，现有的单行正则扫描立即瘫痪；
3. **“空格画表格”是假功能**：
   用 3 个固定空格隔开单元格，在移动端变宽字体下必然错位成一团乱码。

### 3.2 阶段三架构蓝图：Lexer → Parser → Renderer 三层解耦

```
┌───────────────────────────────────────────────────────────────┐
│               MarkdownLexer.lua (词法扫描器)                  │
│       • 逐行/逐字符流扫描，输出标准 Token 序列                │
│       • 0 Android 依赖，纯标准 Lua，可在独立 PC 挂架跑完单测   │
└───────────────────────────────┬───────────────────────────────┘
                                │ Tokens
                                ▼
┌───────────────────────────────────────────────────────────────┐
│               MarkdownAST.lua (语法分析器)                    │
│       • 基于栈与状态机构建不可变语法树 (Block Nodes & Inline) │
│       • 原生支持多层嵌套：Quote -> List -> CodeBlock          │
└───────────────────────────────┬───────────────────────────────┘
                                │ AST 节点树
                                ▼
┌───────────────────────────────────────────────────────────────┐
│           MarkdownSpannedRenderer.lua / TableLayout           │
│       • 普通文本段 -> 映射为挂载现代 Span 的 Spanned 对象     │
│       • 表格节点 -> 映射为原生的自适应网格组件 (TableComponent)│
│         (HorizontalScrollView + TableLayout 带细边框与斑马纹)  │
└───────────────────────────────────────────────────────────────┘
```

### 3.3 详细实施步骤规划

#### 步骤 1：构建纯 Lua 词法扫描器（`mods/agent/markdown/MarkdownLexer.lua`）
- 识别块级开始/结束标记：
  - `HEADING(level, text)`
  - `CODE_BLOCK(lang, code)`
  - `BLOCKQUOTE_START(depth)` / `BLOCKQUOTE_END`
  - `LIST_START(ordered, startNum)` / `LIST_ITEM(indent, text)` / `LIST_END`
  - `TASK_ITEM(checked, text)`
  - `TABLE_START` / `TABLE_ROW(cells)` / `TABLE_END`
  - `THEMATIC_BREAK`（分割线，支持 `---`, `***`, `___` 3 个及以上字符）
  - `PARAGRAPH(text)`

#### 步骤 2：构建行内格式分析器（`mods/agent/markdown/InlineParser.lua`）
- 采用双指针分词算法，替代当前的多次全量正则 `gsub`：
  - 单次扫描匹配：`` `code` ``、`**bold**`、`*italic*`、`~~strike~~`、`[label](url)`；
  - 自动校验词边界，彻底免疫 `snake_case` 变量名损坏；
  - 原生支持嵌套（如 `**粗体中的`代码`和[链接](url)**`），不依赖任何 `\001` 控制字符占位。

#### 3. 真正具备自适应能力的移动端表格（`TableComponent`）
- 当遇到表格节点时：
  - 不再将表格挤在单个 TextView 里用空格模拟；
  - UI 端加载 `TableLayout`，并包裹在 `HorizontalScrollView` 中；
  - 依据表头和数据行自动计算单元格对齐（左对齐/居中/右对齐）；
  - 设置 1dp 细腻分割线与斑马纹底色，支持在手机屏幕上平滑横向滚动，永不错位。

#### 4. 自动化测试套件扩充（`tests/TestMarkdown.lua`）
- 在纯 JVM 挂架中编写 30+ 组针对真实大模型复杂输出的测试用例：
  - 深度块级嵌套测试（引用嵌套列表、列表嵌套代码等）；
  - 复杂行内嵌套测试（粗体嵌套代码与链接等）；
  - 包含管道符 `|` 的表格转义测试；
  - 畸形未闭合 Markdown 容错测试。
- 保证核心 AST 引擎具备 100% 的脱水单测覆盖率。

---

## 四、 质量验证基线
1. 执行 `pwsh -File ./tests/run_tests.ps1` 必须持续保持 **100% 全部通过（ALL-PASS）**；
2. 执行 `./gradlew :app:compileDebugKotlin` 必须保持编译零错误。
