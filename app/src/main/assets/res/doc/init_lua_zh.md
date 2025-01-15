# `init.lua` 配置文件文档

`init.lua` 文件用于配置应用程序的环境参数。它是一个 Lua 脚本，包含多个变量，这些变量控制应用程序的名称、版本、调试模式、主题等设置。建议使用官方打包器生成脚本，避免手动编辑 `init.lua`。

## `init.lua` 的结构

文件应定义变量来配置应用程序的行为。以下是支持的变量说明：

---

## **1. `app_name`**
- **类型**: `string`
- **描述**: 指定应用程序的名称，将作为应用程序窗口标题显示。

### 示例：
```lua
app_name = "示例应用程序"
```

---

## **2. `package_name`**
- **类型**: `string`
- **描述**: 定义应用程序的包名，通常用于标识应用程序的唯一性。请确保包名符合标准命名规则，例如：`com.example.myapp`。

### 示例：
```lua
package_name = "com.example.myapp"
```

---

## **3. `ver_name`**
- **类型**: `string`
- **描述**: 应用程序的版本名称，通常是面向用户显示的版本信息，例如 `1.0.0`。

### 示例：
```lua
ver_name = "1.0.0"
```

---

## **4. `ver_code`**
- **类型**: `integer`
- **描述**: 应用程序的版本号，通常是一个递增的整数，用于标识应用程序的构建版本。

### 示例：
```lua
ver_code = 101
```

---

## **5. `debug_mode`**
- **类型**: `boolean`
- **描述**: 启用或禁用调试模式。如果启用调试模式，应用程序可能会输出更多的调试日志信息以帮助开发者排查问题。

### 示例：
```lua
debug_mode = true
```

---

## **6. `target_sdk`**
- **类型**: `integer`
- **描述**: 指定目标 SDK 版本，表示应用程序在该 SDK 版本下运行时的目标行为。建议与项目的构建配置保持一致。

### 示例：
```lua
target_sdk = 33
```

---

## **7. `min_sdk`**
- **类型**: `integer`
- **描述**: 指定最低 SDK 版本，表示应用程序运行所支持的最低 Android 系统版本。

### 示例：
```lua
min_sdk = 24
```

---

## **8. `NeLuaJ_Theme`**
- **类型**: `string`
- **描述**: 定义应用程序的主题名称，该主题应为 `R.style` 类中已定义的主题字段。

### 示例：
```lua
NeLuaJ_Theme = "Theme_NeLuaJ_Material3"
```

---

## **9. `theme`** *(已弃用)*
- **类型**: `integer` 或 `string`
- **描述**: 配置应用程序的主题。此字段已被标记为弃用，建议改用 `NeLuaJ_Theme`。如果是数字，则直接代表主题资源 ID；如果是字符串，则应与 `android.R.style` 类中的主题字段名称匹配。

### 示例：
```lua
theme = "Theme_Material_Light"
```

---

## **10. `user_permission`**
- **类型**: `table` (数组形式)
- **描述**: 定义应用程序所需的权限列表。这些权限应以字符串形式列出，符合 Android 的权限标准定义。

### 示例：
```lua
user_permission = { "android.permission.INTERNET", "android.permission.CAMERA" }
```

---

## 示例 `init.lua` 文件

以下是一个示例配置文件，展示了如何定义所有支持的变量：

```lua
app_name = "示例应用"
package_name = "com.example.myapp"
ver_name = "1.0.0"
ver_code = 101
debug_mode = true
target_sdk = 33
min_sdk = 24
NeLuaJ_Theme = "Theme_NeLuaJ_Material3"
theme = "Theme_Material_Light" -- 已弃用
user_permission = { "android.permission.INTERNET", "android.permission.CAMERA" }
```

---

## 注意事项
1. **项目目录要求**：请确保 `init.lua` 文件位于项目的根目录中。
2. **语法正确性**：`init.lua` 文件的语法错误可能会导致加载失败。建议在编辑后检查文件语法。
3. **权限配置**：`user_permission` 中的权限应符合 Android 的权限标准，否则可能无法正确请求权限。