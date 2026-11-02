# 维护与验证入口

本页是维护者入口；[实现文档索引](./README.md) 说明模块设计，[测试说明](../tests/README.md) 说明桌面测试机制。历史计划及其警告保留原样；“后续方案”不是现有功能清单。重构完成须核对真实调用链、测试结果及设备验收，不能仅凭新文件存在宣称交付。

## 兼容性底线

- 用户打包的 APK 会继承宿主 Java/Kotlin 与 manifest 层：只做 additive 兼容改动，不删除、重命名或收窄现有公开 API，不随意移除组件、权限或改变已有语义。兼容迁移必须另行确认，编译通过不是兼容性证明。
- 当前 `app/build.gradle.kts` 的 `minSdk = 26`。Java 17 编译工具链不等于设备拥有新 JDK/Android API；新增平台调用必须核对最低版本、守卫或兼容实现。运行时桥接/动态加载另见 [LuaJRuntime.md](./LuaJRuntime.md)。
- Lua 使用仓库 LuaJ++ 方言与编译器，不能用系统标准 Lua/luac 的成功或失败代替门禁。桌面行为测试使用完整 JSE jar；nocglib 回退仅适合语法检查。JAR 定位规则见测试说明。
- 修改 LuaLayout/预览/Agent 工具时，保留布局加载的容错、引用顺序和已有绑定语义；静态分析不执行布局代码，也不能宣称完成视觉验证。
- 不撤销其他人的未提交改动；共享 checkout 的 Gradle 命令串行运行。下列命令是维护配方，不代表已在本次变更中全部运行。

## 从项目根目录验证

只改文档、文件名、套件或工具清单时先运行（无需 JDK/设备）：

```powershell
.\tests\check_documentation_inventory.ps1
```

Lua 改动使用相关套件；提交前运行当前 runner 自动发现的全部套件，不手写套件或断言总数：

```powershell
.\tests\run_tests.ps1 -Check app/src/main/assets/mods/agent/AgentChat.lua
.\tests\run_tests.ps1 TestLayoutTools
.\tests\run_tests.ps1
```

需要 JDK（当前构建工具链为 17）；Android 构建还需项目配置要求的 SDK 与依赖。Kotlin/Java/manifest/资源或跨层集成改动，由持有构建目录的维护者串行执行：

```powershell
.\gradlew.bat :app:compileDebugKotlin :app:testDebugUnitTest :app:mergeDebugAssets
```

布局静态分析可先定向运行已有单测：

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests "com.androlua.layout.LayoutToolsTest"
```

选择测试时看测试源码而非名称；相关套件不覆盖的路径必须补测。文档清单脚本独立于 Lua runner，当前 Android CI 显式运行它、runner 失败传播回归、全部 Lua 套件、JVM 单测及 Debug/Release 构建；工作流定义不等于远端 CI 已通过。

构建不再自动改写版本号。需要递增时单独运行 `:app:bumpVersionCode`，然后在新一次 Gradle 调用中构建。`:app:verifyRuntimeTakeover` 检查源码接管名单与实际过滤后的 JAR；它不证明 ABI 兼容。二进制来源、校验值及更新步骤见 [app/libs/README.md](../app/libs/README.md)。

## 各层证明什么

| 验证 | 能证明 | 不能证明 |
|------|--------|----------|
| 文档清单检查 | 选定文档路径存在；工具/套件静态清单一致 | 行为、权限、描述全文准确、历史计划已实现 |
| LuaC 语法门禁 | 指定源码可由 LuaJ++ 编译 | 模块执行成功、动态导入与 Android API 可用 |
| 桌面 Lua / Kotlin 单测 | 测试断言覆盖的逻辑和宿主替身调用 | Android 渲染、ART/dex、真实网络和生命周期 |
| Kotlin 编译 / assets 合并 | 编译与资源装配成功 | ABI/manifest 兼容、工具确认边界或 UI 正确 |
| 真机回归 | 实际设备上执行过的场景 | 未执行设备版本和场景的完整正确性 |

涉及平台改动至少按改动面检查：最低支持 API 的启动与项目运行、布局预览和主加载器一致性、主题/图片/错误提示、AI 确认/取消/切换工程或会话、打包 APK 的继承行为。记录设备/API、执行命令、结果和未覆盖范围，不把静态分析的 unknown 当成有效布局，也不把宿主替身当成真机。

首页、会话列表、工程管理与编辑器返回交接的设备验收步骤见 [HOME_VALIDATION.md](./HOME_VALIDATION.md)。

## 防漂移约定

- 工程上下文已由 `mods/project/ProjectContext.lua` 提供延迟 Bean 快照，`PathManager` 和 `Workspace` 使用它；工程根、浏览目录、当前文件与代际归属分别表达。Agent 当前仍保留原有路径/存储作用域规则，尚未整体迁移；词法规范化不替代安全边界的 canonical/symlink 检查。
- 首页壳的稳定页面标识、窗口宽度策略与可重建页面宿主位于 `app/src/main/java/com/nekolaska/home/HomePages.kt`、`app/src/main/java/com/nekolaska/home/HomePageFragment.kt`、`app/src/main/java/com/nekolaska/home/HomeShellView.kt`；Lua 页面通过命名宿主和 `pageContentReady` 接线。保存失败离开保护位于 `mods/editor/LeaveGuard.lua`；待办跳转须成功确认后消费，不能把 `peekPending` 当作消费。
- 文档中的 `mods/`、`res/` 路径相对 `app/src/main/assets/`；`com/` 相对 `app/src/main/java/`。新增明确文件引用应使用完整模块路径，不省略同表中的目录。
- 工具名以 `app/src/main/assets/mods/agent/ToolRegistry.lua` 的 schema 声明为准，`ToolSchemas.lua` 保持兼容导出，维护 [AIAgent.md](./AIAgent.md) 的标记表；套件以磁盘及 runner 自动发现为准，维护测试说明的标记表。数量只在运行时报告。
- `tests/check_documentation_inventory.ps1` 静态核对文档/工具/套件/模块目录、本地链接和 SDK 构建说明，不加载应用模块、不解析业务行为、不执行工程文件。声明格式变化时更新提取器并重新验证，不能静默跳过空清单。HTML 文档中的 Lua 示例值不当作实际页面资源链接。
- 新的上下文装配、工具注册表或统一预览实现交付后，还要人工核对 AIAgent 请求流程、模块职责与 LuaLayout 后续方案；在调用链和测试未核对前不把协作中的工作写成已完成。
