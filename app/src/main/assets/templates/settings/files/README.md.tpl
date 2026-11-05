# {{appNameText}}

偏好设置 / Preferences · `{{packageNameText}}`

在 NeLuaJ+ 打开工程根目录并运行 `main.lua`；通过打包功能生成 APK 后安装。最低 API 26；Material 3/动态色（`{{themeNameText}}`）。
Run the root `main.lua`, then package/install an APK to verify standalone behavior.

## 文件 / Files
- `main.lua`: reads saved values before attaching listeners, updates the live greeting preview, and saves only when **Save preferences** is pressed. Failed saves keep the chosen values for retry.
- `app/preferences.lua`: private SharedPreferences named with package plus `.settings`; stores two booleans, never executes saved text.
- `res/layout/main.lua`: grouped switch and mutually exclusive radio buttons, live preview and save feedback. All content scrolls for keyboard/large-font/small-window use.
- `app/screen.lua`: included shell; no duplicate Toolbar when the theme supplies an ActionBar.
- `res/string/{init,zh,en}.lua`: English/Chinese messages and title. App name/package/version/permissions/theme live in `init.lua`. Update both `app_name` and `app_title` when renaming; theme attributes control colors.

无需任何权限。设置保存在本机，重启读取；未按保存的预览不会持久化。清除数据或卸载会重置。IDE Run 与安装版使用不同沙箱，包名相同的 IDE 工程共享示例偏好。

No permissions are required. Installed-app preferences are private to the installed app. IDE Run uses a package-namespaced store in the IDE sandbox, not the installed app's store. Clearing data/uninstalling resets preferences.

Small synchronous `commit()` calls let this example display disk-write failures. For more data move storage off the UI thread. A failed commit can still alter the in-memory preferences cache; do not treat its failure as durable success. Corrupt preference types disable saving instead of overwriting existing data.

验收：开关、单选、预览→保存→退出重启，以及未保存退出、失败反馈、大字体、深浅色。
Verify saved and unsaved changes across restart, error feedback and standalone APK operation.
