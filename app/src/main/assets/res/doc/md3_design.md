# Material 3 Expressive 设计指南

NeLuaJ+ 使用 **Material 3 Expressive** (MD3E) 设计规范。本文档介绍如何在 Lua 布局中正确使用 MD3 组件和主题。

---

## 1. 主题设置

### 方式一：init.lua 配置（推荐）

在项目的 `init.lua` 中设置 `NeLuaJ_Theme`，Activity 启动时会自动应用：

```lua
-- init.lua
NeLuaJ_Theme = "Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay"
```

也支持 `theme` 字段，值为 `android.R.style` 中的样式名或整数 ID：

```lua
-- init.lua
theme = "Theme_Material3_DayNight"  -- android.R.style 中的样式
```

### 方式二：main.lua 手动设置

如果需要在运行时动态切换主题，可在 `main.lua` 中手动调用（必须在 `setContentView` 之前）：

```lua
activity.setTheme(R.style.Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay)
activity.dynamicColor()  -- 启用 Material You 动态取色
```

> **注意**：如果 `init.lua` 已设置 `NeLuaJ_Theme`，则无需在 `main.lua` 中重复调用 `setTheme`。

### 可用主题

| NeLuaJ_Theme 值 | 说明 |
|------|------|
| `Theme_NeLuaJ_Material3` | 带 ActionBar（默认） |
| `Theme_NeLuaJ_Material3_ActionOverlay` | 带 ActionBar + ActionMode 覆盖 |
| `Theme_NeLuaJ_Material3_NoActionBar` | 无 ActionBar |
| `Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay` | 无 ActionBar + ActionMode 覆盖（推荐） |

---

## 2. 颜色系统

MD3 使用基于色调的颜色系统。通过 `this.themeUtil` 获取：

### 主色 (Primary)
```lua
local ColorUtil = this.themeUtil
ColorUtil.primary.main          -- 主色（按钮、FAB）
ColorUtil.primary.on            -- 主色上的文字/图标
ColorUtil.primary.container     -- 主色容器（卡片高亮）
ColorUtil.primary.onContainer   -- 主色容器上的文字
```

### 表面色 (Surface) — 最常用
```lua
ColorUtil.surface.main              -- 页面背景
ColorUtil.surface.on                -- 背景上的文字
ColorUtil.surface.variant           -- 变体表面
ColorUtil.surface.onVariant         -- 变体表面上的文字
ColorUtil.surface.container         -- 容器背景
ColorUtil.surface.containerLow      -- 低层容器
ColorUtil.surface.containerHigh     -- 高层容器
ColorUtil.surface.containerHighest  -- 最高层容器
ColorUtil.surface.bright            -- 亮表面
ColorUtil.surface.dim               -- 暗表面
```

### 其他色系
```lua
ColorUtil.secondary.main / .container / .onContainer
ColorUtil.tertiary.main / .container / .onContainer
ColorUtil.error.main / .container / .onContainer
ColorUtil.outline.main      -- 边框色
ColorUtil.outline.variant   -- 淡边框色
ColorUtil.background.main   -- 背景色（≈ surface.main）
```

### 传统方法（向后兼容）
```lua
ColorUtil.getColorPrimary()
ColorUtil.getColorBackground()
ColorUtil.getColorSurfaceVariant()
ColorUtil.getAnyColor(android.R.attr.colorAccent)
```

---

## 3. 常用 MD3 组件

### MaterialToolbar — 顶部工具栏

```lua
import "com.google.android.material.appbar.MaterialToolbar"

{
    MaterialToolbar,
    id = "toolbar",
    layout_width = "match",
    layout_height = "?attr/actionBarSize",
    BackgroundColor = ColorUtil.getColorBackground(),
}
```

### MaterialButton — 按钮

```lua
import "com.google.android.material.button.MaterialButton"

-- 填充按钮（默认）
{ MaterialButton, text = "确定" }

-- 轮廓按钮
{ MaterialButton, text = "取消",
  style = "?attr/materialButtonOutlinedStyle" }

-- 文字按钮
{ MaterialButton, text = "跳过",
  style = "?attr/borderlessButtonStyle" }
```

### MaterialCardView — 卡片

```lua
import "com.google.android.material.card.MaterialCardView"

{
    MaterialCardView,
    layout_width = "match",
    layout_height = "wrap",
    layout_margin = "8dp",
    radius = "16dp",           -- 圆角
    strokeWidth = "1dp",       -- 描边宽度
    strokeColor = ColorUtil.outline.variant,
    CardBackgroundColor = ColorUtil.surface.containerLow,
    CardElevation = 0,         -- MD3 推荐 0 高度
    {
        -- 卡片内容
    }
}
```

### TextInputLayout — 输入框

```lua
import "com.google.android.material.textfield.TextInputLayout"
import "com.google.android.material.textfield.TextInputEditText"

{
    TextInputLayout,
    layout_width = "match",
    layout_height = "wrap",
    Hint = "请输入内容",
    style = "?attr/textInputOutlinedStyle",  -- 轮廓样式
    {
        TextInputEditText,
        layout_width = "match",
        layout_height = "wrap",
    }
}
```

### MaterialTextView — 文本

```lua
import "com.google.android.material.textview.MaterialTextView"

{ MaterialTextView,
  text = "标题",
  textSize = "24sp",
  textColor = ColorUtil.surface.on }

{ MaterialTextView,
  text = "正文内容",
  textSize = "14sp",
  textColor = ColorUtil.surface.onVariant }
```

### TabLayout — 标签页

```lua
import "com.google.android.material.tabs.TabLayout"

{
    TabLayout,
    id = "tabs",
    layout_width = "match",
    layout_height = "wrap",
    TabMode = 1,           -- 0=fixed, 1=scrollable, 2=auto
    TabGravity = 0,        -- 0=fill, 1=center, 2=start
}
```

### FloatingActionButton — 浮动按钮

```lua
import "com.google.android.material.floatingactionbutton.FloatingActionButton"

{
    FloatingActionButton,
    id = "fab",
    layout_width = "wrap",
    layout_height = "wrap",
    layout_gravity = "bottom|end",
    layout_margin = "16dp",
    src = "icon.png",
}
```

### Chip / ChipGroup — 标签

```lua
import "com.google.android.material.chip.Chip"
import "com.google.android.material.chip.ChipGroup"

{
    ChipGroup,
    layout_width = "match",
    layout_height = "wrap",
    {
        Chip, text = "选项1", Checkable = true,
    },
    {
        Chip, text = "选项2", Checkable = true,
    },
}
```

### MaterialDivider — 分割线

```lua
import "com.google.android.material.divider.MaterialDivider"

{ MaterialDivider, layout_width = "match", layout_height = "wrap" }
```

---

## 4. 常用布局模式

### AppBarLayout + 滚动内容

```lua
import "com.google.android.material.appbar.AppBarLayout"
import "androidx.coordinatorlayout.widget.CoordinatorLayout"

{
    CoordinatorLayout,
    layout_width = "match",
    layout_height = "match",
    fitsSystemWindows = true,
    {
        AppBarLayout,
        layout_width = "match",
        layout_height = "wrap",
        {
            MaterialToolbar,
            id = "toolbar",
            layout_width = "match",
            layout_height = "?attr/actionBarSize",
            layout_scrollFlags = "scroll|enterAlways",
        },
    },
    {
        RecyclerView,
        layout_width = "match",
        layout_height = "match",
        layout_behavior = "@string/appbar_scrolling_view_behavior",
    },
}
```

### BottomSheet — 底部弹出

```lua
import "com.google.android.material.bottomsheet.BottomSheetDialog"

local dialog = BottomSheetDialog(activity)
dialog.setContentView(loadlayout(sheetLayout))
dialog.show()
```

---

## 5. 设计原则

### 间距
- 使用 **8dp 网格**：4dp, 8dp, 12dp, 16dp, 24dp, 32dp
- 卡片内边距：**16dp**
- 列表项内边距：水平 **16dp**，垂直 **12dp**

### 圆角
- 小组件（Chip）：**8dp**
- 卡片：**12dp ~ 16dp**
- 对话框：**28dp**
- 底部弹出：**28dp**（顶部）

### 文字大小（必须用 sp）
- 标题：**24sp**
- 副标题：**16sp**
- 正文：**14sp**
- 标签/说明：**12sp**

### 颜色使用
- 背景：`surface.main` 或 `surface.container`
- 正文：`surface.on`
- 次要文字：`surface.onVariant`
- 强调：`primary.main`
- 边框：`outline.variant`
- 错误：`error.main`
