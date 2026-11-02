# Agent 重构实现状态

本文是重构范围和验证边界的摘要；Agent 当前模块、协议及存储以
[AIAgent.md](./AIAgent.md) 为主要入口，首页交接以 [HOME.md](./HOME.md) 为准。
不将设计目标或测试通过等同于完整验收。旧方案见
`AGENT_REFACTORING_PLAN.md`、`PHASE_1_REFACTORING_SPEC.md` 和
`PHASE_2_REFACTORING_SPEC.md`；其中的双模容器等设计已不再采用。

## 调度、取消与回合状态

- `SubagentRunner.lua` 在工具线程等待 `CountDownLatch`，步骤由主线程推进。
  仍是单个子代理、阻塞等待模型，不是多子代理异步调度器。
- 子代理取消/超时会终结状态并取消持有的请求和工具句柄；旧确认、重复结果、
  旧请求的用量回调不再执行。进度通知投递到主线程。
- `OpenAIClient.sendStream()` 返回可取消的请求状态；已经结束的句柄不会再取消新请求。
- `ToolExecutor.lua` 仅保留活跃任务。取消前分离批次并标记闭包中的取消状态，
  不依赖取消后一定存在的完成回调清理条目。
- `AgentJobRegistry.kt` 使用锁原子分离取消批次，随后在锁外执行取消；
  取消期间注册的新任务仍留在下一批次中。它不是事务性、跨模块的统一取消屏障。
- `AgentTurn.lua` 用工程、会话和 generation 守卫回调；并行停止保留已收到结果，
  为未完成工具补停止结果。重试及强制压缩重试具有显式入口。

## UI 与列表

- 对话列表只使用 `RecyclerView`，没有生产或单测 `msgContainer` 降级分支。
- `MessageItemFlattener.lua` 生成复合卡片。`AgentChatAdapter.kt` 使用比较快照和
  `DiffUtil` 发出增量通知，流式文本更新数据源后通过 payload 刷新。
- 数据更新在主线程执行，布局计算期间按序延后；回收时释放流式 View 引用。
- 完整重绑定仍会重建单个复合气泡，并非每个 Markdown 块都有独立 ViewHolder。
- 任务计划条随消息刷新读取已提交的 TodoManager 状态。
- 尚未实现 VSYNC/Ring-Buffer 合批；没有提供恒定总内存或 60 FPS 的实测保证。

## Markdown 与协议

- `MarkdownAST.lua` 是轻量块扫描器，识别普通文本、围栏代码和管道表格；
  不是完整 CommonMark 语法树，也没有完整的嵌套列表/引用解析。
- `MarkdownInline.lua` 识别代码、链接与基本强调；内部仍使用占位符和部分正则。
- 原生表格支持对齐、斑马纹、行内格式、链接及每次 30 行展开。
  创建失败时以完整原文降级；表格内部并未虚拟化。
- `MarkdownTagHandler.kt` 对自定义标签的闭合位置采用独立栈；
  O(1) 指栈查找，不是整个 Markdown 渲染的复杂度。
- 请求层保留续写上下文、过滤内部字段，并对工具参数做 JSON 对象校验。
  模型/中转站的实机兼容性仍须分别验证。

## 验证边界

- Lua 测试覆盖回合归属、重试、并行停止、取消清理、超时后确认失效、
  请求句柄、Markdown 解析、表格降级及展开等行为。
- JVM 测试覆盖比较快照、Diff 通知、原生任务注册表并发取消等逻辑。
- `testDebugUnitTest` 是本地 JVM 测试，Android Framework 行为有桩限制；
  `assembleDebug` 通过只代表构建成功。
- 仍需真机验证：快速切会话、后台/销毁、停止与确认交错、长列表滚动、
  IME、Markdown 视觉效果和各网关请求。未经实测不标注“全面验收”或“100% 覆盖”。
