# NeLuaJ+ 对外 MCP 服务

本文描述外部助手访问手机工程的本地服务。内置助手连接外部 MCP 的客户端能力见
[AIAgent.md](./AIAgent.md#mcp-客户端内置助手调用外部工具)；聊天任务状态与诊断见 [TOOL_TASKS.md](./TOOL_TASKS.md)。

## 快速开始

1. 打开 **首页 → 设置 → MCP 连接**。
2. 选择允许 AI 助手访问的工程。
3. 选择权限：**只读**允许查看文件；**读写**还允许修改、删除文件和撤销操作，执行时不会逐次询问。
4. 选择是否使用令牌验证，然后点击 **开启 MCP 服务**。

「服务已开启」表示助手现在可以连接，不表示已有助手连上。查看「最近 5 次工具操作」可确认是否收到调用。手机切换工程不会改变已经授权的工程；更换工程或权限、切换令牌验证，需先停止服务。

### 手机上的 AI 助手

在支持 MCP 的助手中添加服务器，类型选择 **Streamable HTTP**，地址填写 `http://127.0.0.1:8765/mcp`。不需要 USB 或 ADB。这里的 `127.0.0.1` 指这台手机，不能直接用于其他手机或局域网连接，也不是用浏览器打开的网页。只支持 stdio 或旧版 HTTP+SSE 的客户端不能直接连接。

### 令牌怎么填

令牌相当于这个连接的密码，默认需要验证。

- **开启验证**：点击「复制令牌」。在助手的请求头设置中，名称填 `Authorization`，值填 `Bearer `（末尾有一个空格）再粘贴令牌。如果助手有专门的 Bearer token 输入框，只粘贴令牌即可。
- **关闭验证**：不填令牌，不添加 `Authorization` 请求头。复制的 OpenCode 配置也会省略这一项。

关闭验证后，手机其他应用也能按所选权限访问这个工程。服务仍只监听本机地址，并限制工程范围。免令牌时，「复制令牌」和「更换令牌」按钮不可用。

### 电脑上的 AI 助手

用 USB 连接手机，在手机上开启 USB 调试并允许这台电脑。只有一台设备时，在电脑运行：

```sh
adb forward tcp:8765 tcp:8765
```

多台设备时，先用 `adb devices` 查看设备编号，将下方 `SERIAL` 替换为目标手机的编号：

```sh
adb -s SERIAL forward tcp:8765 tcp:8765
```

使用同号端口：服务校验 Host，转发成其他电脑端口会被拒绝。配置连接后可通过 `adb -s SERIAL forward --remove tcp:8765` 取消转发。使用 Android SDK 的新版 platform-tools，避免 PATH 中旧 adb 反复重启服务。

转发完成后，电脑上的助手也使用 `http://127.0.0.1:8765/mcp`。令牌填写方式与手机相同。

### OpenCode V2 配置

点击「复制 OpenCode V2 配置」，将内容合并到 `opencode.json`，保留原有设置。开启验证时，在运行 OpenCode 的环境中将 `NELUAJ_MCP_TOKEN` 设为复制的令牌；配置文件中的 `{env:NELUAJ_MCP_TOKEN}` 是环境变量引用，不是令牌本身。开启验证的配置如下：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "neluaj": {
        "type": "remote",
        "url": "http://127.0.0.1:8765/mcp",
        "protocol": "legacy",
        "oauth": false,
        "headers": {
          "Authorization": "Bearer {env:NELUAJ_MCP_TOKEN}"
        }
      }
    }
  }
}
```

关闭验证时，删去示例中的整个 `headers` 字段即可，无需设置环境变量。应用会按当前验证模式生成正确配置。

### 断开与重新连接

- 关闭设置窗口不会停止服务；点击「停止 MCP 服务」才会关闭监听。
- 停止后重新开启、更新或重启应用后，令牌会重新生成。开启验证时需重新复制令牌并更新助手设置。
- 「更换令牌」会立即使旧令牌失效并断开现有连接。
- 系统在后台关闭 NeLuaJ+ 后，需要重新打开应用并开启服务；目前不保证长期后台在线。
- 连接失败时先确认服务已开启、地址及端口正确、客户端支持 Streamable HTTP；提示 401 时检查令牌。电脑连接还需确认 USB 调试授权和端口转发。

### 协议兼容性

这是本机配对服务，不是 OAuth 服务。使用 `2025-11-25` 的 initialize 握手和 JSON 响应；不支持 2026-07-28、stdio 或旧版 HTTP+SSE。GET/SSE 返回 405。浏览器 Origin 默认全部拒绝，原生客户端无 Origin 可以连接。

## 工具

先调用 `project_info` 取得不透明 `projectHandle`，其余工程操作必须携带它。路径为工程内相对路径；禁止绝对路径、父级穿越和符号链接。停止或轮换令牌使旧 handle 失效。

- 只读：`server_info`、`project_info`、`list_files`、`read_file`、`search_files`、`get_transaction`、`get_history`。
- 读写授权另提供：`create_file`、`append_file`、`replace_in_file`、`apply_patch`、`create_directory`、`rename_path`、`delete_path`、`undo_file_change`、`redo_file_change`。
- 文档资源：`neluaj://docs/agent` 和 `neluaj://docs/layout`。

`read_file` 返回文本或 base64、kind 和 SHA-256 version。缺失路径也有 version，用于条件创建。目录读取只返回 kind/version；版本观察沿用原生快照预算。列表分页最多 200 项；单目录最多 2000 项。搜索为字面量匹配，最多扫描 2000 项/4 MiB 内容，返回 truncated。

写入必须传 `requestId` 和读取时的 `expectedVersion`；rename 另传 `expectedTargetVersion`；undo/redo 使用 `get_history` 的 `expectedHead`。创建不覆盖。Lua 内容做编译语法检查。

同一 requestId 只能重试相同内容：native 在发布前持久 reservation 和规范请求摘要。已完成调用返回原事务结果；不同内容拒绝。未发布 reservation 被中断时返回明确 INTERRUPTED，不自动重做。journal/tombstone 为提交事实，补写结果不能覆盖它。断线不等于未写入，重连后查询事务或以相同 requestId/参数重试。

取消 notification 仅阻止发布前执行；进入发布后完成事务与条件补偿，并同步编辑器。连接超时不直接中断发布线程。工具错误使用 `isError` 和 `structuredContent`，partial 不是成功。

编辑器回调每次最多等待 5 秒：尚未执行的回调在超时/取消后不会再执行；已经开始的保存继续持有令牌引用直到退出，避免另一笔写入与它并发。准备阶段超时会拒绝本次修改；提交后的同步超时会保留提交结果并报告待重试的同步警告。并发修改占用同一个 Lua 执行器时立即返回 busy 错误，不排队耗尽 HTTP 工作线程。这里的时限限制编辑器等待，不强行中断已经开始的磁盘提交。

同步失败后丢弃可能已被消费的编辑器快照；通知重播或相同 requestId/参数重试时重新捕获恢复状态，只重试同步、不重复修改文件。

## 实现与生命周期

- `com/nekolaska/mcp/server/McpServerHost.kt`：NanoHTTPD 2.3.1，loopback、Bearer/Host/Origin 校验、1 MiB 请求体、4 并发连接、30 秒连接 deadline，不使用上传临时文件。
- `McpProtocolAdapter.kt`：JSON-RPC 方法、版本及取消适配。
- `McpRuntime.kt`：进程内用户启动会话、凭据与授权，关闭界面不会停止监听；无常驻前台服务，系统回收进程后需要重新开启。
- `McpProjectRegistry.kt` / `McpProjectBackend.kt`：固定授权、相对路径、读取预算、显式工具白名单。
- `McpMutationHost.kt`：独立 Lua Globals、实际 AgentStorage alias 解析、主线程桥接。
- `mods/files/ExternalFileFacade.lua`：复用 FileMutationService/PatchEngine/FileMutationEngine；无聊天 Activity、Bean 或 xTask 依赖。
- `mods/mcp/EditorBridge.lua`：UI 局部快照、弱 Activity 注册、resume 重播。编辑器准备复用 native token；UI 等待不持 native monitor。

工程 scope 保留原词法路径（如 `/sdcard`），真实路径仅用于边界校验，以免切断原工程历史。MCP 与内置 Agent、编辑器保存共享原生协调器和撤销历史。当前文档成功写入后强刷，新输入先存恢复草稿；无编辑器时不提前 ack，下一次 resume 对账。

外部编辑器、任意 Lua 和其他未接入协调器的文件管理操作仍是外部写入者；Java 文件系统 API 不提供对非协作写者的原子 compare-and-rename。详见 [FILE_MUTATIONS.md](./FILE_MUTATIONS.md)。

SDK 选型：官方 Kotlin SDK 的 Ktor JVM 示例没有 Android server 兼容承诺，首版采用单个 NanoHTTPD 依赖与独立 adapter。当前 minSdk 26/targetSdk 33；API 26 仍待设备验证，不因 DEX 合并成功宣称所有设备通过。

构建依赖：`settings.gradle.kts` 将 `org.nanohttpd` 及其 `org.sonatype.oss:oss-parent` 父 POM 定向到阿里云 Central 镜像，避免 Maven Central 返回 403。其他依赖继续使用原有仓库配置；正常打包无需额外 `-I` 临时脚本。

## 验证记录与剩余边界

### 本轮桌面回归（2026-11-10）

编辑器等待超时、排队回调失效、运行中 token pin 延迟释放、同步快照重新捕获，以及连续等待超时后 HTTP 容量可用的回归通过。
本轮 Lua 全套、全部 JVM 单元测试与 Debug 构建通过，未重新进行设备验收。

### 首版设备记录（2026-11-06）

2026-11-06：桌面 JVM、Lua facade 和 Android Debug 构建通过；PJZ110/API 36 上真实 HTTP instrumentation 已验证初始化、工具目录、读取、创建、追加、重复请求不重复追加、版本冲突、删除撤销和历史 head。测试使用应用私有独立目录，没有修改用户工程。

OpenCode V2.2.5 经同号 ADB 转发的实际验收已确认 `connected`，资源目录发现两项内置文档；使用临时 location 的 runtime API 注册并在验收后移除，没有修改用户全局配置。外部窗口的 instrumentation 最终报告 Process crashed，故该记录只证明实际握手和资源发现，不证明长连接或结束生命周期。正常短程 HTTP 事务 instrumentation 单独通过。

首版 47 套 Lua 行为测试、JVM 测试、Debug/Release 和测试 APK 构建通过。之后新增免令牌模式，真实 loopback HTTP 的 JVM 测试确认无需 Authorization 即可连接，并仍拒绝非法 Host/Origin；相关 UI 测试及 Debug 构建通过。Inspector、编辑器可见强刷/草稿、Activity 重建、USB 拔插、真实进程死亡和 API 26 兼容性仍需分别验收。

随后用户从设置页开启读写授权，在实际 `demo1` 工程上完成 USB HTTP 验收：初始化、列目录、临时文件创建/读取、追加与重复 requestId 去重、过期版本拒绝、条件撤销及删除全部通过。临时文件已删除；操作保留在正常事务历史中。该记录补齐实际工程读写，不代替可见编辑器强刷/草稿验收。

设备测试入口为 `com.nekolaska.mcp.server.McpDeviceTest`。默认不保留监听；显式 instrumentation 参数 `externalClient=true` 提供 120 秒外部客户端窗口，令牌只暂存在应用私有 cache 的 `mcp-device-token`，finally 删除。该入口仅在测试 APK 中，生产配置不创建令牌文件。

## 参考

- https://opencode.ai/v2/docs/mcp-servers
- https://modelcontextprotocol.io/specification/2025-11-25
- https://github.com/NanoHttpd/nanohttpd
