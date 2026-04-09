# MaterialTextField

`vinx.material.textfield.MaterialTextField` 是对 `TextInputLayout` + `TextInputEditText` 的封装组件，解决了 LuaLayout 无法正确处理 `TextInputLayout` 嵌套 `TextInputEditText` 的问题。

它会根据传入的 `style` 自动创建对应的内部 EditText，并将 EditText 的常用方法代理到自身，使你可以像操作普通 EditText 一样操作它。

---

## 为什么需要它

在 LuaLayout 中直接使用 `TextInputLayout` 需要手动嵌套 `TextInputEditText` 作为子 View，但 LuaLayout 的属性设置机制会将属性应用到外层 `TextInputLayout` 而非内部 EditText，导致 `text`、`textSize`、`singleLine` 等属性无法正确生效。

`MaterialTextField` 在构造时自动创建并添加内部 EditText，同时将 EditText 相关的属性调用代理到内部 EditText，一行代码即可使用完整的 Material Design 输入框。

---

## 导入

```lua
import "vinx.material.textfield.MaterialTextField"
```

---

## 支持的样式

通过 `style` 属性指定输入框样式，决定外观和内部 EditText 类型：

### 轮廓样式（Outlined）

内部创建 `TextInputEditText`。

| 样式 | 说明 |
|------|------|
| `Widget_Material3_TextInputLayout_OutlinedBox` | MD3 轮廓输入框 |
| `Widget_Material3_TextInputLayout_OutlinedBox_Dense` | MD3 紧凑轮廓输入框 |
| `Widget_MaterialComponents_TextInputLayout_OutlinedBox` | MDC 轮廓输入框 |
| `Widget_MaterialComponents_TextInputLayout_OutlinedBox_Dense` | MDC 紧凑轮廓输入框 |

### 填充样式（Filled）

内部创建 `TextInputEditText`。

| 样式 | 说明 |
|------|------|
| `Widget_Material3_TextInputLayout_FilledBox` | MD3 填充输入框 |
| `Widget_Material3_TextInputLayout_FilledBox_Dense` | MD3 紧凑填充输入框 |
| `Widget_MaterialComponents_TextInputLayout_FilledBox` | MDC 填充输入框 |
| `Widget_MaterialComponents_TextInputLayout_FilledBox_Dense` | MDC 紧凑填充输入框 |

### 下拉菜单样式（ExposedDropdownMenu）

内部创建 `MaterialAutoCompleteTextView`，支持下拉选择。

| 样式 | 说明 |
|------|------|
| `Widget_Material3_TextInputLayout_OutlinedBox_ExposedDropdownMenu` | MD3 轮廓下拉菜单 |
| `Widget_Material3_TextInputLayout_OutlinedBox_Dense_ExposedDropdownMenu` | MD3 紧凑轮廓下拉菜单 |
| `Widget_Material3_TextInputLayout_FilledBox_ExposedDropdownMenu` | MD3 填充下拉菜单 |
| `Widget_Material3_TextInputLayout_FilledBox_Dense_ExposedDropdownMenu` | MD3 紧凑填充下拉菜单 |

### 无样式

不传 `style` 或传入不匹配的值时，`boxBackgroundMode` 为 `NONE`，内部创建 `TextInputEditText`。

---

## 基本用法

### 轮廓输入框

```lua
import "vinx.material.textfield.MaterialTextField"

{
    MaterialTextField,
    layout_width = "fill",
    layout_height = "wrap",
    hint = "用户名",
    singleLine = true,
    textSize = "14sp",
    tintColor = ColorUtil.getColorPrimary(),
    style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
    id = "inputName",
}
```

### 紧凑轮廓输入框

```lua
{
    MaterialTextField,
    layout_width = "fill",
    layout_height = "wrap",
    hint = "搜索",
    singleLine = true,
    textSize = "12sp",
    tintColor = ColorUtil.getColorPrimary(),
    style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox_Dense,
}
```

### 填充输入框

```lua
{
    MaterialTextField,
    layout_width = "fill",
    layout_height = "wrap",
    hint = "密码",
    singleLine = true,
    style = MDC_R.style.Widget_Material3_TextInputLayout_FilledBox,
    tintColor = ColorUtil.getColorPrimary(),
}
```

### 多行输入

```lua
{
    MaterialTextField,
    layout_width = "fill",
    layout_height = "wrap",
    hint = "备注",
    minLines = 3,
    maxLines = 6,
    style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
    tintColor = ColorUtil.getColorPrimary(),
}
```

---

## 对话框中使用

`MaterialTextField` 最常见的场景是在对话框中作为输入框：

```lua
import "vinx.material.textfield.MaterialTextField"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"

local binding = {}
local layout = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    padding = "20dp",
    Focusable = true,
    FocusableInTouchMode = true,
    {
        MaterialTextField,
        layout_width = "fill",
        layout_height = "wrap",
        hint = "请输入文件名",
        singleLine = true,
        textSize = "14sp",
        tintColor = ColorUtil.getColorPrimary(),
        style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
        id = "fileName",
    },
}

MaterialAlertDialogBuilder(activity)
    .setTitle("新建文件")
    .setView(loadlayout(layout, binding))
    .setPositiveButton("确定", function()
        local name = binding.fileName.getText().toString()
        print("输入的文件名: " .. name)
    end)
    .setNegativeButton("取消", nil)
    .show()
```

> **提示**：外层容器建议设置 `Focusable = true` 和 `FocusableInTouchMode = true`，防止输入框自动获取焦点弹出键盘。

---

## 下拉选择菜单

使用 `ExposedDropdownMenu` 样式可以创建下拉选择框：

```lua
import "vinx.material.textfield.MaterialTextField"
import "android.widget.ArrayAdapter"

local binding = {}
local layout = {
    MaterialTextField,
    layout_width = "fill",
    layout_height = "wrap",
    hint = "选择语言",
    style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox_ExposedDropdownMenu,
    tintColor = ColorUtil.getColorPrimary(),
    id = "langSelect",
}

loadlayout(layout, binding)

-- 设置下拉选项
local items = {"Lua", "Java", "Kotlin", "Python"}
local adapter = ArrayAdapter(activity, android.R.layout.simple_dropdown_item_1line, items)
binding.langSelect.setAdapter(adapter)
```

---

## 常用属性

### 外观属性（TextInputLayout）

这些属性直接作用于外层 `TextInputLayout`：

| 属性 | 类型 | 说明 |
|------|------|------|
| `style` | int | 输入框样式，决定外观和内部 EditText 类型 |
| `hint` | string | 浮动提示文字 |
| `helperText` | string | 底部辅助文字 |
| `helperTextEnabled` | boolean | 是否启用辅助文字 |
| `counterEnabled` | boolean | 是否启用字符计数 |
| `counterMaxLength` | int | 最大字符数 |
| `errorEnabled` | boolean | 是否启用错误提示 |
| `startIconDrawable` | Drawable | 起始图标 |
| `endIconMode` | int | 末尾图标模式 |
| `boxStrokeColor` | int | 边框颜色 |
| `boxCornerRadii` | — | 通过 `setBoxCornerRadii()` 设置 |

### 代理属性（转发到内部 EditText）

这些属性通过 `MaterialTextField` 的代理方法转发到内部 EditText：

| 属性 | 类型 | 说明 |
|------|------|------|
| `text` | CharSequence | 输入框文本内容 |
| `textSize` | string/float | 文字大小 |
| `textColor` | int | 文字颜色 |
| `singleLine` | boolean | 是否单行 |
| `maxLines` | int | 最大行数 |
| `minLines` | int | 最小行数 |
| `inputType` | int | 输入类型 |
| `imeOptions` | int | IME 选项 |
| `filters` | InputFilter[] | 输入过滤器 |
| `movementMethod` | MovementMethod | 光标移动方式 |

### 特有属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `tintColor` | int (颜色值) | 一键设置主题色：边框色、提示文字色、光标色、选择手柄色、高亮色 |

---

## tintColor 详解

`setTintColor(color)` 是 `MaterialTextField` 的特有方法，一次调用设置所有交互色：

- `boxStrokeColor` — 边框/下划线颜色
- `hintTextColor` — 浮动提示文字颜色
- `highlightColor` — 文本选中高亮色（30% 透明度）
- `textCursorDrawable` — 光标颜色（API 29+）
- `textSelectHandle` / `textSelectHandleLeft` / `textSelectHandleRight` — 选择手柄颜色（API 29+）

```lua
-- 使用 MD3 主题色
field.tintColor = ColorUtil.getColorPrimary()

-- 使用自定义颜色
field.tintColor = 0xFF6200EE
```

---

## 获取/设置文本

```lua
-- 设置文本
binding.inputField.setText("Hello")

-- 获取文本（返回 Editable）
local text = binding.inputField.getText().toString()

-- 获取纯文本长度
local len = binding.inputField.length()

-- 追加文本
binding.inputField.append(" World")

-- 全选
binding.inputField.selectAll()

-- 设置选区
binding.inputField.setSelection(0, 5)
```

---

## TextInputLayout 原生方法

`MaterialTextField` 继承自 `TextInputLayout`，以下方法可直接调用：

```lua
-- 设置/获取错误信息
field.setError("不能为空")
field.setErrorEnabled(true)

-- 辅助文字
field.setHelperText("至少 6 个字符")
field.setHelperTextEnabled(true)

-- 字符计数
field.setCounterEnabled(true)
field.setCounterMaxLength(20)

-- 密码可见性切换
field.setEndIconMode(TextInputLayout.END_ICON_PASSWORD_TOGGLE)

-- 清除按钮
field.setEndIconMode(TextInputLayout.END_ICON_CLEAR_TEXT)

-- 自定义末尾图标
field.setEndIconDrawable(res.drawable.icon_name)
field.setEndIconOnClickListener(function()
    print("点击了末尾图标")
end)

-- 设置圆角
field.setBoxCornerRadii(dp(12), dp(12), dp(12), dp(12))
```

---

## 完整示例：登录表单

```lua
import "vinx.material.textfield.MaterialTextField"
import "com.google.android.material.button.MaterialButton"
import "com.google.android.material.textfield.TextInputLayout"

local ColorUtil = this.themeUtil
local primary = ColorUtil.getColorPrimary()

local binding = {}
activity.setContentView(loadlayout({
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
    padding = "24dp",
    gravity = "center",
    {
        MaterialTextField,
        layout_width = "fill",
        layout_height = "wrap",
        hint = "邮箱",
        singleLine = true,
        inputType = 0x21, -- textEmailAddress
        tintColor = primary,
        style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
        startIconDrawable = res.drawable.email,
        id = "email",
    },
    {
        MaterialTextField,
        layout_width = "fill",
        layout_height = "wrap",
        layout_marginTop = "16dp",
        hint = "密码",
        singleLine = true,
        inputType = 0x81, -- textPassword
        tintColor = primary,
        style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
        endIconMode = TextInputLayout.END_ICON_PASSWORD_TOGGLE,
        id = "password",
    },
    {
        MaterialButton,
        layout_width = "fill",
        layout_height = "wrap",
        layout_marginTop = "24dp",
        text = "登录",
        onClick = function()
            local email = binding.email.getText().toString()
            local pwd = binding.password.getText().toString()
            if #email == 0 then
                binding.email.setError("请输入邮箱")
            elseif #pwd == 0 then
                binding.password.setError("请输入密码")
            else
                print("登录: " .. email)
            end
        end,
    },
}, binding))
```

---

## 与原生写法对比

### 原生写法（LuaLayout 中不可用）

```lua
-- ❌ LuaLayout 无法正确处理嵌套关系
-- text/textSize 等属性会被设置到 TextInputLayout 而非 EditText
{
    TextInputLayout,
    hint = "用户名",
    {
        TextInputEditText,
        text = "Hello",     -- 不会生效
        textSize = "14sp",  -- 不会生效
    },
}
```

### MaterialTextField 写法

```lua
-- ✅ 属性自动代理到内部 EditText
{
    MaterialTextField,
    hint = "用户名",
    text = "Hello",         -- 正确设置到 EditText
    textSize = "14sp",      -- 正确设置到 EditText
    singleLine = true,      -- 正确设置到 EditText
    tintColor = primary,    -- 一键设置主题色
    style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
}
```
