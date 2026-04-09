# 迁移指南

本文档帮助你将旧版 NeLuaJ+ 项目迁移到最新版本。新版本引入了 **Material 3 Expressive** 设计规范。

---

## 1. 状态栏适配

### 推荐写法

新版本推荐使用以下模式设置状态栏，确保深色/浅色模式正确切换：

```lua
import "android.view.View"
import "android.view.WindowManager"

local ColorUtil = this.themeUtil

local window = activity.getWindow()
    .setNavigationBarColor(0)
    .setStatusBarColor(ColorUtil.getColorBackground())
    .addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
    .clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
if this.isNightMode() then
    window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_VISIBLE)
else
    window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR)
end
```

> **提示**：使用 ActionBar 主题（`Theme_NeLuaJ_Material3`）时，ActionBar 会自动处理状态栏颜色。使用 NoActionBar 主题时需要手动设置。

---

## 2. 主题迁移

### 推荐主题

| 主题 | 说明 |
|------|------|
| `Theme_NeLuaJ_Material3` | 带 ActionBar，适合简单页面 |
| `Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay` | 无 ActionBar，适合自定义 Toolbar 的页面 |

### 主题设置方式

**方式一（推荐）**：在 `init.lua` 中配置，Activity 自动应用：

```lua
-- init.lua
NeLuaJ_Theme = "Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay"
```

**方式二**：在 `main.lua` 中手动设置（必须在 `setContentView` 之前）：

```lua
activity.setTheme(R.style.Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay)
```

> 如果 `init.lua` 已设置 `NeLuaJ_Theme`，则无需在 `main.lua` 中重复调用。

### 动态颜色

推荐在 `onCreate` 中调用 `activity.dynamicColor()` 启用 Material You 动态取色：

```lua
activity.dynamicColor()
```

---

## 3. 布局组件迁移

### 推荐使用 Material 3 组件

| 旧组件 | 新组件 | 说明 |
|--------|--------|------|
| `TextView` | `MaterialTextView` | 支持 MD3 文字样式 |
| `Button` | `MaterialButton` | 自动应用 MD3 按钮样式 |
| `EditText` | `TextInputEditText` + `TextInputLayout` | MD3 输入框 |
| `CardView` | `MaterialCardView` | 支持描边、圆角等 MD3 属性 |
| `Toolbar` | `MaterialToolbar` | MD3 工具栏 |

### 颜色获取

使用 `LuaThemeUtil` 获取主题颜色，而非硬编码：

```lua
local ColorUtil = this.themeUtil

-- 推荐：结构化访问
local primary = ColorUtil.primary.main
local surface = ColorUtil.surface.main
local onSurface = ColorUtil.text.primary

-- 兼容：传统方法
local primary = ColorUtil.getColorPrimary()
local background = ColorUtil.getColorBackground()
```

### 尺寸单位

- 文字大小使用 **`sp`**（会跟随系统字体缩放）
- 间距和尺寸使用 **`dp`**
- ❌ 不要对文字大小使用 `dp`

---

## 4. init.lua 配置更新

### 推荐配置

```lua
app_name = "我的应用"
package_name = "com.example.myapp"
ver_name = "1.0"
ver_code = "1"
min_sdk = "26"        -- Android 8.0（旧版默认 21）
target_sdk = "33"     -- Android 13（旧版默认 29）
debug_mode = true
NeLuaJ_Theme = "Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay"
user_permission = {
  "INTERNET",
}
```

### 变更说明

| 配置项 | 旧默认值 | 新默认值 | 原因 |
|--------|---------|---------|------|
| `min_sdk` | `21` | `26` | Android 8.0 以下设备占比极低 |
| `target_sdk` | `29` | `33` | 适配 Android 13 权限模型 |
| `user_permission` | 含 `WRITE_EXTERNAL_STORAGE` | 仅 `INTERNET` | Android 13+ 不再需要存储权限 |

---

## 5. 新版模板示例

### main.lua

```lua
require "environment"

local ColorUtil = this.themeUtil

-- 主题已在 init.lua 中配置，无需手动 setTheme
activity.dynamicColor()
activity.setContentView(res.layout.main)
  .setSupportActionBar(toolbar)
  .getSupportActionBar() {
  Title = res.string.app_title,
  Elevation = 0,
}
```

### res/layout/main.lua

```lua
import "com.google.android.material.appbar.MaterialToolbar"
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.button.MaterialButton"

local ColorUtil = this.themeUtil

return {
  LinearLayout,
  orientation = "vertical",
  layout_width = "match",
  layout_height = "match",
  {
    MaterialToolbar,
    id = "toolbar",
    layout_width = "match",
    layout_height = "?attr/actionBarSize",
    BackgroundColor = ColorUtil.getColorBackground(),
  },
  {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
    gravity = "center",
    {
      MaterialTextView,
      text = "Hello NeLuaJ+",
      textSize = "24sp",
      textColor = ColorUtil.getColorPrimary(),
    },
    {
      MaterialButton,
      text = "Click Me",
      layout_marginTop = "16dp",
      onClick = function()
        print("Hello World!")
      end,
    },
  },
}
```

---

## 6. 常见问题

### Q: 深色模式下状态栏图标看不清？

A: 确保根据 `isNightMode()` 正确设置了 `setSystemUiVisibility`：

```lua
if this.isNightMode() then
    window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_VISIBLE)
else
    window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR)
end
```

### Q: 如何让状态栏和 ActionBar 颜色一致？

A: 使用 `setStatusBarColor` 设置为与 ActionBar 相同的背景色：

```lua
activity.getWindow().setStatusBarColor(ColorUtil.getColorBackground())
```

### Q: 如何实现全屏沉浸式（如图片查看器）？

A: 使用以下代码让内容延伸到系统栏下方：

```lua
pcall(function()
    local window = activity.getWindow()
    window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
    window.getDecorView().setSystemUiVisibility(
        View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
        | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        | View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR)
    window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
    window.setStatusBarColor(Color.TRANSPARENT)
    window.addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS)
end)
```

### Q: 如何获取主题颜色而不是硬编码？

A: 使用 `this.themeUtil`（详见 LuaThemeUtil 文档）：

```lua
local ColorUtil = this.themeUtil
local bg = ColorUtil.getColorBackground()
local primary = ColorUtil.primary.main
local onSurface = ColorUtil.surface.on
```
