# 布局表属性参考

`loadlayout` 将 Lua 表转换为 Android 视图。本文档列出所有支持的属性。

---

## 1. 基本结构

```lua
return {
    ViewClass,              -- 第一个元素必须是 View 类
    属性名 = 属性值,          -- 视图属性
    { ChildViewClass, ... } -- 子视图
}
```

---

## 2. 通用属性

### 尺寸

| 属性 | 说明 | 示例 |
|------|------|------|
| `layout_width` | 宽度 | `"match"`, `"wrap"`, `"200dp"`, `"50%"` |
| `layout_height` | 高度 | `"match"`, `"wrap"`, `"100dp"` |
| `minWidth` | 最小宽度 | `"48dp"` |
| `minHeight` | 最小高度 | `"48dp"` |

**尺寸值简写**：

| 值 | 等价于 |
|----|--------|
| `"match"` / `"fill"` / `"-1"` | `match_parent` |
| `"wrap"` / `"-2"` | `wrap_content` |

**尺寸单位**：

| 后缀 | 说明 | 示例 |
|------|------|------|
| `dp` | 密度无关像素 | `"16dp"` |
| `sp` | 缩放像素（文字专用） | `"14sp"` |
| `px` | 像素 | `"1px"` |
| `%` / `%w` | 屏幕宽度百分比 | `"50%"` |
| `%h` | 屏幕高度百分比 | `"30%h"` |
| `pt` | 点 | `"12pt"` |
| `in` | 英寸 | `"0.5in"` |
| `mm` | 毫米 | `"10mm"` |

### 间距

| 属性 | 说明 |
|------|------|
| `padding` | 四边内边距 |
| `paddingLeft` / `paddingStart` | 左/起始内边距 |
| `paddingRight` / `paddingEnd` | 右/末端内边距 |
| `paddingTop` | 上内边距 |
| `paddingBottom` | 下内边距 |
| `layout_margin` | 四边外边距 |
| `layout_marginLeft` / `layout_marginStart` | 左/起始外边距 |
| `layout_marginRight` / `layout_marginEnd` | 右/末端外边距 |
| `layout_marginTop` | 上外边距 |
| `layout_marginBottom` | 下外边距 |

### 可见性

| 属性 | 值 | 说明 |
|------|-----|------|
| `visibility` | `"visible"` | 可见（默认） |
| | `"invisible"` | 不可见但占位 |
| | `"gone"` | 不可见且不占位 |

### 背景

```lua
-- 颜色值
background = 0xFFFF0000          -- 整数颜色
background = "#FF0000"           -- 十六进制字符串
background = "#80FF0000"         -- 带透明度

-- Drawable 对象
background = drawable

-- 图片路径（自动加载）
background = "bg.png"
```

### ID

```lua
id = "myView"  -- 设置 ID，之后可通过变量名 myView 访问
```

---

## 3. 文本属性

| 属性 | 说明 | 示例 |
|------|------|------|
| `text` | 文本内容 | `"Hello"` |
| `hint` | 提示文本 | `"请输入..."` |
| `textSize` | 文字大小（用 sp） | `"14sp"` |
| `textColor` | 文字颜色 | `0xFF000000` |
| `textStyle` | 文字样式 | `"bold"`, `"italic"`, `"bold\|italic"`, `"normal"` |
| `ellipsize` | 省略方式 | `"END"`, `"START"`, `"MIDDLE"`, `"MARQUEE"` |
| `singleLine` | 单行模式 | `true` |
| `maxLines` | 最大行数 | `3` |
| `gravity` | 文字对齐 | `"center"`, `"left"`, `"right"` |
| `textAlignment` | 文字对齐 | 见下表 |
| `inputType` | 输入类型 | 见下表 |
| `imeOptions` | IME 选项 | 见下表 |
| `autoLink` | 自动链接 | `"web"`, `"email"`, `"all"` |

### textAlignment 值

| 值 | 说明 |
|----|------|
| `"inherit"` | 继承父视图 |
| `"gravity"` | 跟随 gravity |
| `"textStart"` | 文本起始对齐 |
| `"textEnd"` | 文本末端对齐 |
| `"textCenter"` | 文本居中 |
| `"viewStart"` | 视图起始对齐 |
| `"viewEnd"` | 视图末端对齐 |

### inputType 值

| 值 | 说明 |
|----|------|
| `"text"` | 普通文本 |
| `"textMultiLine"` | 多行文本 |
| `"textPassword"` | 密码 |
| `"textVisiblePassword"` | 可见密码 |
| `"textUri"` | URI |
| `"textEmailAddress"` | 邮箱 |
| `"textCapWords"` | 首字母大写 |
| `"textCapSentences"` | 句首大写 |
| `"textAutoCorrect"` | 自动纠错 |
| `"textNoSuggestions"` | 无建议 |
| `"number"` | 数字 |
| `"numberSigned"` | 带符号数字 |
| `"numberDecimal"` | 小数 |
| `"numberPassword"` | 数字密码 |
| `"phone"` | 电话号码 |
| `"datetime"` | 日期时间 |
| `"date"` | 日期 |
| `"time"` | 时间 |

### imeOptions 值

| 值 | 说明 |
|----|------|
| `"actionDone"` | 完成 |
| `"actionSearch"` | 搜索 |
| `"actionSend"` | 发送 |
| `"actionNext"` | 下一个 |
| `"actionGo"` | 前往 |
| `"actionPrevious"` | 上一个 |
| `"actionNone"` | 无动作 |
| `"flagNoFullscreen"` | 禁止全屏 |
| `"flagNoExtractUi"` | 禁止提取 UI |

---

## 4. 图片属性

| 属性 | 说明 | 示例 |
|------|------|------|
| `src` | 图片源 | `"icon.png"`, URL 字符串, Bitmap, Drawable |
| `scaleType` | 缩放类型 | 见下表 |

**scaleType 值**：

| 值 | 说明 |
|----|------|
| `"fitCenter"` | 等比缩放居中（默认） |
| `"centerCrop"` | 等比缩放裁剪填满 |
| `"centerInside"` | 等比缩放不超出 |
| `"fitXY"` | 拉伸填满 |
| `"center"` | 原始大小居中 |
| `"fitStart"` | 等比缩放靠左上 |
| `"fitEnd"` | 等比缩放靠右下 |

---

## 5. View 通用属性

以下属性可用于任何 View，直接通过 Java 反射设置：

| 属性 | 说明 | 示例 |
|------|------|------|
| `alpha` | 透明度 (0.0~1.0) | `0.5` |
| `rotation` | 旋转角度 | `45` |
| `rotationX` / `rotationY` | X/Y 轴旋转 | `30` |
| `scaleX` / `scaleY` | X/Y 轴缩放 | `1.5` |
| `translationX` / `translationY` | X/Y 轴平移 | `"10dp"` |
| `elevation` | 高度（阴影） | `"4dp"` |
| `enabled` | 是否启用 | `true` / `false` |
| `clickable` | 是否可点击 | `true` |
| `focusable` | 是否可获取焦点 | `true` |
| `focusableInTouchMode` | 触摸模式下可获取焦点 | `true` |
| `selected` | 是否选中 | `true` |
| `clipToPadding` | 是否裁剪到 padding | `false` |
| `clipChildren` | 是否裁剪子视图 | `false` |
| `layerType` | 图层类型 | `"none"`, `"software"`, `"hardware"` |
| `layoutDirection` | 布局方向 | `"ltr"`, `"rtl"`, `"locale"` |
| `drawingCacheQuality` | 绘制缓存质量 | `"auto"`, `"low"`, `"high"` |
| `scrollbarStyle` | 滚动条样式 | `"insideOverlay"`, `"outsideOverlay"` |
| `horizontalScrollBarEnabled` | 水平滚动条 | `true` / `false` |
| `verticalScrollBarEnabled` | 垂直滚动条 | `true` / `false` |
| `BackgroundResource` | 背景资源 ID | `rippleRes` |
| `BackgroundColor` | 背景颜色 | `0xFFFF0000` |

> **提示**：任何 View 的 Java setter 方法都可以作为属性使用。例如 `setAlpha(0.5f)` 对应 `alpha = 0.5`，`setEnabled(false)` 对应 `enabled = false`。首字母大写的属性名（如 `BackgroundColor`）会调用对应的 `setBackgroundColor` 方法。

---

## 6. LinearLayout 属性

| 属性 | 说明 | 值 |
|------|------|----|
| `orientation` | 排列方向 | `"vertical"`, `"horizontal"` |
| `gravity` | 子视图对齐 | 见下表 |
| `layout_weight` | 权重 | 数字，如 `1` |
| `layout_gravity` | 自身在父中的对齐 | 同 gravity |

### Gravity 值

| 值 | 说明 |
|----|------|
| `"center"` | 居中 |
| `"center_horizontal"` | 水平居中 |
| `"center_vertical"` | 垂直居中 |
| `"top"` | 顶部 |
| `"bottom"` | 底部 |
| `"left"` | 左侧 |
| `"right"` | 右侧 |
| `"start"` | 起始端（RTL 感知） |
| `"end"` | 末端（RTL 感知） |
| `"fill_horizontal"` | 水平填充 |
| `"fill_vertical"` | 垂直填充 |
| `"no_gravity"` | 无对齐 |
| `"clip_horizontal"` | 水平裁剪 |
| `"clip_vertical"` | 垂直裁剪 |

**组合**：用 `|` 连接，如 `"center_vertical|right"`, `"bottom|end"`

---

## 6. RelativeLayout 规则

```lua
{
    RelativeLayout,
    layout_width = "match",
    layout_height = "match",
    {
        TextView, id = "title", text = "标题",
        layout_alignParentTop = true,
        layout_centerHorizontal = true,
    },
    {
        TextView, text = "副标题",
        layout_below = "title",          -- 在 title 下方
        layout_centerHorizontal = true,
    },
}
```

### 相对于父容器

| 属性 | 说明 |
|------|------|
| `layout_alignParentTop` | 对齐父顶部 |
| `layout_alignParentBottom` | 对齐父底部 |
| `layout_alignParentLeft` / `Start` | 对齐父左/起始 |
| `layout_alignParentRight` / `End` | 对齐父右/末端 |
| `layout_centerInParent` | 父内居中 |
| `layout_centerHorizontal` | 水平居中 |
| `layout_centerVertical` | 垂直居中 |

### 相对于兄弟视图

| 属性 | 说明 |
|------|------|
| `layout_above` | 在目标上方 |
| `layout_below` | 在目标下方 |
| `layout_toLeftOf` / `toStartOf` | 在目标左/起始侧 |
| `layout_toRightOf` / `toEndOf` | 在目标右/末端侧 |
| `layout_alignTop` | 顶部对齐 |
| `layout_alignBottom` | 底部对齐 |
| `layout_alignLeft` / `alignStart` | 左/起始对齐 |
| `layout_alignRight` / `alignEnd` | 右/末端对齐 |
| `layout_alignBaseline` | 基线对齐 |

---

## 7. CoordinatorLayout 属性

| 属性 | 说明 | 值 |
|------|------|----|
| `layout_behavior` | 行为 | 见下表 |
| `layout_anchor` | 锚点视图 ID | `"fab"` |
| `layout_scrollFlags` | 滚动标志 | 见下表 |
| `layout_collapseMode` | 折叠模式 | `"pin"`, `"parallax"` |
| `layout_collapseParallaxMultiplier` | 视差系数 | `0.5` |
| `fitsSystemWindows` | 处理系统栏间距 | `true` |

### Behavior 值

| 值 | 说明 |
|----|------|
| `"@string/appbar_scrolling_view_behavior"` | 跟随 AppBar 滚动 |
| `"@string/bottom_sheet_behavior"` | 底部弹出行为 |
| `"@string/side_sheet_behavior"` | 侧边弹出行为 |
| `"@string/hide_bottom_view_on_scroll_behavior"` | 滚动时隐藏底部视图 |
| `"@string/hide_view_on_scroll_behavior"` | 滚动时隐藏视图 |
| `"@string/searchbar_scrolling_view_behavior"` | SearchBar 滚动行为 |
| `"@string/fab_transformation_scrim_behavior"` | FAB 变换遮罩 |
| `"@string/fab_transformation_sheet_behavior"` | FAB 变换为 Sheet |

### ScrollFlags 值

| 值 | 说明 |
|----|------|
| `"scroll"` | 可滚动 |
| `"enterAlways"` | 向下滚动时立即显示 |
| `"exitUntilCollapsed"` | 向上滚动时折叠到最小高度 |
| `"snap"` | 吸附效果 |

---

## 8. 事件监听

所有以 `on` 开头的属性会被设置为事件监听器：

```lua
{
    MaterialButton,
    text = "点击",
    onClick = function(view)
        print("被点击了")
    end,
    onLongClick = function(view)
        print("被长按了")
        return true  -- 返回 true 表示已消费
    end,
}
```

常用事件：

| 属性 | 说明 |
|------|------|
| `onClick` | 点击 |
| `onLongClick` | 长按 |
| `onTouch` | 触摸 |
| `onFocusChange` | 焦点变化 |
| `onItemClick` | 列表项点击 |
| `onItemLongClick` | 列表项长按 |
| `onCheckedChange` | 选中状态变化 |
| `onScrollChange` | 滚动变化 |

---

## 10. 列表与容器属性

### ListView / Spinner

| 属性 | 说明 | 示例 |
|------|------|------|
| `items` | 字符串数组，自动创建 Adapter | `{ "选项1", "选项2" }` |
| `DividerHeight` | 分割线高度 | `0`, `1` |
| `FastScrollEnabled` | 快速滚动 | `true` |

```lua
{
    ListView,
    id = "list",
    items = { "苹果", "香蕉", "橙子" },
    DividerHeight = 0,
    onItemClick = function(parent, view, pos, id)
        print("点击了第", pos, "项")
    end,
}
```

### ViewPager

| 属性 | 说明 | 示例 |
|------|------|------|
| `pages` | View 列表 | `{ view1, view2, view3 }` |
| `pagesWithTitle` | 带标题的页面 | `{ {view1, view2}, {"标题1", "标题2"} }` |

```lua
{
    ViewPager,
    id = "pager",
    pages = { page1View, page2View },
}

-- 带标题（配合 TabLayout）
{
    ViewPager,
    id = "pager",
    pagesWithTitle = {
        { page1View, page2View },
        { "首页", "设置" },
    },
}
```

### ScrollView

| 属性 | 说明 | 示例 |
|------|------|------|
| `fillViewport` | 内容不足时填满 | `true` |
| `scrollbars` | 滚动条 | `"vertical"`, `"horizontal"`, `"none"` |

> **注意**：`ScrollView` 只能有一个子视图，通常是 `LinearLayout`。

### RecyclerView

RecyclerView 需要在 Lua 代码中设置 LayoutManager 和 Adapter：

```lua
import "androidx.recyclerview.widget.LinearLayoutManager"

recyclerView.setLayoutManager(LinearLayoutManager(activity))
recyclerView.setAdapter(adapter)
```

---

## 11. style 属性

通过 `style` 属性应用 Android 主题样式：

```lua
-- 使用主题属性引用
{ MaterialButton, text = "轮廓按钮",
  style = "?attr/materialButtonOutlinedStyle" }

-- 使用资源 ID
{ MaterialButton, text = "文字按钮",
  style = "?attr/borderlessButtonStyle" }
```

---

## 12. 完整示例

```lua
import "com.google.android.material.appbar.MaterialToolbar"
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.button.MaterialButton"
import "com.google.android.material.card.MaterialCardView"

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
        ScrollView,
        layout_width = "match",
        layout_height = "match",
        {
            LinearLayout,
            orientation = "vertical",
            layout_width = "match",
            layout_height = "wrap",
            padding = "16dp",
            {
                MaterialCardView,
                layout_width = "match",
                layout_height = "wrap",
                radius = "16dp",
                CardElevation = 0,
                strokeWidth = "1dp",
                strokeColor = ColorUtil.outline.variant,
                {
                    LinearLayout,
                    orientation = "vertical",
                    padding = "16dp",
                    layout_width = "match",
                    layout_height = "wrap",
                    {
                        MaterialTextView,
                        text = "欢迎",
                        textSize = "24sp",
                        textColor = ColorUtil.surface.on,
                    },
                    {
                        MaterialTextView,
                        text = "这是一个示例卡片",
                        textSize = "14sp",
                        textColor = ColorUtil.surface.onVariant,
                        layout_marginTop = "8dp",
                    },
                    {
                        MaterialButton,
                        text = "了解更多",
                        layout_marginTop = "16dp",
                    },
                },
            },
        },
    },
}
```
