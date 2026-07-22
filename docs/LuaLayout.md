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
com.androlua.LuaLayout.kt          -- 编排 + 专用属性 when（~650 行）
com.androlua.layout/
  LayoutEnums.kt                   -- 枚举分表、sizeTokens、relativeRules
  LayoutValueParser.kt             -- 字符串→尺寸/颜色/枚举/布尔
  LayoutParamsApplier.kt           -- layout_*、margin、padding、behavior
  LayoutViewFactory.kt             -- theme/style 构造 View
  LayoutReflection.kt              -- 属性可写集合、Method 缓存
  LayoutTint.kt                    -- TintColor 按控件类型分发
```

| 模块 | 职责 |
|------|------|
| **Enums** | `gravity` / `inputType` / `imeOptions` / `visibility`… 分表；`match`/`wrap`；RelativeLayout rules |
| **ValueParser** | `"16dp"`、`"?attr/colorPrimary"`、`"#RRGGBB"`、`a\|b` 位或；主题 attr 实例级缓存 |
| **ParamsApplier** | `layout_width/height/weight/gravity`；margin 字段名 `leftMargin`；Start/End；padding 合并 |
| **ViewFactory** | 无 style 快路径；四参构造缓存；`ContextThemeWrapper` 缓存 |
| **Reflection** | 每 Class 扫一次 setXxx/fields；`getMethod` 缓存 |
| **Tint** | ImageView / CompoundButton / ProgressBar / Material* / EditText 背景下划线 |

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
| MDC 专用 | `radius`、`cardElevation`、`stroke*`、`Checked` | 类型分支 + 正确 API |
| 历史别名 | `TintColor`、`DividerHeight` | 工程存量布局 |
| 通用反射 | `alpha`、`enabled`、多数 setXxx | `view[key]=` → JavaInstance |

`textSize`：裸数字按 **sp→px**；带 `sp`/`dp` 走 `toValue`；调用 `setTextSize(PX, px)`。

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
| Coil `src` | 异步解码，不占主线程解析时间 |

---

## 5. 与文档 / 工程约定

应用内文档（应与实现同步）：

- `res/doc/module_loadlayout.html`
- `res/doc/layout_reference.html`
- `res/doc/md3_design.html`、`color_api.html`

布局颜色：优先 `"?attr/color…"`；运行时 int 用 `themeUtil`。  
MaterialButton style 在 loadlayout 上支持有限，工程里常用 **BackgroundTintList / 事后 setTint**。

---

## 6. 已知限制

1. **ConstraintLayout `layout_constraint*`**：未系统支持，落入通用 LP 字段路径，多数会 canSet 失败或无效。  
2. **id 顺序**：`layout_below = "title"` 要求 `title` 已在表中更早出现。  
3. **属性错误不中断**：半残 UI + 日志，调试时需看 log。  
4. **`commonLayoutParamKeys`**：跳过校验的字段若写错仍可能静默。  
5. **Coil `src`**：异步回调依赖 `isAttachedToWindow`，极端时序仍可能丢图。  
6. **id**：现用 `View.generateViewId()`，不再使用 `0x7f000000` 手写计数。

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
- [ ] 更新 `res/doc/module_loadlayout.html` / `layout_reference.html`  
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
