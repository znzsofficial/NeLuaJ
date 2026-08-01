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

### [ ] 上下文压缩（总结式）

- 现状：预算超限时 `buildApiMessages` 只做"丢最旧消息"的硬裁剪，会丢失早期信息。
- 方案：超预算时把最旧的一批消息交由模型总结成一段摘要，作为 `system`/`user` 前缀哨兵消息替换原文；总结本身走 `sendStream`，失败回退到现有丢消息策略。需新增开关与文案。

### [ ] 对话 redo/undo

- 编辑区：复用编辑器自带 undo 栈，AI 改文件后不清除。
- 对话区：messages 为 append-only，"撤销上一条"＝确认后删除末条并重绘；"重做"用 deleted 缓冲恢复。

### [ ] Markdown 富文本渲染（轻量方案，不引入 Markwon）

- 现状：`splitCodeBlocks` 只切 ```代码块```（独立卡片 + 复制/插入），行内 Markdown 不渲染。
- 方案：自写 `SpannableStringBuilder` 渲染器，纯 Android API 零依赖——`#`~`###` 标题、`**粗体**`/`*斜体*`、`` `行内代码` ``、`-` 列表、`>` 引用、`[text](url)`（`URLSpan`）、`---` 分隔线。代码块维持现有卡片逻辑，与文本段混合排版。
- 理由：Markwon 渲染树与现有 Lua 气泡/代码卡片体系冲突，引入成本高且样式不可控，故不采用。

### 已清理的遗留

- `open_file` 工具已移除（无对应实现），创建文件后不再弹无意义的气泡提示。
- "插入代码到编辑器"（`insertCode`）仅保留为代码块卡片的**手动**按钮，系统提示词不引导模型主动触发；编辑器上下文（`buildContext`：当前文件/选中代码/编译错误/项目文件列表）仍会注入给模型。
