# 颜色与主题 API

NeLuaJ+ 提供了一套完整的 Material 3 颜色 API，支持动态主题色、颜色协调、颜色角色查询等功能。

---

## dynamicColor — 动态主题色

### 跟随系统壁纸

```lua
-- 使用系统壁纸动态取色（Android 12+）
this.dynamicColor()
```

调用后 Activity 的主题色会跟随系统壁纸颜色。`themeUtil` 获取的所有颜色会自动更新。

### 自定义 Seed Color

```lua
-- 传入种子色，生成完整的 Material 3 色板并应用到 Activity
this.dynamicColor(0xFF6750A4)
```

传入任意颜色值作为种子色，Material 3 算法会自动生成完整的 primary / secondary / tertiary / neutral / error 色板并应用到当前 Activity。

调用后 `themeUtil` 会反映新的色板：

```lua
this.dynamicColor(0xFF1B6B3A) -- 绿色种子

-- themeUtil 现在返回基于绿色生成的完整色板
local primary = this.themeUtil.getColorPrimary()
local secondary = this.themeUtil.getColorSecondary()
local surface = this.themeUtil.surface.container
```

> **注意**：`dynamicColor` 必须在 `setContentView` 之前调用，否则已创建的 View 不会更新。典型用法是在 `main.lua` 最开头调用。

### 完整示例

```lua
-- 根据用户选择的颜色动态切换主题
local seedColor = 0xFF2196F3 -- 蓝色

-- 应用种子色主题
this.dynamicColor(seedColor)

-- 后续所有 UI 都会使用基于蓝色生成的色板
local ColorUtil = this.themeUtil
activity.setContentView(loadlayout({
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
    BackgroundColor = ColorUtil.getColorBackground(),
    {
        MaterialButton,
        text = "Hello",
        -- 按钮自动使用新的 primary 色
    },
}))
```

---

## harmonizeColor — 颜色协调

将一个自定义颜色与当前主题色进行协调，使其在视觉上与主题和谐统一。

### 与主题 Primary 协调

```lua
-- 将红色与当前主题的 primary 色协调
local red = 0xFFFF0000
local harmonized = this.harmonizeColor(red)
-- harmonized 是一个偏向主题色调的红色
```

### 两个颜色互相协调

```lua
-- 将 color1 向 color2 的色调偏移
local result = this.harmonizeColor(color1, color2)
```

### 使用场景

```lua
-- 错误色与主题协调
local errorRed = 0xFFB3261E
local themedError = this.harmonizeColor(errorRed)

-- 自定义标签色与主题协调
local tagColors = {0xFFE91E63, 0xFF9C27B0, 0xFF2196F3, 0xFF4CAF50}
for i, color in ipairs(tagColors) do
    tagColors[i] = this.harmonizeColor(color)
end
```

---

## isColorLight — 颜色明暗判断

判断一个颜色是浅色还是深色，常用于决定文字颜色。

```lua
local bg = 0xFFE8DEF8
if this.isColorLight(bg) then
    textView.setTextColor(0xFF000000) -- 浅色背景用深色文字
else
    textView.setTextColor(0xFFFFFFFF) -- 深色背景用浅色文字
end
```

---

## themeUtil — 主题色获取

`this.themeUtil` 提供当前主题的所有 Material 3 颜色。调用 `dynamicColor()` 后会自动反映新色板。

### 结构化访问

```lua
local t = this.themeUtil

-- Primary 色组
t.primary.main           -- 主色
t.primary.on             -- 主色上的内容色
t.primary.container      -- 主色容器
t.primary.onContainer    -- 主色容器上的内容色
t.primary.inverse        -- 反色主色
t.primary.fixed          -- 固定主色
t.primary.fixedDim       -- 固定主色（暗）
t.primary.onFixed        -- 固定主色上的内容色
t.primary.onFixedVariant -- 固定主色变体上的内容色

-- Secondary 色组
t.secondary.main / .on / .container / .onContainer
t.secondary.fixed / .fixedDim / .onFixed / .onFixedVariant

-- Tertiary 色组
t.tertiary.main / .on / .container / .onContainer
t.tertiary.fixed / .fixedDim / .onFixed / .onFixedVariant

-- Error 色组
t.error.main / .on / .container / .onContainer

-- Surface 色组
t.surface.main           -- 表面色
t.surface.on             -- 表面上的内容色
t.surface.variant        -- 表面变体
t.surface.onVariant      -- 表面变体上的内容色
t.surface.inverse        -- 反色表面
t.surface.onInverse      -- 反色表面上的内容色
t.surface.bright         -- 亮表面
t.surface.dim            -- 暗表面
t.surface.container      -- 表面容器
t.surface.containerLow   -- 表面容器（低）
t.surface.containerLowest-- 表面容器（最低）
t.surface.containerHigh  -- 表面容器（高）
t.surface.containerHighest-- 表面容器（最高）

-- Background 色组
t.background.main / .on

-- Text 色组
t.text.primary / .hint / .highlight / .title / .subtitle

-- Outline 色组
t.outline.main / .variant
```

### 兼容方法

```lua
local t = this.themeUtil

t.getColorPrimary()
t.getColorOnPrimary()
t.getColorPrimaryContainer()
t.getColorOnPrimaryContainer()
t.getColorSecondary()
t.getColorSecondaryContainer()
t.getColorTertiary()
t.getColorError()
t.getColorSurface()
t.getColorOnSurface()
t.getColorSurfaceVariant()
t.getColorOnSurfaceVariant()
t.getColorSurfaceContainer()
t.getColorSurfaceContainerHigh()
t.getColorSurfaceContainerHighest()
t.getColorBackground()
t.getColorOnBackground()
t.getColorOutline()
t.getColorOutlineVariant()
-- ... 更多见 LuaThemeUtil 源码
```

### 获取任意主题属性颜色

```lua
-- 通过 attr 资源 ID 获取任意主题颜色
local color = this.themeUtil.getAnyColor(MDC_R.attr.colorTertiaryContainer)
```

---

## Java 类直接调用

以上 API 底层使用的 Java 类也可以在 Lua 中直接调用：

```lua
import "com.google.android.material.color.MaterialColors"
import "com.google.android.material.color.ColorRoles"

-- 从任意颜色生成 4 个角色色
local roles = MaterialColors.getColorRoles(activity, 0xFF6750A4)
local accent = roles.getAccent()
local onAccent = roles.getOnAccent()
local accentContainer = roles.getAccentContainer()
local onAccentContainer = roles.getOnAccentContainer()

-- 颜色叠加
local layered = MaterialColors.layer(bgColor, overlayColor, 0.5)

-- 带透明度合成
local composite = MaterialColors.compositeARGBWithAlpha(color, 128)
```

---

## API 速查表

| 方法 | 说明 | 返回值 |
|------|------|--------|
| `this.dynamicColor()` | 跟随系统壁纸取色 | void |
| `this.dynamicColor(seedColor)` | 从种子色生成完整色板 | void |
| `this.harmonizeColor(color)` | 与主题 primary 协调 | int (颜色值) |
| `this.harmonizeColor(color, withColor)` | 两色互相协调 | int (颜色值) |
| `this.isColorLight(color)` | 判断颜色明暗 | boolean |
| `this.themeUtil.*` | 获取当前主题色 | int (颜色值) |
| `this.themeUtil.getAnyColor(attrId)` | 获取任意主题属性色 | int (颜色值) |
