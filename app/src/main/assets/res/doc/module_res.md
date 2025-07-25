# NeLuaJ+ 的 `res` 模块介绍

`NeLuaJ+` 对 `LuaJ++` 的 `res` 模块进行了显著的增强和现代化改造，提供了类似原生 Android 资源系统的强大功能，并深度集成了多语言支持、暗黑模式、屏幕方向适配等高级特性。

---

## 功能概览

### **1. `res.string` (字符串资源)**
- **主要功能**: 管理多语言字符串资源，支持复杂的语言回退机制。
- **文件结构**:
    - `res/string/init.lua`: (可选) 存放所有语言通用的字符串。
    - `res/string/zh-rCN.lua`: (示例) 简体中文（中国）的特定字符串。
    - `res/string/zh.lua`: (示例) 所有中文地区的通用回退字符串。
    - `res/string/en.lua`: (示例) 英文的字符串。
    - `res/string/default.lua`: **必须**，用于指定当设备语言没有对应资源时的默认语言。返回一个字符串，如 `"en"`。
- **加载逻辑**:
    1.  加载 `init.lua`。
    2.  根据设备当前 `Locale`，按以下优先级尝试加载语言文件：
        - **最具体**: `语言-r国家/地区` (如 `zh-rCN`)
        - **次具体**: `语言` (如 `zh`)
        - **默认**: 由 `default.lua` 中指定的语言 (如 `en`)
    3.  一旦找到并加载成功，后续的回退步骤将被跳过。

---

### **2. `res.color` (颜色资源)**
- **主要功能**: 根据系统主题（白天/夜间模式）提供不同的颜色值。
- **文件结构**:
    - `res/color/init.lua`: (可选) 存放通用颜色值。
    - `res/color/day.lua`: 用于白天模式的颜色。
    - `res/color/night.lua`: 用于夜间（暗黑）模式的颜色。
- **加载逻辑**:
    1.  加载 `init.lua`。
    2.  判断当前系统是否为夜间模式，自动加载 `night.lua` 或 `day.lua` 来覆盖或补充颜色值。

---

### **3. `res.dimen` (尺寸资源)**
- **主要功能**: 根据屏幕方向提供不同的尺寸值（如 dp, sp）。
- **文件结构**:
    - `res/dimen/init.lua`: (可选) 存放通用尺寸值。
    - `res/dimen/port.lua`: 用于竖屏 (`portrait`) 模式。
    - `res/dimen/land.lua`: 用于横屏 (`landscape`) 模式。
    - `res/dimen/undefined.lua`: (可选) 用于未定义方向。
- **加载逻辑**:
    1.  加载 `init.lua`。
    2.  根据当前屏幕方向，自动加载对应的尺寸文件。

---

### **4. `res.drawable` 和 `res.bitmap` (图像资源)**
- **主要功能**:
    - 从 `res/drawable/` 目录中加载图片资源。
    - `res.drawable`: 返回一个可以在视图中直接使用的 `Drawable` 对象。
    - `res.bitmap`: 返回一个 `Bitmap` 对象，用于更底层的图像操作。
- **支持的图片格式**:
    - `png`, `jpg`, `gif`, `webp`, `jpeg`, `svg`, `bmp`, `heif`, `heic`, `avif`
- **动态资源**:
    - 如果存在同名的 `.lua` 文件（如 `my_icon.lua`），则会执行该脚本并返回其结果，可以用于创建动态的 `Drawable`（例如 `ShapeDrawable`）。
- **性能**:
    - 内部实现了缓存机制，避免重复加载同一资源，提升性能。

---

### **5. `res.font` (字体资源)**
- **主要功能**: 从 `res/font/` 目录加载自定义字体，实现了缓存机制。
- **支持的字体格式**: `ttf`, `otf`。
- **返回值**:
    - 一个 `Typeface` 对象，可用于设置 `TextView` 等组件的字体。

---

### **6. `res.layout` (布局资源)**
- **主要功能**: 加载在 `.lua` 文件中定义的布局。
- **返回值**:
    - 返回一个描述布局结构的 Lua `table`。这个 `table` 可以被传递给 `loadlayout` 或其他视图构造函数。

---

### **7. `res.view` (视图资源)**
- **主要功能**: 直接加载一个布局文件并返回渲染后的视图对象。
- **返回值**:
    - 一个加载并解析完成的 Android 视图对象（通常是 `ViewGroup` 或 `View`），可以直接添加到界面上。
    - 相当于 `loadlayout(res.layout.xxx)` 的快捷方式。

---

### **8. `res.raw` (原始资源)**
- **主要功能**: 访问 `res/raw/` 目录下的任意原始文件，文件名大小写敏感，但访问时可以忽略扩展名。
- **用法**:
    - `res.raw.my_data`: 会自动查找 `my_data.json`, `my_data.txt` 等文件，并返回第一个匹配项的 Java `File` 对象。
    - `res.raw()` (作为函数调用): `res.raw("my_data")` 会直接将文件内容作为字符串返回（默认UTF-8编码）。
- **返回值**:
    - 通过属性访问 (`.`)：返回 `java.io.File` 对象。
    - 通过函数调用 (`()`): 返回文件内容的字符串。

---

### **9. `res.language` (当前语言)**
- **主要功能**: 获取当前 `res.string` 实际加载并使用的语言标签。
- **返回值**:
    - 一个字符串，例如 `"zh-rCN"`, `"zh"`, 或 `"en"`，反映了资源回退后的最终结果。这对于调试或在应用内显示当前语言非常有用。

---
