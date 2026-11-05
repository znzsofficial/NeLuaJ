# {{appNameText}}

表单交互 / Validated form · `{{packageNameText}}`

在 NeLuaJ+ 打开根目录运行 `main.lua`，通过 IDE 打包 APK 后安装。Android 8.0/API 26 起；支持 Material 3 与动态色主题。
Open the root in NeLuaJ+, run `main.lua`, then package and install the APK. Current theme: `{{themeNameText}}`.

## 文件与修改 / Files & customization
- `main.lua`: trims the input, validates 1–40 Unicode characters, displays a greeting and registers clear/submit listeners.
- `res/layout/main.lua`: Material text field, primary action, themed clear icon button and live result. The icon button uses `materialIconButtonStyle`; keep its theme-managed background and tint. Its accessible label and tooltip describe the action.
- `app/screen.lua`: included page shell; sets content before Toolbar, only adds a Toolbar for NoActionBar themes and checks the ActionBar before setting its title.
- `res/string/init.lua`, `zh.lua`, `en.lua`: title and English/Chinese messages. Change colors through the theme in `init.lua`, layout `?attr/...` values, or your own project resources.
- `init.lua`: app name/package/version/theme and explicit permission list. Update `app_name` and `app_title` together when renaming.

不保存或发送名字，默认无权限。The name remains in the current page only; no storage or network permission is required. All helper source ships in the project.

测试空白名字、中文名字、超过 40 字符、清空按钮、键盘打开时的滚动、大字体和深浅色；再独立运行 APK。
Try empty/long input, Unicode names, clearing, keyboard scrolling and large text. Test the packaged app as well as IDE Run.
