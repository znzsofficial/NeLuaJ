# 工具任务执行与诊断

本文维护内置 Agent 与子代理的任务执行契约。工具清单、批准策略和模型协议见
[AIAgent.md](./AIAgent.md)；文件持久化见 [FILE_MUTATIONS.md](./FILE_MUTATIONS.md)；
外部助手连接手机工程见 [MCP_SERVER.md](./MCP_SERVER.md)。对外 MCP 服务不经过这里的聊天任务注册表。

## 执行边界

`ToolExecutor.executeToolAsync(name, args, onResult, options)` 是聊天和子代理工具的统一异步入口。
工具算法仍由原模块执行；文件写入仍由 `FileMutationService` 与 `FileMutationEngine` 承担版本校验、日志、提交和恢复。
普通工具使用 xTask，文件任务使用进程级 FileMutationDispatcher，MCP 使用独立调用资源组。

返回 handle 提供 `taskId`、`cancel(reason)`、`getSnapshot()`。完成回调为
`onResult(text, ok, effects, taskInfo)`，前三项保持原契约；第四项是任务元数据，不是文件事务结果。

可选 options：

- `scope = {projectPath, conversationId, generation}`：异步结果归属。
- `toolCallId`：模型协议配对 ID；不同于本地 taskId 和文件 transactionId。
- `parentId`：父任务 ID；子代理工具继承父任务的 scope。
- `timeoutMs`：等待期限。
- `onWaitEnd(taskInfo)`：超时结束等待，停止工具轮，而不是恢复模型自动续跑。
- `onLateFileResult(text, ok, fileResult, childTaskInfo, parentTaskInfo)`：子代理已结束后的文件事实回传。它是独立事件，不是父任务第二次完成。

`run_subtask` 内部上下文单独传递，不拼入模型工具参数或 MCP 请求。

`ToolExecutor.cancelJob(handle, reason)` 取消一个任务，`cancelScope(scope, reason)` 按提供的 scope 字段匹配，
`cancelPending()` 请求取消当前执行器的全部活跃任务。身份字段完整保留，不能用展示截断值参与 scope 比较。

## 状态与取消

TaskRegistry 分开记录执行与等待：

- `executionState`：queued、running、settled、unknown。running 表示已派发，非精确磁盘提交阶段；unknown 表示取消后无法确认执行结果。
- `waitState`：waiting、completed、cancelled、timed_out。
- `cancelReason`：白名单原因，不存错误正文。
- `transactionId`：文件事务关联；最终以事务返回值为准。

停止等待不证明操作未执行。文件取消只设置协作标记，已开始发布的事务继续完成或补偿，真实结果仍会回调。
当前会话内，停止占位会被迟到文件事实原位更新，不重复新增 tool output，也不恢复模型续跑；作用域失效后不能写入新会话。
子代理超时只结束子代理等待；迟到文件事实经独立事件按 transactionId 去重，写入原父工具消息的 `child_file_results` 并补充摘要，保留父任务失败状态。scope 失效后不写新会话；文件事务记录仍可恢复。

取消一个任务只取消它拥有的底层 handle；MCP 的资源组覆盖初始化、HTTP 调用、重试和对应 SSE 响应等待，不能关闭兄弟任务共享的 SSE 连接。
全局 MCP shutdown/configuration change 仍允许取消所有请求。网络取消不能证明远端未执行，不自动重试未知副作用。
fetch/sandbox 等既有同步平台能力仍为 best-effort：不通过全局取消误伤其他任务，也不宣称取消协程等于停止底层运算。

## 期限与线程

默认等待 120 秒；子代理工具 190 秒（子代理自身等待 180 秒），构建工具 300 秒。可由调用级 options 覆盖。
TaskRuntime 使用主线程 Handler 和 uptimeMillis 同一时间基准，深度睡眠与主线程拥塞会延后超时回调；它不是系统级实时截止机制。
任务记录只在 owner/main 线程更新，后台结果投递回来；文件发布不由定时器强行中断。
定时器安装失败明确返回启动失败，完成或取消后移除同一个 Runnable 实例。

## 诊断

`AgentChat.getTaskSnapshot(taskId)` 与 `AgentChat.getTaskDiagnostics()` 返回脱离内部表的快照。
记录任务名、父子 ID、scope、时间戳、耗时、状态、取消原因、事务 ID、成功标志；不保存工具参数、结果正文或认证头。
默认保留最近 128 个已退休任务，诊断查询最多返回 128 条；尚未完成的文件事务继续跟踪到真实结果到达。
这个上限约束已退休历史和单次查询，不承诺所有未完成任务的总内存有界；进程重启后内存诊断不会恢复。
TaskRuntime 通过 logcat 的 `AgentTask` 标签记录 created/wait_ended/settled 事件，只输出固定元数据字段，不输出工程路径和会话内容。
`task_info` 随会话工具消息保存；请求模型时由协议层字段白名单过滤。

## 排查“工具卡住”

| 现象 | 检查与解释 |
|---|---|
| UI 仍等待工具 | 用 taskId 查 snapshot，区分尚在等待、超时和已收到结果；running 只表示已派发 |
| 显示已停止，但文件后来变化 | 查看 transactionId 与 file_result；停止等待不撤销已开始的提交 |
| 父子任务结果不一致 | 查看 parentId 和 child_file_results；子文件提交成功不代表整个父任务成功 |
| 文件已提交，编辑器尚未更新 | 检查同步警告并走文件恢复；不要为刷新界面重新执行写入 |
| MCP 断连或超时 | 远端结果可能未知；不要把本地取消当作远端回滚证明 |

需要网络故障细节时结合原调用错误；诊断日志有意不包含参数和响应正文。日志标签 `AgentTask` 可按 taskId 关联 created、wait_ended 和 settled 事件。

## 验证范围

纯 Lua 测试覆盖任务状态、定时器安装/清理、重复回调、取消重入、父子任务、停止占位和迟到事实。
JVM MCP 测试使用本地 HTTP/SSE 连接验证单任务取消、响应等待唤醒和兄弟调用继续。
Android 真机仍需验收：主线程拥塞、后台休眠、Activity 销毁/重建、执行中切会话及停止后编辑器刷新。

2026-11-10 桌面验证：Lua 全套、全部 JVM 单元测试、Debug 构建和文档清单检查通过；
子代理复审发现的并行取消、身份截断、SSE 接管、混合协议元数据及迟到子事务承接问题已修复并复核。
这不是上述真机场景的验收记录。测试命令与套件清单统一维护在 [tests/README.md](../tests/README.md)。
