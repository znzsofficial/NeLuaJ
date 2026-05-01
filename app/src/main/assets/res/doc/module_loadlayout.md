## 介绍
使用 LuaLayout 加载布局表的函数。

支持更多属性，例如 `textStyle`、`layout_anchor`、`pages`（for ViewPager）等，并支持 Material 组件的主题/样式增强：`theme`、`style`、`styleAttr`、`styleRes`。

参数类型分别为 `LuaTable`、`LuaTable`、`ViewGroup.LayoutParams`。

```lua
loadlayout(layout)
loadlayout(layout, _G)
loadlayout(layout, _G, FrameLayout.LayoutParams)
```

## 基本结构

布局表的第一个元素必须是 View 类，后续键值会作为属性写入 View，数字索引用作子视图。

```lua
return {
	LinearLayout,
	orientation = "vertical",
	layout_width = "match",
	layout_height = "match",
	{
		TextView,
		id = "title",
		text = "标题",
		textSize = "20sp",
	},
}
```

## 参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `layout` | `LuaTable` | 布局表，或可被 `require` 得到的布局表 |
| `env` | `LuaTable` | 可选。绑定 `id` 对应 View 的表，常用 `_G` 或局部 `binding` |
| `params` | `ViewGroup.LayoutParams` 类 | 可选。指定根视图 LayoutParams 类型 |

```lua
local binding = {}
local view = loadlayout(layout, binding)
print(binding.title) -- id = "title" 的 View
```

## 常用属性

| 属性 | 说明 | 示例 |
|------|------|------|
| `id` | 设置 View ID，并写入绑定表 | `id = "button"` |
| `layout_width` / `layout_height` | 宽高 | `"match"`, `"wrap"`, `"120dp"`, `"50%"` |
| `padding` / `paddingLeft` 等 | 内边距 | `"16dp"` |
| `layout_margin` / `layout_marginTop` 等 | 外边距 | `"8dp"` |
| `text` / `hint` / `textSize` | 文本属性 | `text = "OK"`, `textSize = "14sp"` |
| `textStyle` | 文字样式 | `"bold"`, `"italic"`, `"bold|italic"` |
| `background` | 背景颜色、Drawable 或图片路径 | `"#FF0000"`, `drawable`, `"bg.png"` |
| `src` | ImageView 图片源 | Bitmap、Drawable、文件路径、URL |
| `items` | ListView/Spinner 简单字符串列表 | `{ "A", "B" }` |
| `pages` / `pagesWithTitle` | ViewPager 页面 | `{ page1, page2 }` |

尺寸字符串支持 `dp`、`sp`、`px`、`pt`、`in`、`mm`，以及 `%`、`%w`、`%h`。

## 事件监听

所有以 `on` 开头的属性会按监听器处理。属性值可以是函数，也可以是绑定表中的函数名字符串。

```lua
local binding = {
	onButtonClick = function(view)
		print("clicked")
	end,
}

local view = loadlayout({
	Button,
	text = "点击",
	onClick = "onButtonClick",
}, binding)
```

```lua
{
	Button,
	text = "直接函数",
	onClick = function(view)
		print(view)
	end,
}
```

## style / theme 用法

`loadlayout` 会在创建 View 时优先处理构造期样式字段，适合 MaterialButton、MaterialTextView、TextInputLayout、MaterialCardView 等组件。

### 兼容字段

- `style`：旧写法，仍可继续使用；传 `?attr/...` 时会按 `defStyleAttr` 处理，传 `@style/...` 或样式资源 ID 时按旧 style 兼容。
- `theme`：视图创建时使用的主题资源，会包装当前 Context。
- `styleAttr`：构造函数的 `defStyleAttr`，推荐用于 Material 组件的变体样式。
- `styleRes`：构造函数的 `defStyleRes`，可与 `styleAttr` 组合使用。

支持的资源写法：

| 写法 | 说明 |
|------|------|
| `?attr/name` | 当前主题中的属性，例如 `?attr/materialButtonOutlinedStyle` |
| `?android:attr/name` | Android 系统 attr |
| `@attr/name` | 应用 attr 资源 |
| `@style/name` | 应用 style 资源 |
| `@android:style/name` | Android 系统 style |
| 数字资源 ID | 直接使用 `R.attr.xxx` / `R.style.xxx` / `MDC_R.attr.xxx` |

### 示例

旧写法仍然可用：

```lua
import "com.google.android.material.button.MaterialButton"

return {
	MaterialButton,
	text = "轮廓按钮",
	style = "?attr/materialButtonOutlinedStyle",
}
```

推荐写法：显式区分 `styleAttr` 与 `styleRes`。

```lua
import "com.google.android.material.button.MaterialButton"

return {
	MaterialButton,
	text = "轮廓按钮",
	styleAttr = "?attr/materialButtonOutlinedStyle",
}
```

同时指定 theme overlay 与样式：

```lua
import "com.google.android.material.textfield.TextInputLayout"
import "com.google.android.material.textfield.TextInputEditText"

return {
	TextInputLayout,
	layout_width = "match",
	layout_height = "wrap",
	theme = "ThemeOverlay.Material3",
	styleAttr = "?attr/textInputOutlinedStyle",
	{
		TextInputEditText,
		layout_width = "match",
		layout_height = "wrap",
	}
}
```

如果已经拿到资源 ID，优先传数字 ID，可避免运行时字符串查找：

```lua
return {
	MaterialButton,
	text = "高性能写法",
	styleAttr = MDC_R.attr.materialButtonOutlinedStyle,
}
```

### 说明

- `style` 继续兼容旧布局。
- 对 Material 组件，推荐优先使用 `styleAttr` / `styleRes`，必要时再叠加 `theme`。
- 字符串资源引用会被缓存；大量 RecyclerView item 中仍推荐直接使用数字资源 ID。
- 无效资源会在运行时输出更明确的错误提示，方便排查 Lua 布局问题。

## CoordinatorLayout 特殊属性

`loadlayout` 对部分 Material/CoordinatorLayout 布局参数做了特殊处理：

| 属性 | 说明 | 示例 |
|------|------|------|
| `layout_behavior` | 设置 CoordinatorLayout Behavior | `"@string/appbar_scrolling_view_behavior"` |
| `layout_anchor` | 锚定到已定义 id 的 View | `"fab"` |
| `layout_scrollFlags` | AppBar 滚动标志 | `"scroll|enterAlways"` |
| `layout_collapseMode` | CollapsingToolbar 折叠模式 | `"pin"`, `"parallax"` |
| `layout_collapseParallaxMultiplier` | 视差系数 | `0.5` |

相对布局规则也支持字符串 id 引用，例如 `layout_below = "title"`。被引用的 id 需要在当前 View 之前定义。

## 注意事项

- 布局表第一个元素必须是 View 类；如果是 `nil`，通常是忘记 `import` 或类名拼写错误。
- `id` 会生成 Android View ID，并将 View 写入绑定表。
- `style`、`styleAttr`、`styleRes`、`theme` 是构造期字段，不会作为普通属性再次写入 View。
- 普通 Java setter 通常可直接用属性名调用，例如 `alpha = 0.5`、`enabled = false`。
- 子视图会递归调用 `loadlayout` 创建；如果子项是字符串，会先通过 Lua `require` 加载。
