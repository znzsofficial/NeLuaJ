# LuaThemeUtil API 文档

## 类概述

`LuaThemeUtil` 是一个用于从 Android 主题中动态获取颜色属性的工具类。通过传入 `Context` 对象，可以方便地获取
Material Design 或 AppCompat 主题中定义的颜色值。

**构造函数**：

```
public LuaThemeUtil(Context context)
```

- 初始化时需要传入当前上下文的 `Context` 对象。

---

## 方法列表

### 主颜色相关

| 方法名                            | 说明           |
|--------------------------------|--------------|
| `getColorPrimary()`            | 获取主题的主色      | 
| `getColorOnPrimary()`          | 获取主色上的内容颜色   | 
| `getColorPrimaryDark()`        | 获取深色主色（旧版）   | 
| `getColorPrimaryVariant()`     | 获取主色变体       | 
| `getColorPrimaryContainer()`   | 获取主色容器颜色     | 
| `getColorOnPrimaryContainer()` | 获取主色容器上的内容颜色 | 
| `getColorPrimaryInverse()`     | 获取反色主色       | 
| `getColorPrimarySurface()`     | 获取表面主色       | 

### 强调色

| 方法名                | 说明        | 
|--------------------|-----------|
| `getColorAccent()` | 获取强调色（旧版） |

### 次颜色相关

| 方法名                              | 说明           | 
|----------------------------------|--------------|
| `getColorSecondary()`            | 获取次色         |
| `getColorOnSecondary()`          | 获取次色上的内容颜色   |
| `getColorSecondaryVariant()`     | 获取次色变体       |
| `getColorSecondaryContainer()`   | 获取次色容器颜色     |
| `getColorOnSecondaryContainer()` | 获取次色容器上的内容颜色 |

### 第三颜色相关

| 方法名                             | 说明            | 
|---------------------------------|---------------|
| `getColorTertiary()`            | 获取第三色         |
| `getColorOnTertiary()`          | 获取第三色上的内容颜色   |
| `getColorTertiaryContainer()`   | 获取第三色容器颜色     | 
| `getColorOnTertiaryContainer()` | 获取第三色容器上的内容颜色 | 

### 错误颜色相关

| 方法名                          | 说明           | 
|------------------------------|--------------|
| `getColorError()`            | 获取错误色        | 
| `getColorOnError()`          | 获取错误色上的内容颜色  | 
| `getColorErrorContainer()`   | 获取错误容器颜色     | 
| `getColorOnErrorContainer()` | 获取错误容器上的内容颜色 |

### 表面颜色相关

| 方法名                          | 说明           | 
|------------------------------|--------------|
| `getColorSurface()`          | 获取表面颜色       | 
| `getColorSurfaceInverse()`   | 获取反色表面颜色     |
| `getColorSurfaceVariant()`   | 获取表面变体颜色     |
| `getColorOnSurface()`        | 获取表面上的内容颜色   | 
| `getColorOnSurfaceInverse()` | 获取反色表面上的内容颜色 | 
| `getColorOnSurfaceVariant()` | 获取表面变体上的内容颜色 | 
| `getColorOnPrimarySurface()` | 获取主表面上的内容颜色  | 

### 其他颜色

| 方法名                        | 说明         | 
|----------------------------|------------|
| `getColorOutline()`        | 获取轮廓颜色     | 
| `getTitleTextColor()`      | 获取标题文本颜色   | 
| `getSubTitleTextColor()`   | 获取副标题文本颜色  | 
| `getActionMenuTextColor()` | 获取操作菜单文本颜色 |
| `getTextColor()`           | 获取默认文本颜色   | 
| `getTextColorHint()`       | 获取提示文本颜色   | 
| `getTextColorHighlight()`  | 获取文本高亮颜色   | 
| `getEditTextColor()`       | 获取编辑框文本颜色  | 

### 背景颜色

| 方法名                      | 说明         | 
|--------------------------|------------|
| `getColorBackground()`   | 获取背景颜色     | 
| `getColorOnBackground()` | 获取背景上的内容颜色 | 

### 通用方法

| 方法名                       | 说明             | 参数                |
|---------------------------|----------------|-------------------|
| `getAnyColor(int attrId)` | 通过属性 ID 获取任意颜色 | `attrId`: 颜色属性 ID |

---

## 使用示例

```lua
import "github.daisukiKaffuChino.utils.LuaThemeUtil"
local themeUtil = LuaThemeUtil(this)
local primaryColor = themeUtil.getColorPrimary()
local errorColor = themeUtil.getColorError()
```