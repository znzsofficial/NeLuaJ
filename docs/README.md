# NeLuaJ+ 文档总索引

按读者与任务组织，不要求从头阅读。仓库维护文档以中文为主；应用内指南按下方目录提供中英文版本。

## 使用 IDE、编写 Lua 应用

- [首页与工程管理（中文）](../app/src/main/assets/res/doc/home_zh.html) / [Home and projects (English)](../app/src/main/assets/res/doc/home_en.html)：创建、打开、搜索、会话、保存失败和改名恢复。
- [应用内 API 文档完整目录](../app/src/main/assets/res/doc/agent_docs.md)：LuaJ++、Java 互操作、资源、布局、网络和组件。HTML 在应用帮助页或本地浏览器阅读，GitHub 可能仅显示源码。
- [LuaLayout AI 编写规范](../app/src/main/assets/res/doc/layout_ai.md)：单位、父容器、绑定表与布局检查的边界。
- 用户 Lua 工程的 APK 打包需要配套 Builder，不等同于构建 IDE 自身；见 [Builder 交接](./BuilderHandoff.md)。

## 构建、维护与验收

| 任务 | 入口 | 文档性质 |
|------|------|----------|
| 从源码构建 IDE、找 APK、维护版本号 | [BUILDING.md](./BUILDING.md) | 当前构建配方 |
| 修改前确认兼容性底线和验证范围 | [MAINTENANCE.md](./MAINTENANCE.md) | 维护约束 |
| 跑 Lua/JVM 测试、添加套件、查宿主桩限制 | [tests/README.md](../tests/README.md) | 测试说明与清单 |
| 验证首页、返回、主题重建、TalkBack 与分屏 | [HOME_VALIDATION.md](./HOME_VALIDATION.md) | 待执行的设备验收清单，不是通过记录 |
| 更新内置二进制、核对来源与接管过滤 | [app/libs/README.md](../app/libs/README.md) | JAR 清单、未知来源与更新步骤 |

## 当前实现

| 文档 | 内容 |
|------|------|
| [HOME.md](./HOME.md) | 首页、编辑器交接、列表加载、状态恢复、工程改名与数据安全边界 |
| [AIAgent.md](./AIAgent.md) | Agent 模块、工具注册与批准策略、协议、上下文、会话存储 |
| [LuaLayout.md](./LuaLayout.md) | 布局表加载、属性解析、AI 静态工具与布局助手复用 |
| [LuaActivity.md](./LuaActivity.md) | 脚本宿主、独立 Globals、生命周期、平台 helper |
| [LuaJRuntime.md](./LuaJRuntime.md) | Java/Kotlin 桥接、动态加载、UTF-8、IO 与 runtime ABI 约束 |
| [BuilderHandoff.md](./BuilderHandoff.md) | IDE 与独立 Builder 的跨应用协议 |
| [AGENT_REFACTORING_MASTER.md](./AGENT_REFACTORING_MASTER.md) | Agent 重构范围、已实现机制及尚未验收部分 |

实现说明中的“后续方案”只表示候选工作，不因写在文档里就成为已交付能力。源码和针对当前版本的测试是核实依据；测试成功也不替代真机验收。

## 历史设计与记录

以下文件保留原路径供旧链接和讨论引用，不作为当前实现规范，不按其中示例恢复已移除架构：

- [AGENT_REFACTORING_PLAN.md](./AGENT_REFACTORING_PLAN.md)：原始 Agent 重构目标。
- [AGENT_REFACTORING_RECORD.md](./AGENT_REFACTORING_RECORD.md)：阶段记录；其中早期“100%”等结论已由文件顶部警告限定。
- [PHASE_1_REFACTORING_SPEC.md](./PHASE_1_REFACTORING_SPEC.md)：第一阶段草案，部分示例并未落地。
- [PHASE_2_REFACTORING_SPEC.md](./PHASE_2_REFACTORING_SPEC.md)：已替代的混合容器方案，不能据此恢复旧消息容器。

## 文档维护规则

- README 负责项目介绍和导航；本文负责总索引；构建命令以 BUILDING 为主，兼容与验收约束以 MAINTENANCE 为主。
- 用户 API/操作说明放应用内帮助；模块内部设计放本目录；历史目标不能覆盖当前行为。
- 修改工具、套件、模块或文档文件时，同步相关索引并运行 `tests/check_documentation_inventory.ps1`；不要在介绍中手写易过期的测试/工具总数。
- 不删除其他人的未提交内容，不为整理文档批量改代码或移动运行时资源。项目设计背景 [PRODUCT.md](../PRODUCT.md) 不是 API 或兼容性契约。
