# LuaThemeUtil API 文档

## 1. 类概述

`LuaThemeUtil` 是一个强大的工具类，用于从 Android App 的当前主题中动态获取颜色。它完美适配 Material Design 3 (Material You) 和旧版 Material/AppCompat 主题，让你的 LuaJ 脚本界面与 App 的原生主题保持一致。

该类提供了两种访问颜色的方式：
1.  **结构化访问 (推荐)**：通过逻辑分组（如 `primary`, `surface`, `text`）来获取颜色，代码更清晰、更易读。
2.  **传统方法访问**：保留了所有旧的 `get...()` 方法，确保与旧脚本的完全兼容。

**构造函数**:

```lua
local themeUtil = LuaThemeUtil(activity) 
```

- **参数**: `context` - 必须传入一个 Android `Context` 对象。

---

## 2. 结构化访问 (推荐用法)

这是获取颜色的首选方式。它通过逻辑分组的对象来访问，使代码意图一目了然。

### 示例

```lua
import "github.daisukiKaffuChino.utils.LuaThemeUtil"
local themeUtil = LuaThemeUtil(activity)

-- 或直接使用 LuaActvity.getThemeUtil()
local themeUtil = this.themeUtil

-- 获取主色
local primaryColor = themeUtil.primary.main

-- 获取表面容器颜色
local surfaceContainerColor = themeUtil.surface.container

-- 获取默认文本颜色
local textColor = themeUtil.text.primary

-- 获取错误颜色
local errorColor = themeUtil.error.main
```

---

## 3. API 分组详解

下面是所有可用的结构化颜色分组及其属性。

### 3.1 `themeUtil.primary` - 主色系

| 属性               | 完整方法名                 | 说明                               |
|------------------|-----------------------|----------------------------------|
| `main`           | `getMain()`           | 主色 (`colorPrimary`)              |
| `on`             | `getOn()`             | 主色上的内容颜色 (`colorOnPrimary`)      |
| `container`      | `getContainer()`      | 主色容器颜色 (`colorPrimaryContainer`) |
| `onContainer`    | `getOnContainer()`    | 主色容器上的内容颜色                       |
| `fixed`          | `getFixed()`          | 固定主色 (M3)                        |
| `onFixed`        | `getOnFixed()`        | 固定主色上的内容颜色 (M3)                  |
| `fixedDim`       | `getFixedDim()`       | 较暗的固定主色 (M3)                     |
| `onFixedVariant` | `getOnFixedVariant()` | 固定主色上的内容变体颜色 (M3)                |
| `inverse`        | `getInverse()`        | 反色主色 (`colorPrimaryInverse`)     |
| `dark`           | `getDark()`           | 深色主色 (`colorPrimaryDark`, 旧版)    |
| `variant`        | `getVariant()`        | 主色变体 (`colorPrimaryVariant`, 旧版) |

### 3.2 `themeUtil.secondary` - 次要/辅助色系

| 属性               | 完整方法名                 | 说明                                   |
|------------------|-----------------------|--------------------------------------|
| `main`           | `getMain()`           | 次要颜色 (`colorSecondary`)              |
| `on`             | `getOn()`             | 次要颜色上的内容颜色                           |
| `container`      | `getContainer()`      | 次要颜色容器                               |
| `onContainer`    | `getOnContainer()`    | 次要颜色容器上的内容颜色                         |
| `fixed`          | `getFixed()`          | 固定次要色 (M3)                           |
| `onFixed`        | `getOnFixed()`        | 固定次要色上的内容颜色 (M3)                     |
| `fixedDim`       | `getFixedDim()`       | 较暗的固定次要色 (M3)                        |
| `onFixedVariant` | `getOnFixedVariant()` | 固定次要色上的内容变体颜色 (M3)                   |
| `variant`        | `getVariant()`        | 次要颜色变体 (`colorSecondaryVariant`, 旧版) |

### 3.3 `themeUtil.tertiary` - 第三色系

| 属性               | 完整方法名                 | 说明                    |
|------------------|-----------------------|-----------------------|
| `main`           | `getMain()`           | 第三色 (`colorTertiary`) |
| `on`             | `getOn()`             | 第三色上的内容颜色             |
| `container`      | `getContainer()`      | 第三色容器                 |
| `onContainer`    | `getOnContainer()`    | 第三色容器上的内容颜色           |
| `fixed`          | `getFixed()`          | 固定第三色 (M3)            |
| `onFixed`        | `getOnFixed()`        | 固定第三色上的内容颜色 (M3)      |
| `fixedDim`       | `getFixedDim()`       | 较暗的固定第三色 (M3)         |
| `onFixedVariant` | `getOnFixedVariant()` | 固定第三色上的内容变体颜色 (M3)    |

### 3.4 `themeUtil.error` - 错误状态色系

| 属性            | 完整方法名              | 说明                  |
|---------------|--------------------|---------------------|
| `main`        | `getMain()`        | 错误颜色 (`colorError`) |
| `on`          | `getOn()`          | 错误颜色上的内容颜色          |
| `container`   | `getContainer()`   | 错误颜色容器              |
| `onContainer` | `getOnContainer()` | 错误颜色容器上的内容颜色        |

### 3.5 `themeUtil.surface` - 表面/卡片色系

这是 UI 组件背景（如卡片、对话框、菜单）最常用的颜色。

| 属性                 | 完整方法名                   | 说明                                  |
|--------------------|-------------------------|-------------------------------------|
| `main`             | `getMain()`             | 基础表面颜色 (`colorSurface`)             |
| `on`               | `getOn()`               | 基础表面上的内容颜色                          |
| `variant`          | `getVariant()`          | 表面变体颜色                              |
| `onVariant`        | `getOnVariant()`        | 表面变体上的内容颜色                          |
| `inverse`          | `getInverse()`          | 反色表面                                |
| `onInverse`        | `getOnInverse()`        | 反色表面上的内容颜色                          |
| `container`        | `getContainer()`        | 表面容器色 (M3, 默认层级)                    |
| `containerLow`     | `getContainerLow()`     | 表面容器色 (M3, 低层级)                     |
| `containerLowest`  | `getContainerLowest()`  | 表面容器色 (M3, 最低层级)                    |
| `containerHigh`    | `getContainerHigh()`    | 表面容器色 (M3, 高层级)                     |
| `containerHighest` | `getContainerHighest()` | 表面容器色 (M3, 最高层级)                    |
| `bright`           | `getBright()`           | 明亮的表面色 (M3)                         |
| `dim`              | `getDim()`              | 昏暗的表面色 (M3)                         |
| `primary`          | `getPrimary()`          | 主表面色 (`colorPrimarySurface`)        |
| `onPrimary`        | `getOnPrimary()`        | 主表面上的内容颜色 (`colorOnPrimarySurface`) |

### 3.6 `themeUtil.background` - 背景色系

| 属性     | 完整方法名       | 说明          |
|--------|-------------|-------------|
| `main` | `getMain()` | 窗口或屏幕的默认背景色 |
| `on`   | `getOn()`   | 背景色上的内容颜色   |

### 3.7 `themeUtil.text` - 文本颜色

| 属性           | 完整方法名             | 说明                |
|--------------|-------------------|-------------------|
| `primary`    | `getPrimary()`    | 主要/默认文本颜色         |
| `hint`       | `getHint()`       | 输入框提示文本颜色         |
| `highlight`  | `getHighlight()`  | 文本选中时的高亮背景        |
| `title`      | `getTitle()`      | 标题文本颜色            |
| `subtitle`   | `getSubtitle()`   | 副标题文本颜色           |
| `actionMenu` | `getActionMenu()` | 操作菜单项文本颜色         |
| `editText`   | `getEditText()`   | 编辑框（EditText）文本颜色 |

### 3.8 `themeUtil.outline` - 轮廓/边框颜色

| 属性        | 完整方法名          | 说明      |
|-----------|----------------|---------|
| `main`    | `getMain()`    | 主要轮廓线颜色 |
| `variant` | `getVariant()` | 轮廓线变体颜色 |

---

## 4. 传统方法

如果你需要维护旧代码，或者习惯于旧的 `get...()` 方法名，它们依然可用。

**getter 简写兼容性**: `themeUtil.getColorPrimary()` 也可以简写为 `themeUtil.colorPrimary`。

### 示例

```lua
-- 使用完整方法名
local primaryColor = themeUtil.getColorPrimary()
local errorColor = themeUtil.getColorError()

-- 使用 getter 简写
local onPrimaryColor = themeUtil.colorOnPrimary
local tertiaryColor = themeUtil.colorTertiary
```

### 传统方法列表

| 方法                                                     | 说明         |
|--------------------------------------------------------|------------|
| `getColorPrimary()` / `colorPrimary`                   | 获取主题的主色    |
| `getColorOnPrimary()` / `colorOnPrimary`               | 主色上的内容颜色   |
| `getColorPrimaryContainer()` / `colorPrimaryContainer` | 主色容器颜色     |
| `getColorSecondary()` / `colorSecondary`               | 获取次色       |
| `getColorError()` / `colorError`                       | 获取错误色      |
| `getColorSurface()` / `colorSurface`                   | 获取表面颜色     |
| `getColorBackground()` / `colorBackground`             | 获取背景颜色     |
| `getTextColor()` / `textColor`                         | 获取默认文本颜色   |
| `getColorAccent()` / `colorAccent`                     | 获取强调色 (旧版) |
| ... (其他所有 `get...` 方法都支持)                              | ...        |

---

## 5. 通用方法

如果你需要获取一个不在列表中的、自定义的颜色属性，可以使用此方法。

| 方法                | 说明             | 参数                                          |
|-------------------|----------------|---------------------------------------------|
| `getAnyColor(id)` | 通过属性 ID 获取任意颜色 | `id`: 颜色属性的整数 ID，例如 `android.R.attr.button` |

### 示例

```lua
-- 假设你需要一个特殊的、未在上面列出的颜色
-- 首先需要获取它的 R 值
local my_attr = android.R.attr.colorActivatedHighlight
local customColor = themeUtil.getAnyColor(my_attr)
```