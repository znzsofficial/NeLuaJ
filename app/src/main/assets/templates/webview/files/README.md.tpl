# {{appNameText}}

离线网页 / Offline WebView · `{{packageNameText}}`

在 NeLuaJ+ 根目录运行 `main.lua`；用打包功能生成 APK 并安装。最低 API 26；Material 3/动态色原生界面（`{{themeNameText}}`）。
Run `main.lua` in NeLuaJ+, then package/install the APK including the `web/` directory.

## 文件 / Files
- `main.lua`: reads bundled HTML/CSS/JS with Lua, replaces the local stylesheet/script tags with inline content, then uses `loadDataWithBaseURL`. JavaScript runs only inside WebView; there is **no `addJavascriptInterface` native bridge**. If you rename the two files, update the replacement patterns too.
- `web/index.html`: page structure and content (English teaching sample); `web/style.css`: light/dark colors and responsive layout; `web/app.js`: bounded counter and reset. You can also serve `web/` with a local development server to preview it in a desktop browser.
- `res/layout/main.lua`: native status text and WebView. `app/screen.lua` is the included page shell. Native title/status translations are in `res/string/{init,zh,en}.lua`; localize the HTML copy directly.
- `init.lua`: name, package, version, theme and permissions. Rename both `app_name` and `app_title` for a consistent label. Native colors follow the theme; web colors are CSS tokens and follow system light/dark preference, not Android dynamic accent colors.

## 权限与数据 / Permissions & data
默认无权限，禁止网络加载、WebView 文件/content 访问与跨文件源访问；Lua 只读取项目自带的三个文件。DOM storage 关闭。计数只保存在网页内存，重新加载归零。点击页内链接后，系统返回先走网页历史，历史为空时结束 Activity。

No permissions are required. Network loads, WebView file/content access and cross-file origin access are disabled. DOM storage is off; the count is memory-only. Android Back navigates WebView history before leaving. WebView is detached and destroyed with its activity.

## 扩展为在线页面 / Explicit online extension
1. Add `"INTERNET"` to `init.lua`'s `user_permission`, then rebuild the APK. A permission change requires packaging; IDE Run does not prove APK permissions.
2. Replace the local loader with `web.loadUrl("https://your-owned-host.example/")` and change `setBlockNetworkLoads(true)` to `false`.
3. Add a WebViewClient that allows only your expected HTTPS hosts and deliberately handles external navigation. Keep file/content access disabled and do not add a native bridge for untrusted pages. Review the page's CSP for the resources it actually needs.

验收：断网运行、加一/重置、页内链接/系统返回、字体放大、深浅色、独立 APK；确认无需宿主文件。
Verify offline launch, increment/reset, history/Back, large fonts, both color modes and independent APK launch.
