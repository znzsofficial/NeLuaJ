# NeLuaJ+ Agent 系统与渲染体系架构级重构规划

> 基于深度审查结论编写。本规划旨在彻底废弃当前“原型演示级”的补丁式设计，系统性消除并发竞态、线程饥饿、内存泄漏与排版失真，重塑为工业级可靠的移动端 Agent 体系。

---

## 一、 现状核心痛点归因

当前系统的四大核心瓶颈：
1. **调度层（Scheduler）**：`SubagentRunner` 依赖 `while not state.done do sleepMs(200)` 在 Worker 线程忙等轮询，极易引发线程池饥饿与锁死；`ToolExecutor` 单例 `activeJob` 导致并发工具无法被完全取消；
2. **状态机（State Machine）**：`AgentTurn.finishStopped` 与异步工具结果缺少 `generation` 及 `sessionId` 强绑定，导致跨会话串线写入（时空错乱）；
3. **渲染层（UI Pipeline）**：`ChatUI` 使用 `ScrollView + LinearLayout`，每次状态变动均调用 `removeAllViews()` 进行全量视图重建，引发剧烈 GC 抖动与卡顿；高频流式输出（SSE tokens）未作批量缓冲；
4. **排版管道（Markdown Engine）**：基于单行正则缝合 `HtmlCompat`，无法表达复杂块级嵌套；`MarkdownTagHandler` 使用 `getSpans` 导致 $O(N^2)$ 复杂度；表格依赖“拼 3 个空格”排版，字宽不同时必然错位。

---

## 二、 分阶段重构路线图

```
┌────────────────────────────────────────────────────────────────────────┐
│ 阶段一：生命周期、并发调度与状态机加固 (P0 - 消除崩溃、死锁与数据破坏)  │
├────────────────────────────────────────────────────────────────────────┤
│ • 废除 SubagentRunner 阻塞轮询，改为事件通知唤醒驱动                  │
│ • 改造 ToolExecutor 为 activeJobs 集合管理，全量取消并发任务          │
│ • 完善 AgentTurn 回调的 generation 与 sessionId 闭包守卫             │
│ • MarkdownTagHandler 引入显式栈结构，将标签闭合复杂度降为 O(1)         │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 阶段二：UI 渲染管线工业级重塑 (P1 - 彻底根除掉帧与渲染卡顿)            │
├────────────────────────────────────────────────────────────────────────┤
│ • 迁移 ChatUI 对话列表至 RecyclerView + ListAdapter (DiffUtil)         │
│ • 消息气泡实现多 ViewType 模板化复用（用户、思考、文本、代码、工具卡片） │
│ • 流式输出（SSE）引入无锁环形缓冲（Ring-Buffer）与帧率脉冲批量刷新    │
│ • 单次分词扫描（Tokenizer）替代主线程多轮正则代码高亮                  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 阶段三：独立 AST 增量排版引擎演进 (P2 - 达到现代桌面/IDE 级排版质感)     │
├────────────────────────────────────────────────────────────────────────┤
│ • 废除脆弱正则，构建轻量状态机 Lexer/Parser，输出不可变 AST 结构       │
│ • 表格迁移至独立块级组件（HorizontalScrollView + 自适应 TableLayout）  │
│ • 支持多层块级嵌套（列表嵌套代码块、引用嵌套清单等）规范化渲染         │
│ • 分离 Parser 与 Spanned 适配层，实现核心排版 100% 独立单测覆盖        │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 三、 各阶段详细设计与实施清单

### 阶段一：生命周期、并发调度与状态机加固（首要推进）

#### 1.1 根除 `SubagentRunner.lua` 的阻塞忙等
- **原代码缺陷**：`while not state.done do sleepMs(200) end`（第 249–251 行）在后台线程忙等轮询，独占 Worker 线程，单例 `current` 锁死并发。
- **重构方案**：
  - 将子代理任务调度改为非阻塞模型：主代理发起子任务时，向调度上下文注册带有 `taskId` 的完成回调；
  - 移除 `sleepMs` 忙等循环与模块级全局单例 `current`，以 `activeSubagents[taskId]` 表进行多任务生命周期跟踪；
  - 子代理完成时通过 Event 回调主动唤醒宿主并传递结果。

#### 1.2 `ToolExecutor.lua` 多任务并发取消追踪
- **原代码缺陷**：`local activeJob` 单例变量（第 5 行）在并发执行多个只读工具时被反复覆盖，用户点击停止时仅能取消最后一个任务。
- **重构方案**：
  - 改造为集合管理：`local activeJobs = {}`；
  - `executeToolAsync` 时向集合注册：`activeJobs[job] = name`；
  - 任务正常完成或异常时，在 finally 块中从集合剔除；
  - `cancelPending()` 遍历集合中所有的活跃 Job 执行 `.cancel()`，并清空集合。

#### 1.3 `AgentTurn.lua` 时空错乱彻底防御
- **原代码缺陷**：`finishStopped` 及部分工具异步回调未核对请求所属的 `generation` 与 `sessionId`，在用户快速切会话时将回执误写入新会话。
- **重构方案**：
  - 每一个发起的 Turn 均显式闭包捕获当前的 `turnSessionId = Session.id()` 与 `turnGeneration = generation`；
  - 所有网络请求返回、流式分块、工具完成及 `finishStopped` 回调进入时，严格执行守卫：
    ```lua
    if Session.id() ~= turnSessionId or generation ~= turnGeneration then
      return -- 丢弃过期/失效的幽灵回调，绝不落盘
    end
    ```

#### 1.4 `MarkdownTagHandler.kt` 闭合标签 $O(1)$ 栈优化
- **原代码缺陷**：`getLatestMark` 使用 `output.getSpans(0, output.length, ...).lastOrNull()` 进行全量线性扫描，时间复杂度为 $O(N^2)$。
- **重构方案**：
  - 移除对整个文档的 `getSpans` 线性查找；
  - 内部为每种标签维护独立的 `ArrayDeque<Int>`（记录 opening 索引位置栈）；
  - `opening = true` 时：直接将 `output.length` 压栈；
  - `opening = false` 时：直接从栈顶弹出起始位置，并对 `[start, output.length]` 挂载 Span，将时间复杂度从 $O(N^2)$ 永久降为 $O(1)$。

---

### 阶段二：UI 渲染管线工业级重塑

#### 2.1 迁移到 `RecyclerView` 虚拟化容器
- **重构方案**：
  - 彻底淘汰 `ScrollView + LinearLayout` 以及全量 `removeAllViews()` 刷新；
  - 定义清晰的 `ItemViewType`：
    - `TYPE_USER_BUBBLE`：用户输入气泡
    - `TYPE_AI_THINKING`：思维链折叠卡片
    - `TYPE_AI_TEXT`：AI 格式化 Markdown 文本段
    - `TYPE_AI_CODE_CARD`：带语言标签与操作栏的代码块卡片
    - `TYPE_AI_TOOL`：工具调用/返回状态卡片
    - `TYPE_AI_TODO`：任务规划清单卡片
  - 使用 `LuaRecyclerAdapter` 结合增量数据更新，仅重绘变动项，大幅降低内存与 CPU 开销。

#### 2.2 流式文本平滑 Ring-Buffer 吞吐
- **重构方案**：
  - 避免每个 SSE chunk 触发一次测量重绘；
  - 引入微型时间窗口缓冲（如 60ms 批处理）：在缓冲区内累积收到的字符串分块，仅在 Choreographer VSYNC 或时间到达时批量通知 UI 进行一次文本更新与视口推进。

---

### 阶段三：独立 AST 增量排版引擎演进

#### 3.1 淘汰单行脆弱正则，引入轻量状态机
- **重构方案**：
  - 构建分词扫描器（Lexer），将 Markdown 拆分为 Block Tokens（Paragraph, CodeBlock, Table, List, Quote）与 Inline Tokens（Text, Code, Strong, Em, Link）；
  - 基于语法树（AST）统一处理嵌套格式，彻底解决不可见控制字符占位符魔法（`\001CODE\002`）与错误交错嵌套。

#### 3.2 真正具备排版能力的自适应表格
- **重构方案**：
  - 废弃“在单行内加 3 个空格”的假表格；
  - 将表格作为独立块级节点输出，在 UI 端由原生 `HorizontalScrollView` + `TableLayout` 承载，或者通过轻量 Canvas 绘制带边框与斑马纹的自适应 Grid 控件。

---

## 四、 风险控制与自动化验证基线

1. **测试套件保障**：重构每一步均必须严格保持 `./tests/run_tests.ps1` 全套 13 个独立测试套件 100% PASS，并在 `TestSubagent` 与 `TestAgentTurn` 补充并发取消与时空守卫用例。
2. **渐进式迁移**：阶段一优先在现有模块内进行非侵入式热点重构，确保零 API 破坏；阶段二和三平滑切换底层容器。
