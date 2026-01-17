# NeLuaJ+ 的 `saf` 模块介绍

`saf` 模块是 Android **存储访问框架 (Storage Access Framework, SAF)** 的 Lua 封装。它允许应用获取特定目录的持久化读写权限，解决 Android 10+ 分区存储限制，支持类似文件管理器的目录操作以及系统级文件选择器调用。

---

## 核心特性

*   **权限持久化**: 自动保存用户授权的目录 URI，重启后无需再次授权。
*   **双模式操作**: 支持 **目录树模式 (Tree)**（在授权目录内自由管理文件）和 **选择器模式 (Picker)**（调用系统界面操作单个文件）。
*   **智能识别**: 自动根据文件后缀识别 MIME 类型（如 `.json`, `.png` 等）。

---

## 1. 目录授权与管理

#### **`saf.select(callback)`**
*   **功能**: 调用系统界面，请求用户选择并授权一个文件夹。
*   **参数**:
    *   `callback` (function): 授权完成后的回调。
        *   参数 `uri`: (UserData/String) 成功返回授权目录的 URI，失败返回 `nil`。
*   **说明**: 授权成功后，模块会自动永久保存权限。

#### **`saf.get()`**
*   **功能**: 获取当前已保存并授权的目录 URI。
*   **返回值**: `Uri` 对象或 `nil` (如果尚未授权)。

---

## 2. 目录树操作 (Tree Mode)

此类方法用于在**当前授权的目录**下进行操作。
*前提：必须先通过 `saf.select` 获取权限（`saf.get()` 不为 nil）。若未授权，调用此类方法会自动触发授权流程。*

### 文件读写

#### **`saf.list(callback)`**
*   **功能**: 列出当前授权目录下的所有文件和子文件夹。
*   **参数**:
    *   `callback` (function): 接收文件列表的回调。
        *   参数 `files` (table): 包含文件信息的数组表。
*   **文件信息结构**:
    ```lua
    {
        name = "data.json",
        uri = "content://...",   -- 文件的具体 URI
        mime = "application/json",
        size = 1024,             -- 文件大小 (字节)
        isDirectory = false      -- 是否为文件夹
    }
    ```

#### **`saf.read(filename)`**
*   **功能**: 读取当前授权目录下的指定文件内容。
*   **参数**: `filename` (string) 文件名（不区分大小写）。
*   **返回值**: (String) 文件内容，失败或文件不存在返回 `nil`。

#### **`saf.save(filename, content)`**
*   **功能**: 在当前授权目录下保存文件。
*   **参数**:
    *   `filename` (string): 文件名（自动根据后缀推断 MIME 类型）。
    *   `content` (string): 要写入的内容。
*   **返回值**: `true` 成功，`false` 失败。
*   **逻辑**: 文件存在则覆盖，不存在则创建。

### 文件管理

#### **`saf.exists(filename)`**
*   **功能**: 检查当前目录下指定的文件或文件夹是否存在。
*   **返回值**: `true` 存在，`false` 不存在。

#### **`saf.mkdir(dirname)`**
*   **功能**: 在当前目录下创建一个新文件夹。
*   **返回值**: `true` 成功，`false` 失败（如已存在）。

#### **`saf.delete(filename)`**
*   **功能**: 删除当前目录下指定的文件或文件夹。
*   **返回值**: `true` 成功，`false` 失败。

#### **`saf.rename(oldName, newName)`**
*   **功能**: 重命名当前目录下的文件或文件夹。
*   **返回值**: `true` 成功，`false` 失败。

#### **`saf.type(filename)`**
*   **功能**: 获取资源类型。
*   **返回值**:
    *   `"file"`: 普通文件
    *   `"directory"`: 文件夹
    *   `nil`: 文件不存在或出错

---

## 3. 系统选择器操作 (Picker Mode)

此类方法**不需要**预先授权目录，每次调用都会打开系统的文件选择器或保存界面，对任意位置的文件进行单次操作。

#### **`saf.read(callback)`**
*   **功能**: 打开系统文件选择器（Open Document），读取任意位置的文件。
*   **参数**:
    *   `callback` (function):
        *   参数 `content` (String): 读取到的文件内容。取消或失败返回 `nil`。

#### **`saf.save(filename, content, callback)`**
*   **功能**: 打开系统文件创建界面（Create Document），导出文件到任意位置。
*   **特性**: 自动根据 `filename` 后缀设置 MIME 类型，确保系统能正确识别文件格式（如 JSON, 图片等）。
*   **参数**:
    *   `filename` (string): 预设的文件名。
    *   `content` (string): 要保存的内容。
    *   `callback` (function):
        *   参数 `result` (Boolean): `true` 表示保存成功，`false` 表示失败或取消。