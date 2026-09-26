# 内置 AI Agent

NeLuaJ+ 的内置 AI 助手是面向当前工程的编码 Agent。当前实现同时支持 OpenAI 兼容的 Chat Completions 和 Responses 流式接口，具备工程文件工具、隔离 Lua 沙盒、公开网页读取、MCP 工具、本地 Skill、上下文压缩和文件变更撤销能力；回合状态机（`AgentTurn`）驱动工具循环（默认不限轮数，设置项 `ai_max_rounds` 可封顶），只读工具批量并行，`run_subtask` 可派生隔离子代理，`update_todos` 维护任务计划，`run_project` / `build_project` 覆盖运行与打包交接。

本文描述当前代码行为。用户可见说明位于：

- `app/src/main/assets/res/doc/agent_zh.html`
- `app/src/main/assets/res/doc/agent_en.html`
- `app/src/main/assets/res/doc/sandbox_zh.html`
- `app/src/main/assets/res/doc/sandbox_en.html`
- `app/src/main/assets/res/doc/agent_docs.md`

## 功能入口

- `app/src/main/assets/activities/main/Actions.lua` 打开 AI 助手。
- `mods/agent/ChatUI.lua` 创建并展示全高 `BottomSheetDialog`。
- `res/layout/ai_chat_panel.lua` 定义聊天面板、消息区、输入区和操作按钮。
- 打开面板时会异步预取 MCP 工具，避免在主线程进行网络请求。
- 关闭面板只保存会话，不取消正在执行的模型请求或工具链；重新打开后会重建消息并继续显示内存中的流式响应。

## 模块结构

### Lua 层

| 文件 | 职责 |
|------|------|
| `mods/agent/AgentChat.lua` | 组合根：内置系统提示词、20 个工具 schema、平台工具实现、编辑器上下文，以及各子模块依赖注入 |
| `mods/agent/AgentTurn.lua` | 回合状态机：generation 守卫、加载状态、keepalive、压缩触发、请求生命周期与工具循环；只读白名单工具组成并行批 |
| `mods/agent/ChatUI.lua` | 聊天面板装配、流式渲染入口、确认对话框、会话/模型/MCP/设置管理入口 |
| `mods/agent/BubbleRenderer.lua` | 消息、待办计划、子代理进度、工具调用气泡的构建 |
| `mods/agent/Markdown.lua` | 气泡 Markdown 渲染（标题、列表、表格、任务列表、分隔线、行内代码等） |
| `mods/agent/ModelRegistry.lua` | 供应商/模型多配置注册表：增删改、当前模型指针、辅助模型按身份持久化、旧单模型配置迁移 |
| `mods/agent/PatchEngine.lua` | 多格式补丁应用：SEARCH/REPLACE 块、Unified Diff、整文件替换 |
| `mods/agent/ConversationStore.lua` | 会话持久化：稳定 ID、工程作用域、工程→会话映射、轻量索引 |
| `mods/agent/ConvList.lua` / `ConvUi.lua` | 会话列表行渲染与新建/切换/重命名/删除/搜索管理界面 |
| `mods/agent/SettingsUi.lua` | 供应商/模型/参数/AI 偏好设置对话框 |
| `mods/agent/SubagentRunner.lua` | `run_subtask` 隔离子代理执行：独立上下文、进度实时上报、取消传播、结果截断 |
| `mods/agent/TodoManager.lua` | `update_todos` 任务计划：校验、归一化、持久化到会话与提示词注入 |
| `mods/agent/ContextManager.lua` | token 粗略估算、上下文预算、工具调用链成组裁剪、自动和手动摘要压缩 |
| `mods/agent/OpenAIProtocol.lua` | Chat Completions / Responses 请求编码、端点和服务商适配、历史修复、结构化工具调用解析 |
| `mods/agent/OpenAIClient.lua` | 单次模型请求生命周期、流式回调、自动重试、错误分类和取消 |
| `mods/agent/ToolExecutor.lua` | 工具名规范化、参数冻结、后台调度、项目作用域检查、并行安全判定、批准策略、MCP 路由和取消 |
| `mods/agent/MCPProtocol.lua` | MCP 协议版本、JSON-RPC/SSE 解码、工具参数请求头等无状态协议辅助逻辑 |
| `mods/agent/MCPClient.lua` | MCP 配置、协议协商、会话兼容、工具发现/缓存/调用和异步刷新 |
| `mods/agent/ChangeSet.lua` | 文件变更前后快照、fingerprint 冲突检测、事务回滚、撤销和恢复 |
| `mods/agent/AgentStorage.lua` | 工程级 Agent 外部存储、工程哈希、锁和临时文件/备份原子写入 |
| `mods/agent/SkillManager.lua` | 本地 `SKILL.md` 扫描、优先级合并、关键词匹配和提示词注入 |
| `mods/agent/TextUtil.lua` | UTF-8 安全截断、token 数格式化等共享文本工具 |
| `mods/utils/LuaKV.lua` | 目录型 KV 存储引擎：每键一文件、tmp+rename 原子写、键名白名单编码；会话记录的存储底座 |

### Kotlin 层

| 文件 | 职责 |
|------|------|
| `com/nekolaska/ai/AiHttpClient.kt` | 模型 HTTP/SSE 传输，解析 Chat 和 Responses 流式事件并回调 Lua UI |
| `com/nekolaska/ai/ResponsesStreamState.kt` | 关联 Responses 输出项、function call、参数增量和完整输出 |
| `com/nekolaska/ai/AgentFetch.kt` | `fetch_url` 的只读公网 HTTPS 传输和重定向校验 |
| `com/nekolaska/ai/MarkdownTagHandler.kt` | `HtmlCompat.fromHtml` 的表格与分隔线 TagHandler，供 Markdown.lua 使用 |
| `com/nekolaska/mcp/McpHttpClient.kt` | MCP Streamable HTTP、旧版 HTTP+SSE、请求取消和 URL 校验 |
| `com/androlua/LuaSandbox.kt` | 沙盒调用入口、跨进程结果等待、超时和输出限制 |
| `com/androlua/LuaSandboxService.kt` | 私有 `:lua_sandbox` 进程中的语法检查和代码执行服务 |
| `com/androlua/SandboxLibraries.kt` | 沙盒内的 JSON、编码、摘要、检查和断言 API |
| `com/androlua/SandboxHttp.kt` | 沙盒 `http.request` 的主机授权、公网 DNS、请求和响应限制 |

## 请求流程

1. 用户发送消息时，`ChatUI.sendMessage()` 先按文本匹配当前 Skill，并只持久化用户原始输入。
2. `AgentChat.buildContext()` 为本次请求临时加入当前文件、项目路径、选中代码、最多 5000 字符的编辑器内容、可见编译错误和工程顶层文件名。该副本不会写入会话历史。
3. `ContextManager` 加入当前系统提示词，并按模型上下文窗口构建请求历史。`assistant.tool_calls` 与紧随其后的 `tool` 结果作为不可拆分单元裁剪。
4. 历史超预算时，较早内容会通过同一模型、禁用工具的摘要请求压缩；失败时回退到最近历史裁剪。
5. `OpenAIProtocol` 合并内置工具和当前已缓存的 MCP 工具，设置 `tool_choice = "auto"`，并编码为 Chat Completions 或 Responses 请求。
6. `AiHttpClient` 在后台读取 SSE，在主线程增量更新 UI，并汇总文本、reasoning、结构化工具调用、Responses 原始输出和 incomplete 状态。
7. 模型返回工具调用后，assistant 消息先持久化。`AgentTurn` 将连续的只读白名单工具（`read_file`、`read_files`、`list_dir`、`search_in_files`、`check_lua_syntax`、`get_env_info`）组成并行批并发执行，其余工具按序串行；每个结果完成后立即持久化。
8. 工具结果全部完成后发起下一轮模型请求。工具循环默认没有硬上限（由用户停止或模型结束调用）；可在设置中配置每回合工具轮数上限（`ai_max_rounds`），超出后回合结束并提示，子代理轮次同用此上限。
9. 最终文本、停止状态、不完整状态、工具后空响应和请求错误都会保存到会话，以支持重开面板、继续或恢复操作。

## 系统提示词与文档

内置提示词位于 `AgentChat.lua` 的 `SYSTEM_PROMPT`。指令优先级为：

1. 内置规则与安全边界。
2. 用户当前明确要求。
3. 设置中的附加指令 `ai_system_prompt`。
4. 当前匹配的本地 Skill。

项目文件、注释、编辑器文本、内置文档、错误信息、网页、MCP 返回值和工具结果都被声明为待分析数据，不能覆盖更高优先级指令。

- NeLuaJ+ API 不确定时，模型应先读取 `res/doc/agent_docs.md`，再读取对应文档和工程现有用法。
- `activity.getLuaDir()/res/doc` 下的文档是可信只读路径；仅 `read_file` 和 `read_files` 可因此免确认，信任不会扩展到写入、删除、目录遍历或应用其他私有文件。
- 当前会话首次调用 `run_lua` 前，提示词和工具描述要求先读取 `res/doc/sandbox_zh.html`；英文对话读取 `res/doc/sandbox_en.html`。文档已在上下文中时无需重复读取。
- 沙盒文档前置读取是运行时硬门禁：执行器记录本次进程内是否通过 `read_file` / `read_files` 读过受信 `res/doc` 根下的 `sandbox_*.html`，未读过时 `run_lua` 需要确认（即使沙盒自动运行开启）。该标记进程级共享，切换会话不重置；工程内自建的同名文件不满足条件。

## 模型与协议

每个模型配置包含：

```text
name, url, key, model, responses, contextLength, maxTokens
```

- `responses = false` 使用流式 `/chat/completions`。
- `responses = true` 使用流式 `/responses`。
- API 地址可以填写根地址或完整终端地址；端点归一化会保留 query string，并处理普通 OpenAI 兼容地址、Azure OpenAI 和 DeepSeek Responses 地址差异。
- Azure OpenAI 和 Xiaomi MiMo（按量付费与 Token Plan）使用 `api-key` 请求头，其他端点使用 Bearer token。MiMo 的 Chat Completions 请求使用 `max_completion_tokens`，并在后续轮次保留 `reasoning_content`。Token Plan 地址包括 `token-plan-cn`、`token-plan-sgp` 和 `token-plan-ams`。MiMo 没有公开的余额接口。
- 官方 OpenAI 的 GPT-5、o1、o3 和 o4 系列，以及 xAI 的 Grok 4、Grok 3 Mini、Grok Code，请求会省略不支持的 `temperature`。
- Grok Responses 使用 `https://api.x.ai/v1/responses`。请求带 `include: ["reasoning.encrypted_content"]`，并把完整 output 回放给同一 origin。流式解析同时接收 `response.reasoning_text.delta` 和 `response.reasoning_summary_text.delta`。
- Chat 模式兼容 `tool_calls`、单个 `tool_call`、旧 `function_call`、部分中转服务的 completed message，以及 `reasoning` / `reasoning_content`。
- Responses 模式处理 `response.*` 事件、输出文本、reasoning、function call 参数增量、不完整响应和完整 output 序列。
- 原生 Responses output 只对已知严格端点保存，并且只回放给产生它的同一规范化 origin；切换协议或服务商时使用可移植的 function call 历史。
- 适配层还包含 Kimi Chat reasoning 保留、DeepSeek 旧会话 reasoning 回退、GLM `tool_stream` 和 DashScope Qwen function output 配对规则。
- 如果模型只用普通文本声称要调用工具，却没有返回结构化 tool call，本轮会报错停止，避免把未执行操作当作已完成。

## 配置与持久化键

配置通过 `this.getSharedData` / `setSharedData` 存放在应用默认 SharedPreferences。Agent 层没有额外加密 API Key。

| 键 | 默认 | 当前用途 |
|----|------|----------|
| `ai_providers` | `""` | 供应商 JSON 列表。每项含 `id`、`name`、`url`、`key`。旧模型上的地址和 Key 会按二者相同合并迁移到这里 |
| `ai_models` | `""` | 模型 JSON 列表。每项含 `name`、`providerId`、`model`、`responses`、`contextLength`、`maxTokens`；为空时尝试迁移旧单模型配置 |
| `ai_model_index` | `"0"` | 当前模型索引；有模型时会归一化到有效的 1 起索引 |
| `ai_api_key` | `""` | 旧版单模型凭据迁移源；正常请求从当前模型所属供应商读取 Key |
| `ai_api_url` | `https://api.deepseek.com/v1` | 旧版单模型地址迁移源；正常请求从当前模型所属供应商读取地址 |
| `ai_model` | `deepseek-v4-flash` | 旧版单模型 ID 迁移源；正常请求直接读取当前 `ai_models` 项 |
| `ai_context_length` | `30000` | 旧配置迁移和缺省回退；当前值保存在模型对象中 |
| `ai_max_tokens` | `4096` | 旧配置迁移和缺省回退；当前值保存在模型对象中 |
| `ai_temperature` | `0.7` | 全局采样温度，限制为 0–2 |
| `ai_retry_count` | `2` | 自动重试次数，限制为 0–5 |
| `ai_system_prompt` | `""` | 追加到内置提示词后的用户附加指令，不会替换内置规则 |
| `ai_auto_approve` | `"0"` | 文件操作自动批准，默认关闭 |
| `ai_auto_run_sandbox` | `"1"` | 自动运行受限 Lua 沙盒，默认开启 |
| `ai_auto_approve_network` | `"1"` | 网络工具自动批准，默认开启 |
| `ai_allow_selfsigned` | `"0"` | 仅模型 API 流量允许自签名证书并关闭主机名校验 |
| `ai_mcp_servers` | 首次写入预设 | MCP 服务器 JSON；默认预设 `context7` 和 `deepwiki` |
| `ai_aux_provider_id` / `ai_aux_model_id` | `""` | 辅助模型（标题生成、上下文压缩、轻量子代理）按 provider + model 身份持久化；模型列表重排不影响指向，模型被删除时自动清除 |
| `ai_max_rounds` | `"0"` | 每回合工具轮数上限；`0` = 不限制（默认）。仅计数自动工具续环，用户发送新消息即重置；超出后回合结束并提示，子代理轮次同用此上限 |
| `ai_conversations` | SharedData 旧键（迁移源，迁移后清除） | 会话已按记录迁至 LuaKV 文件存储：`<agents 根>/kv/conversations/`，每会话一个记录文件（tmp+rename 原子写），`_index.json` 保存元数据索引（首页列表只读索引即可）。每条记录含 `usage`、`todos`、`seq`（稳定排序） |
| `ai_current_conv_by_project` | `{}` | 工程 → 会话 ID 映射；会话列表与恢复按工程读取 |
| `ai_current_conv_id` | `""` | 最近选择的会话 ID |
| `ai_current_conv` | `"0"` | 旧版会话索引导入源，读取时迁移 |
| `ai_changesets` | `""` | 旧版变更历史迁移源，迁移后清空 |

模型上下文窗口最小为 1000；最大输出限制为 256–32768，并且不超过上下文窗口减 500。

`ai_allow_selfsigned` 只影响模型 API 的 `AiHttpClient`。它不会放宽 `fetch_url`、沙盒 HTTPS 或 MCP 的校验。

## 内置工具

当前共有 20 个内置工具：

| 类别 | 工具 |
|------|------|
| 读取与发现 | `read_file`、`read_files`、`list_dir`、`search_in_files` |
| 文件变更 | `create_file`、`create_folder`、`delete_file`、`delete_folder`、`apply_patch`、`replace_in_file`、`append_file`、`rename_file` |
| 语法、执行与网络 | `check_lua_syntax`、`run_lua`、`fetch_url` |
| 工程与任务 | `run_project`、`build_project`、`run_subtask`、`update_todos` |
| 环境 | `get_env_info` |

`ToolExecutor.normalizeToolName()` 兼容 `read`、`mkdir`、`edit_file`、`run`、`fetch` 等常见别名，并可根据参数推断缺失的工具名。模型仍应使用 schema 中的规范名称。

主要限制：

- `read_file` 按行号返回，支持 `offset` / `max`；单文件超过 4 MiB 时拒绝完整读取。
- `read_files` 一次最多 20 个路径，默认每个文件最多 4000 字符，总返回约 60000 字符。
- `list_dir` 的递归实现限制深度和总条目，自动跳过 `.git`、`build`、`node_modules` 等目录。
- `search_in_files` 使用普通子串而非正则，并限制递归深度、扫描文件数和单文件大小。
- `apply_patch` 支持 SEARCH/REPLACE 块和 Unified Diff。SEARCH/REPLACE 依次尝试精确匹配、去首尾空行和忽略逐行空白差异的匹配。
- `create_file` 会覆盖已有文件；修改已有文件时系统提示词要求优先使用 `apply_patch`。
- `delete_file` / `delete_folder` 禁止删除当前工程根目录或其上级目录。

## 批准策略

`ChatUI` 先检查 `shouldAutoApprove()`，再检查 `requiresConfirmation()` 和破坏性工具分类。

| 操作 | 默认行为 |
|------|----------|
| 当前工程内的读取、列目录和搜索 | 自动批准 |
| 通过 `read_file` / `read_files` 读取内置 `res/doc` 文档 | 自动批准 |
| `get_env_info`、`check_lua_syntax` | 自动批准 |
| 工程外读取、列目录或搜索 | 请求确认 |
| 文件创建、修改、删除、移动 | 请求确认；开启 `ai_auto_approve` 后工程内变更可免确认，但**已存在目标的 `create_file`（覆盖写）仍要求确认** |
| 不带 `network_hosts` 的 `run_lua` | 由 `ai_auto_run_sandbox` 控制，且需已读过沙盒前置文档；默认自动运行 |
| 带有效 `network_hosts` 的 `run_lua` | 需同时开启 `ai_auto_run_sandbox` 和 `ai_auto_approve_network` 才自动运行 |
| `fetch_url` | 由 `ai_auto_approve_network` 控制；默认自动批准 |
| MCP 工具 | **一律自动执行，不经确认**（用户配置：不需要任何确认） |

开启 `ai_auto_approve` 后，执行器判定为当前工程内的文件变更可以免确认；`rename_file` 要求源路径和目标路径都通过工程检查。当前实现对不存在的相对目标无法通过 `getPathType` 判定，因此新建相对路径即使开启文件自动批准也可能继续显示确认框。

关闭 `ai_auto_run_sandbox` 后，所有 `run_lua` 调用都会逐次确认。关闭 `ai_auto_approve_network` 后，`fetch_url` 和带联网主机的沙盒代码都会逐次确认。MCP 调用不经确认直接执行（用户配置）。这些设置都不放宽沙盒自身的隔离和网络校验；网络设置也不影响模型 API 请求、用户主动连接测试或 MCP 工具列表刷新。

拒绝确认会生成普通 `tool` 结果并持久化，后续同批工具仍可继续执行。系统提示词禁止模型通过别名、拆分调用或重复请求绕过拒绝。

## 路径与项目隔离

- 相对路径以 `Bean.Path.this_dir` 为基准；绝对路径也被工具 schema 接受。
- 工具进入后台任务前会冻结已解析路径并记录当前工程 scope，避免执行期间相对路径随工程切换而漂移。
- scope 已变化时，尚未执行的文件工具会返回“项目已切换，文件操作未执行”。变更事务执行中发生工程切换时，`ChangeSet` 会尽量回滚。
- 工程边界使用规范化/Canonical path 比较，避免简单字符串前缀造成越界误判。
- 经用户确认的绝对路径操作并不统一限制在工程内；删除工程根目录或其上级目录是额外的强制保护。
- `PathManager.updateDir()` 会刷新 ChatUI、取消旧请求，并重新配置 AgentStorage、Skill 和 ChangeSet 的工程作用域。

## 文件变更与撤销

以下工具由 `ChangeSet` 跟踪：

```text
create_file, create_folder, delete_file, delete_folder,
apply_patch, replace_in_file, append_file, rename_file
```

- 工具执行前后保存文件或目录快照；单个事务最多约 1.5 MiB、2000 个文件。
- 当前工程的 undo 和 redo 各最多保留 10 个事务，持久化 JSON 上限为 4 MiB；超限时删除较早记录。
- 撤销或恢复前重新计算 fingerprint。文件被编辑器、用户或其他进程修改后会拒绝覆盖。
- 多路径恢复失败时会尝试回滚已恢复部分，避免留下半完成事务。
- 变更历史位于 `/sdcard/LuaJ/agents/projects/<24-hex-project-hash>/changesets.json`，使用锁、临时文件和备份文件提交。
- 旧数字工程哈希目录和 `ai_changesets` 会在读取时迁移。
- 聊天回合 undo/redo 与文件 undo/redo 相互独立。聊天 undo/redo 栈只存在于当前内存会话，但调整后的消息历史会持久化。

## Lua 沙盒

`check_lua_syntax` 和 `run_lua` 通过私有 `:lua_sandbox` 进程执行。超时或取消会终止远程沙盒任务，避免无限循环阻塞应用主进程。

沙盒提供基础 Lua、`coroutine`、`string`、`table`、`math`、`utf8`、`bit32`，以及：

```text
json, codec, hash.sha256, inspect, assert_equal, http.request
```

沙盒不提供 `io`、`os`、`package`、`debug`、`require`、`luajava`、`import`、`dofile`、`loadfile` 或 Android/工程文件访问。

主要限制：

- 源码最大 128 KiB，输出最大 64 KiB，错误文本最大 16 KiB。
- 执行超时限制为 1–8 秒。
- 联网前必须在 `run_lua.network_hosts` 中声明精确主机；最多 8 个主机、每次运行最多 4 个请求。
- 沙盒 HTTP 只允许公网 DNS 解析后的 HTTPS 443，禁止 IP 字面量、localhost、私网、代理、重定向和 URL 凭据。
- 支持 GET、HEAD、POST、PUT、PATCH、DELETE；请求体最大 256 KiB，响应体最大 512 KiB，单次 HTTP 超时 1–6 秒。
- `run_lua` 是否跳过确认由 `ai_auto_run_sandbox` 控制；带 `network_hosts` 时还必须开启 `ai_auto_approve_network`，但主机和请求校验始终执行。

完整 API 以 `res/doc/sandbox_zh.html` 和 `res/doc/sandbox_en.html` 为准。

## 公开网页读取

`fetch_url` 使用独立于 Lua 沙盒和模型 API 的 `AgentFetch`：

- 只支持 GET / HEAD 和公开 HTTPS 443。
- 不接受自定义请求头、Cookie、认证参数或请求体，不使用系统代理。
- 禁止 IP、localhost、私网和非公网 DNS 结果。
- 最多跟随 3 次重定向，每个目标都重新执行 URL 和 DNS 校验。
- 只返回 text、JSON、XML 和 JavaScript 类型正文。
- 总超时限制为 1–15 秒；正文限制为 256–50000 字符，默认 12000。
- URL 中已有的查询参数会原样发送。

## MCP

当前只集成 MCP tools，不集成 resources、prompts、roots、sampling，也不支持 stdio 或启动本地命令。

- 第一次没有配置时写入 `context7` 和 `deepwiki` 两个公开预设。
- 首选无状态 Streamable HTTP 协议 `2026-07-28`，先直接探测 `tools/list`。
- 旧服务器回退到 `initialize` + `notifications/initialized`，兼容 `2025-11-25`、`2025-06-18`、`2025-03-26` 和旧 HTTP+SSE。
- `tools/list` 最多读取 20 页，支持服务端 `ttlMs`；默认缓存 300 秒。
- 工具刷新是异步的；首次刷新完成前发出的模型请求可能暂时不包含 MCP 工具，后续请求会使用已发布的缓存。
- 模型可见工具名使用 `mcp__<namespace>__<tool>__<hash>`，内部 route map 再映射回服务器和原始工具名，避免名称冲突。
- 每个 MCP 工具沿用服务器提供的 `inputSchema`。现代协议可根据 schema 中合法的 `x-mcp-header` 注解，把静态标量参数镜像为 `Mcp-Param-*` 请求头。
- MCP 返回的 text 和 `structuredContent` 会传给模型；图片内容当前转换为 `[图片内容]` 占位文本。
- 会话过期、旧 SSE 断开或现代参数头不匹配时会刷新/重新初始化并重试一次。
- HTTPS 服务器不受 `fetch_url` 的公网 DNS 限制；明文 HTTP 只允许 localhost，URL 不允许内嵌用户名或密码。
- MCP 工具调用不经确认直接执行（用户配置：不需要任何确认）；工具发现刷新不受确认策略影响。

## 本地 Skill

Skill 只读取直接子目录中的 `SKILL.md`，不执行文件内容，也不自动下载远程 Skill。单文件超过 128 KiB 时忽略。

扫描顺序和同名覆盖优先级：

```text
/sdcard/LuaJ/agents/skills/<name>/SKILL.md       优先级 1
<project>/skills/<name>/SKILL.md                 优先级 2
<project>/.agents/skills/<name>/SKILL.md         优先级 3
```

frontmatter 支持 `name`、`description`、`triggers`、`keywords`。匹配使用不区分大小写的字面量计分：名称 +3、每个 trigger/keyword +2、description +1，同分时使用来源优先级。

每次发送用户消息都会重新选择 Skill；没有匹配时清除当前 Skill。会话中的 `skills` 字段只记录使用过的名称，当前实现不会根据该字段在重开会话后自动恢复 Skill 正文。

## 上下文管理

- 请求历史预算为 `max(2000, contextLength - maxTokens - 200)`。
- token 估算是启发式值，不是服务商 tokenizer 的精确结果。
- 自动压缩在原历史超过预算时触发，为摘要最多预留 1200 token；未携带新用户消息的发送会把压缩结果持久化回会话，避免后续每轮重复摘要（代价是更早的工具原文被摘要替换）；携带编辑器上下文的重发基于请求副本压缩，副本不落盘。
- 手动“压缩上下文”会把摘要和较新的消息写回当前会话。
- 摘要请求禁用工具，并把对话内容声明为待总结数据，防止旧消息中的指令被执行。
- 自动压缩失败、摘要为空或无法分离历史时，回退到按消息组保留最近内容。
- 压缩阈值目前只估算系统提示词和消息，不包含可能很大的 MCP/工具 schema；请求准备完成后的 UI 用量估算才会统计完整 body。

## 会话与生命周期

- 会话按记录存于 `<agents 根>/kv/conversations/`（LuaKV：每会话一个记录文件，tmp+rename 原子写，崩溃只影响正在写的那个会话），`_index.json` 保存元数据索引（首页跨工程列表只读索引，无需解析消息体），每条包含 `projectPath`；会话列表和当前选择按工程过滤。SharedData 旧 `ai_conversations` 键是迁移源，迁移成功后清除。
- 会话保存用户/assistant/tool 消息、结构化工具调用和结果、reasoning、Responses 原始 output/origin、continuation state 和请求错误。
- 新会话默认以首条用户消息去换行后的前 30 个字符命名；首轮问答完成后由辅助模型异步生成简短标题（不超过 16 字、与对话同语言）替换默认名，生成失败时保留默认名。
- 重开会话时按记录的 `skills` 名单恢复激活技能（`SkillManager.findByName` 重查正文；同名技能内容已变更则为新内容，找不到则不恢复）。后续发送仍按消息重新匹配。
- 关闭 BottomSheet 不取消任务。流式状态和工具链仍保存在当前 Activity/进程内存中；没有跨 Activity、跨进程或跨重启的持久化任务队列。
- 停止按钮会取消模型 HTTP、当前后台工具、MCP/网页/沙盒调用和待确认对话框。已完成工具结果保留，未完成的 Responses function call 会补入 `stopped` 工具结果以维持历史配对。
- 切换工程、切换/新建/清空会话会使旧 generation 失效并取消旧任务，过期回调不能修改新上下文。
- 被停止的部分文本、不完整输出和工具后空响应会标记 continuation state，UI 可继续请求。
- 请求错误记录在对应用户消息上。401/403 类错误提供打开设置，context/token 类错误提供压缩后重试，其他错误可直接重试或编辑原请求。

## 子代理与任务计划

### `run_subtask`

- 在隔离子代理上下文中执行委派任务：独立的系统提示词（基础提示词 + 子代理模式）、独立工具循环与上下文预算，不共享主会话消息历史。
- 子代理不提供委托类工具（不能再嵌套 `run_subtask`），避免递归失控。
- 执行期间以进度卡实时上报阶段（开始 / 轮次 / 工具 / 完成）；主会话的停止操作会传播取消子代理。
- 未指定模型时默认使用主模型；可在设置中指定辅助模型供轻量子代理使用。
- 工具历史使用可移植格式（不依赖 Responses 原生 output），结果有长度上限。

### `update_todos`

- 维护会话级任务计划：条目校验（content 必填、status 归一化为 pending/in_progress/completed）、最多 50 条、单条 content 按 UTF-8 安全截断。
- 计划持久化到当前会话记录；渲染为进度卡（已完成 n/m），并以紧凑清单注入系统提示词，驱动模型按计划推进。

## 重试与错误规则

- 默认自动重试 2 次，配置范围 0–5。
- HTTP 429、HTTP 5xx 和网络/流异常可重试；普通 HTTP 4xx 和用户取消不重试。
- 退避为 `min(1200, attempt * 300) ms`。
- 重试前清空已经流出的 UI 文本，避免失败响应片段重复拼接。
- 每次流式请求只允许一个终结回调。
- Responses 工具调用在参数完成前被截断、模型空响应、工具结果后空响应和未结构化工具意图都有独立处理路径。

## UI 与国际化

- 命令菜单支持手动压缩、聊天回合撤销/恢复、文件变更撤销/恢复、会话切换、Agent 帮助和设置。
- Markdown 气泡支持标题、强调、删除线、列表、任务列表、引用、链接、分隔线、行内代码与表格（表格经 `MarkdownTagHandler` 渲染）；代码块使用独立卡片，可复制或手动插入编辑器。
- “插入编辑器”不是模型工具，只是代码块卡片上的用户操作。
- AI 界面文案位于 `res/string/zh.lua` 和 `res/string/en.lua` 的 `ai_*` 键，修改用户可见文本时应同步双语。

## 已知实现边界

- 沙盒文档前置读取由系统提示词、`run_lua` 描述与执行器共同强制：进程内未通过 `read_file`/`read_files` 读过受信 `res/doc` 根下的 `sandbox_*.html` 前，`run_lua` 需要确认；该标记进程级共享，切换会话不重置。
- 文件自动批准对不存在的相对目标仍可能要求确认，因为当前工程内判定会检查目标类型。
- Skill 使用记录持久化在会话里；重开会话时按名单恢复激活技能（找不到同名技能则不恢复），后续发送仍按消息重新匹配。
- 工具 `xTask` 绑定当前 Activity 生命周期；模型流式状态也只保存在内存中，没有跨 Activity、跨进程或跨重启的任务恢复队列。
- 自动压缩决策不包含工具 schema token，大量 MCP schema 可能让实际请求比压缩阶段估算更大。
- MCP 目前只有工具能力，没有资源、提示词或 stdio 支持。

## 验证

相关单元测试：

- `app/src/test/java/com/androlua/AgentToolExecutorVerificationTest.kt`
- `app/src/test/java/com/androlua/LuaSandboxTest.kt`
- `app/src/test/java/com/nekolaska/ai/AgentFetchTest.kt`
- `app/src/test/java/com/nekolaska/ai/ResponsesStreamStateTest.kt`

修改 Agent 核心逻辑、Lua 资源或工具策略后至少运行：

```powershell
.\gradlew.bat :app:testDebugUnitTest :app:mergeDebugAssets --rerun-tasks
```

此外，纯 Lua 模块的行为测试在桌面 JVM 上运行（无需设备）：

```powershell
.\tests\run_tests.ps1
```

与 Agent 相关的套件：`TestParallel`（只读并行批与拦截规则）、`TestSubagent`（子代理执行/取消/模型路由）、`TestRegistry`（供应商与辅助模型注册表）、`TestStoreIndex`（会话存储与轻量索引）、`TestPatch`（补丁引擎）、`TestTodo`（任务计划）。方法论见 [tests/README.md](../tests/README.md)。

`AgentToolExecutorVerificationTest` 还会加载关键 Lua 文件、检查文档读取批准边界、网络自动批准策略、沙盒文档前置提示和内置文档目录完整性。
