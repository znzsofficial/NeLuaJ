# {{appNameText}}

本地清单 / Local checklist · `{{packageNameText}}`

在 NeLuaJ+ 打开根目录运行 `main.lua`，通过 IDE 打包并安装 APK。最低 Android 8.0/API 26；Material 3/动态色主题（`{{themeNameText}}`）。
Open the project root, run `main.lua`, then package/install an APK to verify standalone operation.

## 结构 / Structure
- `main.lua`: add, complete and delete handlers; empty state; storage failure messages. UI updates only after a successful save; failed adds keep the typed text.
- `app/tasks.lua`: JSON array in private Android SharedPreferences, named with this project's package plus `.checklist`. JSON is parsed as data, never executed as Lua.
- `res/layout/main.lua`: scrollable input and task list. This teaching example is limited to 100 tasks of 120 Unicode characters each; move to RecyclerView/database for a larger list.
- `app/screen.lua`: included theme-aware page shell, no IDE modules required.
- `res/string/{init,zh,en}.lua`: title and localized messages. `init.lua` holds the package, permissions, app name and theme; update both app name and string title when renaming. Change layout colors with theme attributes.

## 数据 / Data
无需网络、文件访问或通知权限。重启后恢复清单；卸载/清除应用数据会删除清单。IDE Run 的存储属于宿主沙箱，按工程包名区分；安装 APK 后属于应用自己的沙箱，二者不互相迁移。包名相同的 IDE 工程会共享该示例数据。

No permissions are needed. Installed-app data lives in that app's private sandbox. IDE Run data is package-namespaced inside the IDE's sandbox and is not copied into the APK. Clearing app data or uninstalling removes the checklist.

The example uses synchronous `commit()` on a small bounded dataset to report persistence failures. For production-scale data, use background I/O and explicit loading states. A failed commit may already change SharedPreferences' in-memory cache; the page reports failure rather than promising disk persistence. Corrupt saved JSON disables editing and leaves the original value intact: inspect/back up the preferences before deliberately clearing app data.

验收：新增→完成→删除→重启恢复；空列表、超长输入、达到上限、存储失败与深浅色/大字体。
Verify add/complete/delete/restart, empty state, limits, storage failure and the installed APK.
