# {{appNameText}}

空白页面 / Blank page · `{{packageNameText}}`

## 运行与打包 / Run & package
在 NeLuaJ+ 打开工程根目录，运行 `main.lua`；使用 IDE 的打包功能生成 APK 后安装。
Open the project root in NeLuaJ+, run `main.lua`, then use the IDE's APK packaging action to install a standalone app. Minimum Android version: 8.0 (API 26).

## 修改入口 / Customize
- `main.lua`: activity entry; explicit content/toolbar/title setup lives in the included `app/screen.lua`.
- `res/layout/main.lua`: scrollable page layout. Set `showToolbar = false` with a **NoActionBar** theme for a toolbar-free page. System ActionBar themes never add a second toolbar.
- `res/string/init.lua`: title and English defaults; `zh.lua`: Chinese translations; `en.lua`: English overrides.
- `init.lua`: package, version, permissions and `NeLuaJ_Theme` (current: `{{themeNameText}}`). For renamed app titles, update both `app_name` and `res/string/init.lua`'s `app_title`.
- Theme colors come from the Android theme. Material 3/dynamic, Material Components and Compat are supported; the Compat layout uses standard Android widgets without Material attributes.
- `app/screen.lua` reads the active Android theme's boolean attributes at runtime. Changes to `init.lua` through project settings take effect on the next launch; no regeneration or second evaluation of `init.lua` is needed.

默认无需权限，不保存数据。No permissions or persistent data are needed by this template. Optional modules, if selected, are copied into this project; its runtime never imports the IDE's internal helpers.

验收：分别运行有/无 ActionBar 主题，检查深浅色、大字体和横屏；打包后再独立启动。
Check light/dark mode, large text and landscape, then launch the installed APK independently.
