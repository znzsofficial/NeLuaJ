# NeLuaJ+ 第一阶段架构重构工程方案：Kotlin 下沉与调度状态机加固

> **历史设计草案。** 下文 `SubagentCoordinator` 等示例并非现有实现。
> 当前直接使用 CountDownLatch，注册表以锁分离取消批次，不能仅凭
> ConcurrentHashMap 或一次编译成功宣称取消原子性和死锁已全面消除。
> 当前源码状态与测试边界见 `AGENT_REFACTORING_MASTER.md`。

> 文档版本：1.1 (工程落地版)  
> 目标：将多线程并发控制、线程挂起唤醒、并发任务追踪及高频排版算法下沉至 Kotlin 原生层，消除 LuaJ++ 环境下的线程死锁、CPU 忙等、跨会话时空错乱与 O(N^2) 渲染卡顿。

---

## 一、 为什么将部分逻辑下沉至 Kotlin？

在 NeLuaJ+（LuaJ 虚拟机架构）中，Lua 层的核心局限：
1. **Lua 虚拟机的线程不安全**：`LuaTable` 和 `Globals` 均无并发锁保护，跨线程读写极易导致数据损坏；
2. **缺乏原生线程同步原语**：Lua 原生没有 `CountDownLatch` / `Condition` / `Lock`，导致原实现被迫使用 `while not done do Thread.sleep(200)` 进行高功耗的忙等轮询；
3. **多任务取消追踪脆弱**：在 Lua 侧用单个全局变量 `local activeJob` 记录后台任务，遇到并发工具批次派发时被反复覆盖，导致脱缰后台任务无法被全部取消；
4. **JNI 反射穿透开销**：在 Lua 侧循环遍历多字节字符串并逐个调用 `setSpan`，带来巨额反射开销与 GC 负担。

**工程边界划分原则**：
- **Kotlin 负责**：线程安全、并发同步原语、原子取消注册表、以及栈优化的排版算法；
- **Lua 负责**：会话流程编排、Prompt 组装、声明式 UI 模板渲染与用户交互响应。

---

## 二、 第一阶段落地实施清单（P0）

### 模块 1：子代理同步等待与唤醒协调器（Kotlin 下沉）

- **新增类**：`app/src/main/java/com/nekolaska/agent/SubagentCoordinator.kt`
- **设计细节**：
  ```kotlin
  package com.nekolaska.agent

  import java.util.concurrent.ConcurrentHashMap
  import java.util.concurrent.CountDownLatch
  import java.util.concurrent.TimeUnit
  import java.util.concurrent.atomic.AtomicBoolean

  class SubagentSession(val taskId: String) {
      private val latch = CountDownLatch(1)
      private val cancelled = AtomicBoolean(false)
      @Volatile var result: String = ""
      @Volatile var success: Boolean = false

      fun await(timeoutSeconds: Long = 180): Boolean {
          return latch.await(timeoutSeconds, TimeUnit.SECONDS)
      }

      fun complete(resultText: String, ok: Boolean) {
          this.result = resultText
          this.success = ok
          latch.countDown()
      }

      fun cancel() {
          cancelled.set(true)
          latch.countDown()
      }

      fun isCancelled(): Boolean = cancelled.get()
  }

  object SubagentCoordinator {
      private val activeSessions = ConcurrentHashMap<String, SubagentSession>()

      @JvmStatic
      fun createSession(taskId: String): SubagentSession {
          val session = SubagentSession(taskId)
          activeSessions[taskId] = session
          return session
      }

      @JvmStatic
      fun cancelAll() {
          activeSessions.values.forEach { it.cancel() }
          activeSessions.clear()
      }

      @JvmStatic
      fun removeSession(taskId: String) {
          activeSessions.remove(taskId)
      }
  }
  ```
- **Lua 改造（`SubagentRunner.lua`）**：
  - 移除 `while not state.done do sleepMs(200)` 忙等轮询；
  - 创建 `session = SubagentCoordinator.createSession(taskId)`；
  - 后台 Worker 线程调用 `session.await(180)`（出让 CPU，操作系统级等待）；
  - 主线程完成或取消时调用 `session.complete(result, ok)`，精准唤醒 Worker 线程；
  - **单测挂架兼容**：在 PC 纯 Java 单测环境中，若 `postToMain` 为同步执行，执行完毕后 `session.await(0)` 立即返回，100% 兼容现有 14 个用例。

---

### 模块 2：并发任务追踪与全量原子取消注册表（Kotlin 下沉）

- **新增类**：`app/src/main/java/com/nekolaska/agent/AgentJobRegistry.kt`
- **设计细节**：
  ```kotlin
  package com.nekolaska.agent

  import java.util.concurrent.ConcurrentHashMap

  object AgentJobRegistry {
      // 记录正在执行的异步任务及其分类名称（如 fetch_url, run_lua, mcp 等）
      private val activeJobs = ConcurrentHashMap<Any, String>()

      @JvmStatic
      fun register(job: Any, toolName: String) {
          activeJobs[job] = toolName
      }

      @JvmStatic
      fun unregister(job: Any) {
          activeJobs.remove(job)
      }

      @JvmStatic
      fun cancelAll(cancelCallback: (String) -> Unit): Int {
          val count = activeJobs.size
          activeJobs.forEach { (job, toolName) ->
              try {
                  // 支持 LuaJobWrapper 或标准 Coroutine Job
                  val cancelMethod = job.javaClass.getMethod("cancel")
                  cancelMethod.invoke(job)
              } catch (_: Exception) {}
              cancelCallback(toolName)
          }
          activeJobs.clear()
          return count
      }
  }
  ```
- **Lua 改造（`ToolExecutor.lua`）**：
  - 废弃单例 `local activeJob`；
  - 启动异步任务时调用 `AgentJobRegistry.register(job, name)`；
  - 回调触发时调用 `AgentJobRegistry.unregister(job)`；
  - `cancelPending()` 调用 `AgentJobRegistry.cancelAll(...)`，批量取消所有并发任务并执行清理。

---

### 模块 3：`AgentTurn.lua` 时空错乱彻底防御（Generation & Session 守卫）

- **代码改造（纯 Lua 状态机加固）**：
  - 每次启动新回合时，闭包捕获启动时刻的会话 ID 与世代编号：
    ```lua
    local turnSessionId = Session.id()
    local turnGeneration = state.generation
    ```
  - 定义统一的存活与归属检查：
    ```lua
    local function isTurnActive()
      return Session.id() == turnSessionId and isCurrent(turnGeneration)
    end
    ```
  - 在所有下游回调入口（流式 chunk、异步工具完成、`finishStopped`）：
    ```lua
    if not isTurnActive() then
      return -- 丢弃过期或跨会话的回调，严禁向当前活跃会话插入脏数据
    end
    ```

---

### 模块 4：`MarkdownTagHandler.kt` 闭合标签 O(1) 栈优化与边界防护

- **Kotlin 改造（`MarkdownTagHandler.kt`）**：
  - 为 `<m-code>`, `<m-h1>`, `<m-h2>`, `<m-h3>`, `<m-quote>`, `<table>` 建立独立的 `ArrayDeque<Int>` 开闭位置栈；
  - 移除对整个文档的 `output.getSpans(0, output.length, ...).lastOrNull()` 线性遍历；
  - 标签开启时压入 `output.length`；
  - 标签闭合时使用 `stack.removeLastOrNull()` 安全出栈；
  - 出栈后校验 `0 <= start && start <= output.length`，合法区间直接绑定 Span；
  - 时间复杂度从 $O(N^2)$ 降低至 **$O(1)$**。

---

## 三、 验证基线与质量门禁

1. **测试套件 100% 通过**：
   - 执行指令：`pwsh -ExecutionPolicy Bypass -File ./tests/run_tests.ps1`
   - 必须保持 13 个独立测试套件全绿，零回归错误。
2. **Kotlin 原生编译通过**：
   - 执行指令：`./gradlew :app:compileDebugKotlin --rerun-tasks`
   - 编译退出码 0，无任何类型错误与警告。
3. **消除的崩溃与死锁风险**：
   - 彻底解除多任务并发派发时的后台脱缰任务；
   - 彻底消除 Subagent 线程池饥饿死锁；
   - 杜绝跨会话工具结果串写导致的 API 400 报错。
