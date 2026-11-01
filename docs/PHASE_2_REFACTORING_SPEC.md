# 阶段二实施细节方案：RecyclerView 渐进式集成与混合容器架构 (P1)

> 目标：在 `ChatUI.lua` 中接入基于 `AgentChatAdapter` 的 `RecyclerView` 虚拟化容器，淘汰暴力 `removeAllViews()` 刷新。
> **核心原则**：保持现有 `BubbleRenderer` 的复合卡片渲染能力 100% 不退化，同时保证 PC 端自动化单测套件 100% 持续通过。

---

## 一、 数据集模型与适配器架构：复合卡片展平适配

通过深入审查 `ChatUI.lua:1020-1085` 的现有渲染流，发现历史消息中实际呈现给用户的“卡片流”包括：
1. **用户提问卡片**：`msg.role == "user"`（若有 `request_error` 附带错误重试卡片）；
2. **AI 助手复合卡片**：`msg.role == "assistant"`（内含 Thinking 折叠区 + Markdown/代码块 + 操作行）；
3. **工具调用/回执卡片**：由 `assistant.tool_calls` 配合后续 `tool` 结果展开出的卡片；
4. **子代理实时进度卡片**：`SubagentRunner` 运行时的浮动卡片；
5. **流式动态吐字卡片**：`streamView`。

### 1.1 适配器数据源展平器（`MessageItemFlattener.lua`）
为了让 `AgentChatAdapter`（基于 Android `ListAdapter`）能够高效复用 ViewHolder，在数据输入端将 `Session.messages()` 转换为视觉卡片流（Visual Cards）：
```lua
-- visualItem:
-- { type = "user", message = msg, isLastUser = bool }
-- { type = "assistant", message = msg, isLastAssistant = bool }
-- { type = "tool", toolName = name, args = args, result = result }
-- { type = "streaming", text = text }
-- { type = "subtask", info = info }
```

### 1.2 `AgentChatAdapter` 的多类型映射与绑定
- **ViewType 划分**：
  - `TYPE_USER = 0`：用户气泡
  - `TYPE_ASSISTANT = 1`：AI 复合消息
  - `TYPE_TOOL = 2`：工具调用与结果
  - `TYPE_STREAMING = 3`：流式打字中
  - `TYPE_SUBTASK = 4`：子代理实时卡片
- **ViewHolder 创生与绑定**：
  - `onCreateViewHolder`：针对 `viewType` 调用现存的模板 `loadlayout` 生成根视图与 `rowViews` 表，存入 `holder.setViews(rowViews)`；
  - `onBindViewHolder`：直接复用 `BubbleRenderer` 中的纯数据绑定逻辑，将文本、按钮状态、折叠标记绑定到 ViewHolder 的视图中。

---

## 二、 渐进式双模容器设计（彻底免疫单测 ClassNotFound 风险）

由于 PC 单测环境（`Run.java`）中没有真正的 Android RecyclerView 与类加载环境，采用**渐进式双模架构**：

```
                    ChatUI 渲染调度器
                           │
             ┌─────────────┴─────────────┐
             ▼                           ▼
    [真机 Android 环境]           [PC 纯 JVM 单测环境]
   • views.msgRecycler 存在       • views.msgRecycler 为桩
   • 加载 AgentChatAdapter       • 回退到 views.msgContainer
   • 享受 60FPS 虚拟化与内存恒定  • 13 个单测套件 100% 绿色通行
```

### 实施细节：
在 `ChatUI.lua` 中：
```lua
local function refreshMessageList()
  if not isPanelVisible() then return end
  if chatAdapter and views.msgRecycler then
    -- 真机虚拟化高效刷新
    local cards = flattenVisualCards(Session.messages())
    chatAdapter.submitMessages(cards)
  elseif views.msgContainer then
    -- 单元测试与兼容性回退
    views.msgContainer.removeAllViews()
    loadHistoryLegacy()
  end
end
```

---

## 三、 流式打字（Streaming Token）无损局部刷新

1. **避免覆盖数据**：流式打字期间完全不修改 `Session.messages()`，只更新 `cards` 中的最后一个 `TYPE_STREAMING` 卡片；
2. **局部刷新 Payload**：
   调用 `chatAdapter.notifyItemChanged(streamIndex, AgentChatAdapter.PAYLOAD_STREAMING_TEXT)`；
3. **`onBindViewHolderWithPayload`**：
   当检测到 `PAYLOAD_STREAMING_TEXT` 时，只更新 `holder.getViews().aiStreamText.setText(streamText)`，外框零重绘，零闪烁。
