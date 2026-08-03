# 内置 AI 助手（mods/agent）

NeLuaJ+ 内置的 AI 编码助手，走 OpenAI 兼容 `/chat/completions` 流式接口，支持工具调用与 MCP 扩展。

## 功能入口

- 编辑器内通过「AI 助手」功能项打开：`app/src/main/assets/activities/main/Actions.lua` → `ChatUI.show()`。
- 主界面底部弹出一个全屏 BottomSheet（`res/layout/ai_chat_panel.lua`），内置消息列表与输入区。

## 模块文件

| 文件 | 职责 |
|------|------|
| `mods/agent/AgentChat.lua` | 配置读写、消息上下文构建、工具定义与执行、`sendStream`（含自动重试） |
| `mods/agent/ChatUI.lua` | 全部界面：聊天、设置、模型管理、会话管理、MCP 管理、确认对话框 |
| `mods/agent/MCPClient.lua` | MCP 服务器管理（发现工具、调用工具、默认预设） |
| `mods/agent/ChangeSet.lua` | AI 文件变更快照、fingerprint 冲突检测和文件撤销/恢复 |
| `mods/agent/SkillManager.lua` | 本地 `SKILL.md` 扫描、匹配和提示词注入 |
| `res/layout/ai_chat_panel.lua` | 主聊天面板布局 |
| `res/string/zh.lua` / `en.lua` | 全部文案（`ai_*` 键） |

## 配置项（SharedData）

| 键 | 默认 | 说明 |
|----|------|------|
| `ai_api_key` | `""` | OpenAI 兼容 API Key |
| `ai_api_url` | `https://api.deepseek.com/v1` | API 端点（自动补全 `/chat/completions`） |
| `ai_model` | `deepseek-v4-flash` | 当前模型名 |
| `ai_models` / `ai_model_index` | — | 多模型列表（JSON）与当前索引 |
| `ai_temperature` | `0.7` | 采样温度（0–2） |
| `ai_max_tokens` | `4096` | 单次最大输出（不超过上下文窗口 - 500） |
| `ai_context_length` | `30000` | 模型上下文窗口，用于历史截断预算 |
| `ai_retry_count` | `2` | **失败自动重试次数**（0 = 不重试） |
| `ai_system_prompt` | `""` | 自定义系统提示词，留空用内置默认 |
| `ai_auto_approve` | `"0"` | `"1"` 时项目目录内文件操作免确认 |
| `ai_allow_selfsigned` | `"0"` | `"1"` 时允许自签名 HTTPS 证书（用 `okHttp.unsafe`） |
| `ai_mcp_servers` | — | MCP 服务器列表（JSON） |
| `ai_changesets` | — | 旧版 AI 文件变更历史迁移源；正常运行时使用外部 `changesets.json` |

Agent 运行时数据存放在 `PathBean.agent_root_dir/projects/<project-hash>/`，通常对应 `/sdcard/LuaJ/agents/projects/<project-hash>/`。当前 `ChangeSet` 使用 `changesets.json`；旧的 `ai_changesets` 会在首次读取时自动迁移。

## 本地 Skill

- 全局 Skill 放在 `PathBean.agent_root_dir/skills/<name>/SKILL.md`。
- 项目 Skill 放在 `<project>/.agents/skills/<name>/SKILL.md` 或 `<project>/skills/<name>/SKILL.md`。
- 只读取 Markdown，不执行 Skill 文件中的代码，也不支持远程下载。
- 可选 frontmatter：`name`、`description`、`triggers` 或 `keywords`。
- 每次发送消息时按名称、描述和关键词选择得分最高的 Skill，并将正文注入当前请求；使用过的 Skill 名称记录在会话的 `skills` 字段。

## 自动重试

`AgentChat.sendStream` 在请求层重试，**到达设置次数或不可重试错误时才把错误抛给 UI**（UI 仍有「重试」按钮兜底）。

- **会重试**：网络异常（`Stream` / `ERROR:` / `java.*`）、HTTP 5xx、HTTP 429（限流）。
- **不重试**：HTTP 4xx（参数/鉴权错误）、用户点击「停止」（`cancelAll` 触发的取消错误）。
- 重试前会通过 `onRetry` 回调清空 UI 已流出的文本（避免失败段落重复拼接），并按 `min(1200, attempt*300)ms` 递增退避。

## MCP 扩展

- 工具通过 `mcp::<服务器>::<工具>` 命名空间注入给助手。
- 设置弹窗可添加自定义服务器（名称 / URL / Headers），也可一键添加 `context7`、`deepwiki` 预设。
- 每台服务器支持单独「测试」连接。

## 工具调用与确认

内置工具：`create_file`、`create_folder`、`delete_file`、`delete_folder`、`apply_patch`、`replace_in_file`、`append_file`、`rename_file`、`read_file`、`read_files`（批量读多个文件，最多 20 个）、`list_dir`（支持 `recursive`/`pattern`）、`search_in_files`（支持 `ignore_case`）、`get_env_info`、`run_lua` 等。

- 破坏性操作（创建/删除/改文件）默认弹出确认对话框展示路径与内容预览；`ai_auto_approve = "1"` 时项目目录内免确认（`rename_file` 要求源与目标都必须在项目目录内才自动批准）。
- **删除保护**：`delete_file` / `delete_folder` 拒绝删除项目根目录或其上级目录；路径会先做 `..`/`.` 规范化再校验，防越界。
- `apply_patch` / `replace_in_file` 匹配顺序：精确字面量 → 去首尾空行 → 忽略每行缩进/空白差异的宽松行匹配（行尾统一为 `\n`）。
- `read_files` 结果在界面上只显示文件数摘要，完整内容只发送给模型，避免 UI 卡顿。
- `MAX_TOOL_ROUNDS = 30`，超过停止并提示，防止无限循环。
- 会话历史与工具调用记录会持久化到 `ai_conversations` / `ai_conv_index`（全量保存，发送时才按 token 预算裁剪）。默认会话名为空，首次用户消息后自动取前 30 字符命名。

## 国际化

所有界面文案已抽到 `res/string/{zh,en}.lua` 的 `ai_*` 键，新增文案请保持双语同步。`ChatUI.lua` 内通过 `local S = res.string` 引用；面板布局用 `res.string.*`。

## 后续路线（待办）

以下功能按投入产出比排序，未实现项以 `[ ]` 标记：

### 上下文用量显示（已实现）

`AgentChat.estimateContextUsage(history)` 复用 `buildApiMessages` + `estimateTokens` 计算 `{ used, budget }`，`sendToApi` 发送时在 `loadingBar` 右侧 `ctxUsage` 标签显示 `used / budget tok`；占用率 ≥80% 变橙、≥95% 变红。

### 上下文压缩（总结式，已实现）

- 预算未超限时直接发送原历史；超预算时保留较新的约 55% 历史，把较早消息交由模型总结成摘要，再替换原文参与本次请求。
- 摘要请求禁用工具调用，且不写入持久化会话；会话仍保存完整原始消息，后续请求可重复压缩。
- 摘要为空、请求失败或无法安全分割工具调用链时，自动回退到 `buildApiMessages` 的成对裁剪策略。
- 历史裁剪按普通消息或 `assistant.tool_calls + tool` 结果组进行，不再逐条截断工具链；请求用量直接统计最终发送的 API 消息。

### 请求生命周期与取消（已实现）

- 每次发送拥有递增的 generation；切换/新建/清空会话、关闭面板或点击停止时立即使旧请求失效。
- 压缩、流式响应、工具执行、重试和错误回调都会检查 generation，过期回调不会修改当前会话或 UI。
- 流式请求保证只触发一次终结回调，避免空 `tool_calls` 与普通文本同时返回时重复添加消息。

### 命令菜单（已实现）

- 输入框左侧新增命令按钮，菜单提供主动压缩上下文、撤销上一轮对话、恢复上一轮对话、切换会话和模型设置。
- 撤销/恢复以完整用户回合为单位，不拆开 assistant tool calls 和 tool 结果；恢复只恢复历史和 UI，不重新执行工具。
- 主动压缩会把压缩后的请求历史保存回当前会话；文件变更通过 `ChangeSet` 单独记录和恢复。

### MCP 生命周期（已实现）

- `initialize` 成功后发送 `notifications/initialized`，再进行工具发现或调用。
- MCP 工具刷新期间到达的多个回调会排队，刷新完成后统一返回，避免调用方静默丢失结果。

### 模块拆分（进行中）

- `ContextManager.lua` 已独立负责 token 估算、上下文预算、工具调用链成组裁剪和摘要压缩。
- `AgentChat.lua` 通过兼容入口转发上下文 API，现有 UI 调用无需感知内部拆分。
- `OpenAIClient.lua` 已独立负责 OpenAI 兼容 API 的请求构建、流式响应、重试和 tool call 解析。
- `AgentChat.lua` 通过兼容入口转发 `sendStream` / `testConnection`，现有 UI 调用无需感知客户端拆分。
- `ToolExecutor.lua` 已接管工具名规范化、执行调度、破坏性操作分类、项目目录判断、自动批准策略和 MCP 同步/异步分发，并提供唯一工具执行入口。
- Android 文件读写、补丁和 Lua 沙盒属于平台适配层，通过 `platformExecute` 注入，不再参与工具路由；AgentChat 只提供运行时依赖和平台能力。

### [x] 对话 redo/undo（聊天历史）

- 对话区已按完整用户回合撤销和恢复，不拆开 assistant tool calls 与 tool 结果；恢复不会重新执行工具。
- 文件变更通过下方的 `ChangeSet` 菜单项单独撤销/恢复；聊天 undo 不会改变文件。

### [x] 文件变更 ChangeSet

- 文件创建、删除、修改、追加、重命名和文件夹操作会记录前后快照。
- 撤销/恢复前校验当前 fingerprint；文件被外部修改时拒绝覆盖并提示冲突。
- 命令菜单提供最近一次文件变更的撤销和恢复；恢复不会重新调用 AI 工具。
- 文件快照持久化到外部 `changesets.json`，应用重启后仍可恢复当前项目最近 10 条变更；不同项目的变更历史不会互相恢复，超过 4 MB 的历史会自动丢弃较早记录。

### [x] Markdown 富文本渲染（轻量方案，不引入 Markwon）

- 已支持 `#`~`###` 标题、粗体、斜体、无序/有序列表、引用、`[text](url)` 链接、分隔线和行内代码。
- 代码块维持现有独立卡片逻辑，支持复制和插入；文本段使用 `HtmlCompat` 转为安全的 `Spanned`。
- 理由：Markwon 渲染树与现有 Lua 气泡/代码卡片体系冲突，引入成本高且样式不可控，故不采用。

### 已清理的遗留

- `open_file` 工具已移除（无对应实现），创建文件后不再弹无意义的气泡提示。
- "插入代码到编辑器"（`insertCode`）仅保留为代码块卡片的**手动**按钮，系统提示词不引导模型主动触发；编辑器上下文（`buildContext`：当前文件/选中代码/编译错误/项目文件列表）仍会注入给模型。
