# NeLuaJ+ 的 `saf` 模块介绍

`saf` 模块是 Android **存储访问框架 (Storage Access Framework, SAF)** 的 Lua 封装。它旨在解决 Android 10+ 分区存储（Scoped Storage）带来的文件读写限制，允许应用方便地获取特定目录的持久化读写权限，或调用系统文件选择器进行单次文件操作。

---

## 核心特性

*   **权限持久化**: 自动保存用户授权的目录 URI，应用重启后无需再次授权即可直接读写。
*   **双模式操作**: 支持 **目录树模式 (Tree)**（在授权目录内自由读写）和 **选择器模式 (Picker)**（调用系统界面读写单个文件）。
*   **原生集成**: 基于 `ActivityResultLauncher`，符合 Android 最新开发规范。

---

## 功能详解

### **1. 目录授权与管理**

#### **`saf.select(callback)`**
*   **功能**: 调用系统界面，请求用户选择并授权一个文件夹。
*   **参数**:
    *   `callback` (function): 授权完成后的回调。
        *   参数 `uri`: (UserData/String) 成功返回授权目录的 URI，取消或失败返回 `nil`。
*   **自动逻辑**: 授权成功后，模块会自动调用 `takePersistableUriPermission` 并将 URI 保存到本地配置中。

#### **`saf.get()`**
*   **功能**: 获取当前已保存并授权的目录 URI。
*   **返回值**: `Uri` 对象或 `nil` (如果尚未授权)。

---

### **2. 目录树操作 (Tree Mode)**

此类方法**必须**在 `saf.get()` 返回有效 URI（即已授权）的情况下使用。如果没有授权，调用这些方法会自动触发 `select` 流程。

#### **`saf.list(callback)`**
*   **功能**: 列出当前授权目录下的所有文件和子文件夹。
*   **参数**:
    *   `callback` (function): 接收文件列表的回调。
        *   参数 `files` (table): 一个包含文件信息的数组表。
*   **文件信息结构**:
    ```lua
    {
        name = "文件名.txt",
        uri = "content://...",   -- 文件的具体 URI
        mime = "text/plain",     -- MIME 类型
        size = 1024,             -- 文件大小 (字节)
        isDirectory = false      -- 是否为文件夹 (boolean)
    }
    ```

#### **`saf.read(filename)`**
*   **功能**: 读取当前授权目录下的指定文件内容。
*   **参数**:
    *   `filename` (string): 目标文件名（需包含后缀）。
*   **返回值**:
    *   (String): 文件内容。
    *   `nil`: 如果文件不存在或读取失败。
*   **注意**: 它是通过遍历目录查找显示名称来实现的，不区分大小写。

#### **`saf.save(filename, content)`**
*   **功能**: 在当前授权目录下保存文件。如果文件存在则覆盖，不存在则创建。
*   **参数**:
    *   `filename` (string): 文件名。
    *   `content` (string): 要写入的内容。
*   **返回值**:
    *   `true`: 保存成功。
    *   `false`: 保存失败。

---

### **3. 系统选择器操作 (Picker Mode)**

此类方法不需要预先授权目录，每次调用都会打开系统文件选择器或保存界面。

#### **`saf.read(callback)`**
*   **功能**: 打开系统文件选择器（Open Document），允许用户选择任意位置的一个文件进行读取。
*   **参数**:
    *   `callback` (function): 读取完成的回调。
        *   参数 `content` (string): 文件内容。如果是 `nil` 表示用户取消或读取失败。

#### **`saf.save(filename, content, callback)`**
*   **功能**: 打开系统文件创建界面（Create Document），允许用户选择任意位置导出文件。
*   **参数**:
    *   `filename` (string): 预设的文件名。
    *   `content` (string): 要保存的内容。
    *   `callback` (function): 保存完成的回调。
        *   参数 `result` (boolean): `true` 表示成功，`false` 表示失败或取消。
