# 从源码构建与验证

本页针对 **NeLuaJ+ IDE 自身**。在手机中把用户 Lua 工程打成 APK，需独立的 [NeLuaJ-Builder](https://github.com/znzsofficial/NeLuaJ-Builder)，交接协议见 [BuilderHandoff.md](./BuilderHandoff.md)。

## 环境与配置来源

- 使用 **JDK 17**。仓库通过 Gradle wrapper 固定 Gradle，不要求另装全局 Gradle。
- 使用 Android Studio 时，选择兼容仓库锁定 AGP/Kotlin 版本的 IDE；不要沿用旧 README 的 Ladybug 最低版本承诺。插件版本在 `gradle/libs.versions.toml`，wrapper 在 `gradle/wrapper/gradle-wrapper.properties`。
- 当前 `app/build.gradle.kts`：`compileSdk = 37`、`targetSdk = 33`、`minSdk = 26`。构建机需要对应编译 SDK；最低设备 API 不代表只安装该版本 SDK 就能编译。
- 使用 SDK Manager 安装项目要求的平台/工具；SDK 位置通过本机 Android 环境配置或 `local.properties` 的 `sdk.dir` 提供。不要提交本机 SDK 路径或凭据。
- 桌面 Lua 测试另需 **PowerShell 7 (`pwsh`)** 和 PATH 上可用的 `java` / `javac`。相关 JAR 随仓库提供，来源边界见 [二进制清单](../app/libs/README.md)。

首次 Gradle 构建通常需要获取依赖。`--offline` 仅适用于 SDK 与所需依赖已缓存的环境，不能作为新环境默认命令。

## 最小构建

从仓库根目录执行：

```sh
git clone https://github.com/znzsofficial/NeLuaJ.git
cd NeLuaJ
```

Windows PowerShell：

```powershell
.\gradlew.bat :app:assembleDebug
```

Linux/macOS：

```sh
chmod +x gradlew
./gradlew :app:assembleDebug
```

输出在 `app/build/outputs/apk/debug/`。APK 名称带版本与构建时间，不要在安装脚本中写死某个时间戳。

## 提交前的验证

下面 PowerShell 命令在 Windows / Linux / macOS 的 PowerShell 7 中运行：

```powershell
pwsh -File tests/check_documentation_inventory.ps1
pwsh -File tests/check_build_maintenance.ps1
pwsh -File tests/run_tests.ps1
```

运行平台层单测和 Debug 构建：

```powershell
.\gradlew.bat :app:verifyRuntimeTakeover :app:testDebugUnitTest :app:assembleDebug
```

Linux/macOS 使用同样任务名，将 `.\gradlew.bat` 换为 `./gradlew`。

`verifyRuntimeTakeover` 核对源码接管名单和过滤后 JAR 内容，已接入正常构建；不证明 ABI 或行为完全兼容。Lua/JVM 单测和构建通过，不证明真实设备上的布局、权限、网络、ART/dex 或生命周期正确。详细机制见 [测试说明](../tests/README.md)，首页设备场景见 [HOME_VALIDATION.md](./HOME_VALIDATION.md)。

## Release、签名与版本号

```powershell
.\gradlew.bat :app:assembleRelease
```

输出在 `app/build/outputs/apk/release/`。当前 Release 沿用 **debug 签名配置**，不是生产发布签名方案；不要把 CI 的 release 文件等同于已完成正式签名与设备验收的发行版本。时间戳版本名也不构成可复现构建保证。

正常配置、测试、Debug/Release 构建不改写 `app/version.properties`。需要增加版本号时单独执行：

```powershell
.\gradlew.bat :app:bumpVersionCode
```

检查版本文件变更后，在**新一次 Gradle 调用**中构建。不与 assemble 等任务放在同一命令；Android 在配置阶段读取版本号。

## CI 与常见误区

[Android CI](../.github/workflows/android.yml) 在 main 的 push / pull request 上运行文档清单、runner 失败传播回归、全部发现的 Lua 套件、JAR 接管检查、JVM 单测及 Debug/Release 构建，并保存测试报告与 Release APK。工作流定义不代表某次远端运行已通过；状态以 Actions 结果为准，分支保护需在仓库设置中另行配置。

- 依赖或 SDK 缺失时，不要用关闭测试/校验的方式“修复”构建。
- 遗留 LuaJ++ 字节码的本地 JVM 测试使用 `-noverify`；这是已知兼容措施，不是线上安全保证。
- 当前工具链有废弃选项警告，不在业务修复或文档整理时顺手升级 AGP/Kotlin；迁移单独评估。
- 使用单套共享构建目录时串行运行 Gradle，避免多代理互相覆盖中间产物。
