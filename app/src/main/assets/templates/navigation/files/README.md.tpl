# {{appNameText}}

多页面导航 / Two-page navigation · `{{packageNameText}}`

在 NeLuaJ+ 根目录运行 `main.lua`，使用打包功能生成并安装 APK。最低 API 26；Material 3/动态色主题（`{{themeNameText}}`）。
Run `main.lua` from the project root in NeLuaJ+, then package/install the APK.

## 路由 / Routing
- `main.lua` collects an optional message (up to 500 characters).
- `app/routes.lua` calls the existing `activity.newActivity(absolutePath, { message })` API.
- `detail.lua` receives `local message = ...` and closes with `activity.finish()`. Android Back also returns to the original page; it does not create a second home page.
- Both entry files are at project root so resource and `require` lookup have the same base. If moving pages into subdirectories, explicitly revisit those bases rather than importing an IDE route helper.
- `res/layout/{main,detail}.lua` define the two scrollable layouts. `app/screen.lua` is shipped with this application and handles Toolbar/system ActionBar composition.

标题和文案在 `res/string/{init,zh,en}.lua`；主题、包名和版本在 `init.lua`。改应用名时同步 `app_name` 与 `app_title`。在布局中使用主题属性修改颜色，在 `main.lua`/`detail.lua` 修改事件。
Change text in string resources, colors via theme/layout attributes, and events in the two entry files.

默认无权限、不保存消息。No permissions or persistent storage are needed; parameters are passed locally between activities. Check empty/default and long Unicode messages, system Back, explicit Back, rotation, and standalone APK navigation.
