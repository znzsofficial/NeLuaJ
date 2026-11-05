# 独立项目模板与生成器

工程创建由 `mods/project/templates/Generator.lua` 编排。模板源码在
`app/src/main/assets/templates/`，不再以 `res.string.mcode` / `lcode` 保存。
`res.string` 只负责 IDE 的界面文案；生成工程自己的 `res/string` 仍是正常资源目录。

## 模块边界

- `Registry`：内置模板的稳定 ID、版本和声明清单。
- `Validator`：应用名、包名、主题与模板能力兼容性。
- `Renderer`：参数转义、文件选择和输出清单。
- `FileWriter`：文件系统边界与工程发布。
- `Generator`：预览和生成的公共入口，不持有页面 View。
- `CreateProject.show`：打开 `project_create` 路由，不跨 Activity 传递函数。
- 独立 `projectcreate/CreateProjectActivity`、`Controller`、`Layout`：六模板选择、配置、行内预览与异步生成。`Preview` 用原生 View 组成六种模板的小界面，不加载图片、不执行模板源码；预览不接受输入，点击由整个模板条目处理。
- 完整成功后以 `open_project` / `project_created` 和工程路径回传；首页与编辑器消费 result/pending 并按请求身份去重。编辑器打开前必须通过保存保护，不打开时仅刷新，不切换当前工程。

## 首批模板

- `blank`：最小工程，兼容 Material 3、Material Components 和 AppCompat 主题。
- `form`：输入、校验和结果反馈。
- `list`：本地清单，包含新增、完成、删除与持久化。
- `navigation`：主页面到详情页的参数传递及返回。
- `settings`：开关、单选偏好和重启恢复。
- `webview`：随工程附带的本地网页；默认不需要网络权限、不提供原生 JS 桥接。

进阶模板主推 Material 3/动态色；不支持的主题组合必须在生成前报告错误，不能
静默生成混用组件的工程。每个工程包含 README，说明入口、运行、打包与修改位置。

创建页将主题分成「配色与控件风格」和「标题栏方式」两个下拉选择，各自提供说明，
分别选择 Material 3/动态色/旧版风格，以及自定义 Toolbar/系统 ActionBar。
选择对应原有八种主题配置；更换模板不静默覆盖已选项，不兼容时保留选择并阻止生成。

## 调用约定

```lua
local Generator = require "mods.project.templates.Generator"
local options = {
  templateId = "blank",
  appName = "MyApp",
  packageName = "com.example.myapp",
  rootPath = "/sdcard/Projects",
  themeName = "Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay",
  useInternet = false,
  debugMode = true,
  modules = {},
}
local preview = Generator.preview(options)
-- 页面展示 preview.files / preview.permissions，再由用户执行创建。
local result = Generator.generate(options)
if not result.ok then
  print(result.message)
end
```

成功结果包含 `ok`、`templateId`、`version`、`projectPath`、`config`、`files`
与 `permissions`。失败结果包含 `phase`、`error`、`message`，必要时包含文件或
暂存目录信息。预览不写工程；生成重新校验当前目标状态，不把旧预览当成写入许可。

创建界面的默认名称查找、预览与生成都通过 `xTask` 的 IO 调度执行，后台任务只使用
已捕获的选项，不读取 View。进行中禁用重复提交并显示进度文字；页面已关闭或 Activity
销毁后丢弃旧回调，不再导航。文件写入不通过强制取消中断，让发布/清理流程自然完成；
关闭界面不意味着正在写入的工程一定不会生成。

写入先在独占暂存目录完成，再以独占创建目标目录的方式发布，避免 Android 上
`renameTo` 覆盖空目录。发布失败只回滚本次创建的路径。该流程不是多文件事务：
进程被终止时仍可能留下暂存目录或未完成的目标目录；它们不会被下一次创建静默覆盖。

## 新增模板

1. 在 templates 下创建独立目录，添加 `manifest.lua` 和 `files/`。
2. 清单声明 ID、版本、标题/说明资源键、支持主题族、默认值、权限与文件列表。
3. 在注册表中登记模板，并补齐中英文标题和说明。
4. 添加真正可运行的示例和 README；源码类绑定放模块顶部，运行时使用显式点语法方法调用。
5. 扩展生成产物测试，并在设备上运行和打包验证。

文件清单格式为 `{ source = "main.lua.tpl", path = "main.lua" }`，源路径默认相对
本模板的 files 目录。`sourceRoot = "shared"` 使用 shared/files；也支持显式的
`templates/shared/` 源路径。`when` 可按 `themeFamily` 和 `systemActionBar` 选择
变体。`raw = true` 表示原样复制。`init.lua` 由生成器统一生成，不在模板中重复输出。

占位符区分完整 Lua 字面量（如 `{{appNameLua}}`）和文档文本（如
`{{appNameText}}`）；Lua 字面量占位符外围不要再加引号。未知占位符、重复输出与
越出目标目录的路径必须拒绝。模板清单属于受信任的内置声明，不是用户插件执行入口。

公共文件与可选工具模块以独立资产复用。生成应用不得依赖 IDE 私有的
`mods.ui.Components` 或其他未复制的模块。已有工程不会因为模板更新而被重写。

选择可选模块时额外生成 `MODULES.md`，说明导入、索引、时间单位和迁移规则。
Array/Strings/TimeMeter/ObjectAnimator 使用显式返回的模块表，加载不改写全局标准库；
旧 Array/Strings 扩展须主动调用 installLegacy。Strings 默认按字面量分割并保留空字段，
Lua pattern 使用 splitPattern，区别于旧版混杂的语义。RxLua 沿用原实现。

## 验证边界

桌面测试应验证生成文件本身的 LuaJ++ 语法、文件清单、资源依赖、参数转义、
主题组合和写入失败恢复。IDE 的 Debug/Release 构建成功，不代表生成的应用已经
通过 Builder 打包与安装验证。

设备验收应对六种模板逐一创建、运行、修改、打包并安装，检查主题、字体缩放、
旋转、输入法、返回导航及持久化。没有设备时保留待验状态，不以宿主桩测试代替。

### 发布前操作清单

- 创建前：选不同模板，切换主题，确认不兼容组合有提示；手动修改包名后再改应用名，
  包名不能被自动覆盖；权限与可选模块应与预览清单一致。
- 创建中：选择全部模块，在较慢存储上检查响应；连点创建不能启动重复任务。
  离开创建界面或旋转后，旧任务不得把用户突然带入编辑器。
- 创建失败：验证目录只读、同名目录、写入空间不足，保留输入并提供可重试说明；
  检查失败残留，不得覆盖原有工程。进程中断后不承诺自动删除未完成目录。
- 应用行为：清单增删/完成与设置保存后重启；写入失败时不能显示已保存；
  详情返回、WebView 返回和页面销毁应各自正确处理。
- 独立运行：通过配套 Builder 导出并安装 APK，脱离 IDE 后再运行，而不是仅检查 IDE 内的执行结果。
