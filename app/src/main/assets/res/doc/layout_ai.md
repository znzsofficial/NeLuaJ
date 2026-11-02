# LuaLayout 编写与 AI 检查规范

## 原生布局表不变

布局表第一个数组元素是导入的 View 类，字符串键是属性，后续数组元素是子节点。
不把 CSS、XML 属性名或其他 AndroLua 版本的扩展直接搬过来。

```lua
import "android.widget.LinearLayout"
import "com.google.android.material.textview.MaterialTextView"

local views = {}
local root = loadlayout({
  LinearLayout,
  orientation = "vertical",
  layout_width = "match",
  layout_height = "wrap",
  padding = "16dp",
  {
    MaterialTextView,
    id = "title",
    layout_width = "match",
    layout_height = "wrap",
    text = "Hello",
    textSize = "16sp",
    textColor = "?attr/colorOnSurface",
  },
}, views)
views.title.setText("Ready") -- Java 成员用点调用；绑定保存在局部表，不污染全局。
```

## 生成代码的约定

- 普通尺寸显式写 `dp`，字号显式写 `sp`；裸数字并不统一表示 dp。大多数尺寸按 px，`textSize` 按 sp。`0dp`、weight、alpha 等无须人为加错误单位。
- 显式声明宽高。`match` / `wrap` 可用；省略时默认为 wrap。
- `gravity` 调整控件内容，`layout_gravity` 调整自己在父容器中的位置；能否使用取决于具体控件/父容器。
- `layout_*` 属于父容器的 LayoutParams。不要给 FrameLayout 下的孩子写 `layout_weight`；LinearLayout 按比例分配时常用分配轴尺寸 `0dp` 配合 weight。
- 使用唯一、稳定的 id 与局部 `views` 表。当前加载器仍有引用顺序限制，`layout_below` / `layout_anchor` 目标应先声明。检查器不改变运行语义。
- 事件优先在加载后绑定，避免初始化属性触发业务逻辑；使用实际支持的监听器名称。
- 使用规范小写开头属性，如 `textColor`、`checked`；历史别名继续兼容，但新代码不混用。
- 图片优先复用现有资源。`src="@drawable/save"` 不会自动着色；按控件使用 `iconTint`。
- `style`、`styleAttr`、`styleRes` 与 `theme` 不是同一概念，查阅 `res/doc/layout_style.html`。
- ScrollView 只放一个直接子容器；AdapterView 的子表是模板，不是普通 ViewGroup 子节点。

## 内置 Agent 工具

`layout_describe({widget="MaterialButton", parent="LinearLayout"})` 查询当前安装版本的属性契约：类型、单位、枚举、别名、适用控件、父容器条件、反射能力和事件。这里是工具参数示意，不是 Lua 全局函数。它只反射内置白名单类，不初始化类，不创建 View；自定义类/别名不会被擅自加载。反射属性只代表 setter/field 存在，不代表已知单位和合法值。

`layout_check({path="res/layout/main.lua", parent="FrameLayout"})` 读取最多 128 KiB UTF-8 源码，先用实际 LuaJ++ 编译器做语法预检，再用受限词法/字面量表分析检查布局。不会执行 Lua、require、import、构造器或 setter，不访问引用中的网络资源。

返回 JSON 字段包括 `hasErrors`、`complete`、`nodesChecked`、`errors`、`unknowns`、`truncated`、`diagnostics`。诊断有 code、severity、file、line/column（可确定时）、nodePath、id（可确定时）、property、actual、suggestion。

- error：可确定的问题，例如属性拼写、已知父容器不匹配、无效枚举、重复 id。
- warning：需要注意，例如隐式单位、当前加载器的前向引用。
- unknown：不能在不执行源码的前提下确定，例如自定义控件、变量值、动态孩子、require 子布局、适配器模板或未描述的反射属性。

第一版识别 return 字面量表与 `loadlayout` 内联表，不做变量传播、控制流推演或完整 AST 分析。类名按白名单惯例识别，无法证明源码没有重定义同名类/函数。返回的非布局数据表也可能被标为 unknown。动态表达式中的其他布局调用不保证逐一发现。

`hasErrors=false` 不等于完整验证；`complete=false` 明确表示有未验证项。即使 complete=true，也只表示本次有限静态规则检查完成，不保证资源、构造器、监听器、生命周期、交互和视觉正确。检查器对根节点的实际父容器不了解时，应传入 parent；多个独立布局候选分别检查绑定，不做跨候选 id 共享。

推荐流程：查询相关控件契约 → 最小修改原生源码 → layout_check → 根据节点位置修复 → 用户授权后运行工程并真机验证。不要执行布局表再重新序列化来改代码，这会丢注释、函数和表达式。
