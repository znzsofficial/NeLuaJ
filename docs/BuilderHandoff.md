# NeLuaJ+ 到 Builder 的打开协议

IDE 不会自己打包 APK。项目菜单的“构建”会把当前工程交给 [NeLuaJ-Builder](https://github.com/znzsofficial/NeLuaJ-Builder)。修改 action、extra、package 或 Activity 名称时，必须同步两端和两边的 manifest。

## 稳定契约

| 项目 | 值 |
|---|---|
| Builder package | `com.nekolaska.Builder` |
| Builder Activity | `com.nekolaska.MainActivity` |
| Intent action | `com.nekolaska.Builder.action.OPEN_PROJECT` |
| Project path extra | `com.nekolaska.Builder.extra.PROJECT_PATH` |

调用端：

- `app/src/main/assets/activities/main/Actions.lua` 的 `Actions.openBuild()`
- `app/src/main/AndroidManifest.xml` 通过 `<queries>` 声明 Builder 包可见性

Builder 接收端：

- Builder `AndroidManifest.xml` 声明公开的 `OPEN_PROJECT` intent-filter，并使用 `singleTop`
- Builder 只进入对应工程详情页，不会自动开始构建

## IDE 发送前的检查

1. 当前工程名非空，目录存在。
2. 工程根目录有常规文件 `init.lua`。
3. 若当前有打开文件，先保存；保存失败则中止。
4. extra 发送 canonical path；canonical 失败时回退到拼接路径。
5. Intent 使用显式 `ComponentName`，并带 `FLAG_ACTIVITY_CLEAR_TOP | FLAG_ACTIVITY_SINGLE_TOP`。
6. 启动失败时提示未安装 Builder。

Builder 只接受 canonical `LuaJ/Projects` 下含 `init.lua` 的工程。完整 Builder 侧约定见 Builder 仓库的 `docs/BuilderMaintenance.md`。
