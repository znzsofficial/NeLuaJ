# LuaLayout 实现思路与后续方案

## 1. 定位

`LuaLayout` 把 **Lua 布局表** 转成 Android `View` 树，是 AndroLua / NeLuaJ+ 的核心 UI 桥接。

```lua
-- 布局表：第 1 个元素是 View 类，字符串键是属性，数字键是子节点
return {
  LinearLayout,
  orientation = "vertical",
  layout_width = "match",
  layout_height = "match",
  { MaterialTextView, id = "title", text = "Hello", textSize = "16sp" },
}
```

入口：

| 路径 | 说明 |
|------|------|
| `LuaLayout(context).load(table [, env [, LayoutParamsClass]])` | Java/Kotlin 直接调用 |
| `loadlayout(table)` | 注入 Globals 的 `org.luaj.android.loadlayout` |
| `res.layout.xxx` | `res` 模块内部也会 `new LuaLayout` |

公开 API 包名保持 **`com.androlua.LuaLayout`**，实现细节在 **`com.androlua.layout`**。

---

## 2. 整体流程

```
load(layout, env, paramsClass)
  │
  ├─ layout[1] → View 类（必须）
  ├─ LayoutViewFactory.create → 构造 View（含 style/theme）
  ├─ params = LayoutParams(wrap, wrap)  // 默认 WRAP
  │
  ├─ for each key, value in layout:
  │     ├─ key 为 int > 1 → 子 View（或 AdapterView.adapter）
  │     └─ key 为 string → applyAttribute
  │           ├─ 专用键 when（text / padding* 延后 / MDC…）
  │           ├─ layout_* → LayoutParamsApplier
  │           └─ 其它 → 校验 canSet → view[key] = value（JavaInstance）
  │
  ├─ applyMargins(layout, params)
  ├─ view.LayoutParams = params
  └─ applyPadding(layout, hostView)
```

要点：

1. **专用键优先**：复杂语义（尺寸单位、枚举、MDC）不交给反射盲设。
2. **padding / margin 延后统一写**：避免循环中只设一边时把其它边清零。
3. **未知属性报错**：`LayoutReflection.canSetJavaProperty` 拦住拼写错误，避免 `JavaInstance.set` 静默写内部 Map。
4. **错误不中断整表**：单属性 `sendError` 后继续解析其它键（尽量出半残 UI + 日志）。

---

## 3. 模块拆分（当前）

```
com.androlua.LuaLayout.kt          -- 编排 + 专用属性 when
com.androlua.layout/
  LayoutEnums.kt                   -- 枚举分表、sizeTokens、relativeRules
  LayoutValueParser.kt             -- 字符串→尺寸/颜色/枚举/布尔
  LayoutParamsApplier.kt           -- layout_*、margin、padding、behavior
  LayoutViewFactory.kt             -- theme/style 构造 View
  LayoutReflection.kt              -- 属性可写集合、Method 缓存
  LayoutTint.kt                    -- TintColor / iconTint 按控件类型分发
  LayoutSrcLoader.kt               -- src / @drawable / Coil
```

| 模块 | 职责 |
|------|------|
| **Enums** | `gravity` / `inputType` / `imeOptions` / `visibility`… 分表；`match`/`wrap`；RelativeLayout rules |
| **ValueParser** | `"16dp"`、`"?attr/colorPrimary"`、`"#RRGGBB"`、`a\|b` 位或；主题 attr 实例级缓存 |
| **ParamsApplier** | `layout_width/height/weight/gravity`；margin 字段名 `leftMargin`；Start/End；padding 合并 |
| **ViewFactory** | 无 style 快路径；四参构造缓存；`ContextThemeWrapper` 缓存 |
| **Reflection** | 每 Class 扫一次 setXxx/fields；`getMethod` 缓存 |
| **Tint** | ImageView / CompoundButton / ProgressBar / Material* / EditText 背景下划线；`iconTint` 仅图标 |
| **SrcLoader** | `src`：Bitmap/Drawable 同步；`@drawable` / `@android:drawable` / `drawable/`；路径/URL Coil 异步 |
| **TextSupport** | TextView / TIL：`hint` 外层浮动标签、`textColor`/`hintTextColor`、`singleLine` 等；TIL 内层 EditText 代理 |

---

## 4. 关键设计决策

### 4.1 枚举按属性分表

旧实现单一 `toint` HashMap，`inherit`、`none` 等后写覆盖先写。现改为：

```text
toValue(str, attr?) → enumMapForAttr(attr) 优先 → sizeTokens → 尺寸/颜色/数字
```

`gravity = "center|end"` 在 gravity 表内 OR；未知 token `sendMsg` 提示。

### 4.2 layout_* 与 margin 字段名

Android `MarginLayoutParams` 字段是 **`leftMargin`**，不是 `marginLeft`。  
`layout_marginLeft` 在 `applyMargins` 末尾写入 `leftMargin`。  
单边只写出现的边，避免 `setMargins(16,0,0,0)` 清掉其它边。

### 4.3 专用键 vs 反射

| 类型 | 例子 | 原因 |
|------|------|------|
| 必须专用 | `textSize`、`padding*`、`visibility`、`inputType` | 单位/枚举/API 组合 |
| 图片专用 | `src` → `LayoutSrcLoader` | 资源引用 + Coil + 与 `res.drawable` 对齐 |
| MDC 专用 | `radius`、`cardElevation`、`stroke*`、`Checked` | 类型分支 + 正确 API |
| 历史别名 | `TintColor`、`DividerHeight` | 工程存量布局 |
| 通用反射 | `alpha`、`enabled`、多数 setXxx | `view[key]=` → JavaInstance |

`textSize`：裸数字按 **sp→px**；带 `sp`/`dp` 走 `toValue`；调用 `setTextSize(PX, px)`。

### 4.3.1 `src` / `@drawable`（LayoutSrcLoader）

与 **`res.drawable` 解析顺序对齐**（`org.luaj.android.res`）：

```
src 值
  ├─ Bitmap          → jset ImageBitmap
  ├─ Drawable        → ImageView.setImageDrawable / 否则 ImageDrawable
  ├─ 资源引用字符串
  │     "@drawable/name" | "drawable/name" | "@android:drawable/name"
  │       1) R 同步：app 包 name → ic_name；android 包仅 name
  │          ContextCompat.getDrawable + mutate → setImageDrawable
  │       2) 工程 assets 位图（png/jpg/…）→ Coil 异步
  │       3) 工程 res/drawable/name.lua → 同步
  │       4) 失败 → LuaError（不静默）
  └─ 其它 string（路径 / URL）→ Coil 异步
```

要点：

| 项 | 说明 |
|----|------|
| **着色** | `@drawable/…` **不**带颜色；布局另写 `iconTint` / `TintColor`，或改用 `res.drawable(name, color)` |
| **`ic_` 候选** | 与 `res` 相同：`name` 未命中再试 `ic_name`（便于 `save` → `ic_save.xml`） |
| **ImageView** | Drawable 路径一律 `setImageDrawable`，避免 `jset("ImageDrawable")` 属性名歧义 |
| **trim** | 字符串去空白；空串忽略 |
| **缓存** | 工程位图路径 miss 记 `MISS`，避免反复扫盘 |

用户文档：`res/doc/module_loadlayout.html`（src 专节）、`layout_reference.html` §4。

### 4.4 未知属性

`JavaInstance.set` 找不到 setter 时会静默写入内部 Map。  
通用路径在赋值前：

```text
LayoutReflection.canSetJavaProperty(viewClass, key) → 否则 LuaError → sendError
```

例外：`onXxx` 监听器放行（走 setOnXxxListener 约定）。

### 4.5 性能要点

- 无 `theme`/`style*`：直接 `viewClass.call(context)`，不解析资源。
- 四参构造：`getConstructor` 结果按 Class 缓存，无四参的类不反复失败。
- 主题 wrapper：同 resId 复用 `ContextThemeWrapper`。
- 属性可写：每 Class 一次 methods/fields 扫描。
- Method 反射：`ConcurrentHashMap` + `NO_METHOD` 占位；单参 setter 缓存 key 用字符串拼接。
- `?attr`：缓存挂在 **Layout 实例**（随 Activity 主题，不放 companion 全局）。
- **margin/padding**：主循环顺带标记 `needsMargins`/`needsPadding`，无则跳过二次扫表。
- **`getEditText`**：按 Class 缓存 Method。
- **`gravity` 等 `|` 枚举**：手写切分，避免 `split` 中间 List。
- 专用键 `when` 优先：热属性不进 `canSetJavaProperty`。

### 4.6 仍偏贵的路径（预期）

| 路径 | 说明 |
|------|------|
| `layout.next` 全表遍历 | 每控件 O(属性数)；无法避免 |
| 通用属性 `canSet` 首次 | 扫 Class methods 一次后缓存 |
| `view[key]=` / `jcall` | JavaInstance 元表，比直接 Kotlin 调用慢 |
| Adapter 列表项反复 load | 每行重建 View 树；应用层应复用 / 简化 item 表 |
| Coil `src`（路径/URL/工程位图） | 异步解码，不占主线程解析时间 |
| `@drawable` R 命中 | 同步 `getDrawable`，无 Coil |

---

## 5. 与文档 / 工程约定

应用内文档（应与实现同步）：

- `res/doc/layout_style.html` — **style / theme 写法（用户向唯一入口）**
- `res/doc/module_loadlayout.html` — 主文（用法、`src`；style 链到上者）
- `res/doc/layout_reference.html` — 属性速查
- `res/doc/MaterialTextField.html` — 输入框组件 + style 名表
- `res/doc/module_res.html` — `res.drawable` 等
- `res/doc/md3_design.html`、`color_api.html`

布局颜色：优先 `"?attr/color…"`；运行时 int 用 `themeUtil`。  

**style 构造（LayoutViewFactory）** — 与 `layout_style.html` 一致，解析后按序尝试：

| 顺序 | 条件 | 构造 |
|------|------|------|
| 1 | 有 `styleRes` 且类有四参 | `(Context, attrs, styleAttr, styleRes)` |
| 2 | 有 `styleRes`、无四参 | 三参第三参 = `styleRes`（`MaterialTextField` 等） |
| 3 | 有 `styleAttr` | 三参第三参 = `styleAttr` |
| 4 | 回退 | 单参 `(Context)`（可先 `theme` → `ContextThemeWrapper`） |

`style=` 兼容：`?attr`/`@attr` → styleAttr；`@style`/数字 style id → styleRes。  
`theme` 只包装 Context，不作 style overlay。

---

## 6. 已知限制

1. **ConstraintLayout `layout_constraint*`**：未系统支持，落入通用 LP 字段路径，多数会 canSet 失败或无效。  
2. **id 顺序**：`layout_below = "title"` 要求 `title` 已在表中更早出现。  
3. **属性错误不中断**：半残 UI + 日志，调试时需看 log。  
4. **`commonLayoutParamKeys`**：跳过校验的字段若写错仍可能静默。  
5. **Coil `src`（非 R 路径）**：异步回调依赖 `isAttachedToWindow` / `post`，极端时序仍可能丢图；**R 同步路径无此问题**。  
6. **`@drawable` 不着色**：与 `res.drawable(name, color)` 不同；忘记 `iconTint` 时可能像「有热区无色图」（取决于 vector 默认 fill）。  
7. **id**：现用 `View.generateViewId()`，不再使用 `0x7f000000` 手写计数。  
8. **style 与构造签名**：标准 View 四参把 style 放第 4 参；`MaterialTextField` 仅三参且第 3 参为 style 资源 id。工厂按「有无四参」自动分流；Widget style 走 `style`/`styleRes`，主题叠加走 `theme`。
9. **hint（TextInputLayout）**：`LayoutTextSupport.setHint` 写外层浮动标签，并清空内部 EditText.hint，避免双层提示。

---

## 7. 后续可能的修改方案

### 7.1 短期（低风险）

| 项 | 说明 |
|----|------|
| 专用键继续收口 | `tooltipText` / `contentDescription`；更多 Text 属性走 LayoutTextSupport |
| 未知 `\|` flag | 已有 sendMsg；可改为 debug_mode 才提示，或收集到一次汇总 |
| 单测 | `toValue` 分表、`toLayoutSize`、`applyPadding` 单边不互清、MaterialTextField 代理 |

### 7.2 中期

| 项 | 说明 |
|----|------|
| ConstraintLayout | 专用 `layout_constraint*` 映射到 ConstraintSet 或 LayoutParams 字段 |
| 属性 when 再拆 | `LayoutAttributeApplier` 承接 `applyAttribute`，主类只剩 `load` 循环 |
| RecyclerView 项 | 复用同一 `LuaLayout` 实例时注意 id/ids map 是否应 reset 或分作用域 |
| 严格模式 | SharedData / debug_mode 下未知属性改为抛错中断，便于 CI |

### 7.3 长期 / 可选

| 项 | 说明 |
|----|------|
| 编译期布局 | 把布局表预编译为字节码或 View 工厂，减少运行时解析 |
| Compose 桥 | 若产品线扩展，另开桥接层，不硬塞进 LuaLayout |
| 与 LayoutHelper 统一 | 编辑器预览用的 loadlayout 副本与主实现合并，避免双份语义 |

### 7.4 不建议

- 再回到全局单一 `toint` 表。  
- 对未知属性全面静默（已付出成本做报错，勿回退）。  
- 在 companion 全局缓存主题色（多 Activity / 动态色会串）。

---

## 8. 修改时检查清单

- [ ] 专用键是否 `return`/`continue`，避免落入通用赋值  
- [ ] 尺寸是否走 `toLayoutSize` / `toDimensionPx`，勿把 `"16dp"` 当字符串塞进 int 字段  
- [ ] margin/padding 是否只改指定边  
- [ ] 枚举是否进 **对应** 分表  
- [ ] 更新 `res/doc/module_loadlayout.html` / `layout_reference.html`（含 `src` / `@drawable`）  
- [ ] `src` 改动时同步 `LayoutSrcLoader` 与 `res.drawable` 顺序是否仍对齐  
- [ ] 工程内存量布局（`res/layout/*.lua`、`vConsole`）冒烟  

---

## 9. 参考文件

```
app/src/main/java/com/androlua/LuaLayout.kt
app/src/main/java/com/androlua/layout/*.kt
app/src/main/java/org/luaj/android/loadlayout.kt
app/src/main/assets/res/doc/module_loadlayout.html
app/src/main/assets/res/doc/layout_reference.html
```
