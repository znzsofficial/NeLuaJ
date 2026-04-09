# 便捷 API 参考

NeLuaJ+ 提供了丰富的工具类和模块，简化常见开发任务。

---

## 1. LuaFileUtil — 文件操作

```lua
local LuaFileUtil = luajava.bindClass "com.nekolaska.io.LuaFileUtil".INSTANCE
```

| 方法 | 说明 | 示例 |
|------|------|------|
| `create(path, content)` | 创建文件 | `LuaFileUtil.create("test.txt", "hello")` |
| `write(path, content)` | 写入文件 | `LuaFileUtil.write("test.txt", "world")` |
| `read(path)` | 读取文件 | `local s = LuaFileUtil.read("test.txt")` |
| `remove(path)` | 删除文件 | `LuaFileUtil.remove("test.txt")` |
| `rename(old, new)` | 重命名 | `LuaFileUtil.rename("a.txt", "b.txt")` |
| `checkDirectory(path)` | 确保目录存在 | `LuaFileUtil.checkDirectory("output/")` |
| `isEmpty(path)` | 目录是否为空 | `LuaFileUtil.isEmpty("dir/")` |
| `moveDirectory(src, dest)` | 移动目录 | `LuaFileUtil.moveDirectory("a/", "b/")` |
| `loadLua(path)` | 加载 Lua 文件为表 | `local t = LuaFileUtil.loadLua("config.lua")` |

### 压缩/解压

```lua
-- 解压 ZIP（带进度回调）
LuaFileUtil.extract(File(zipPath), File(outDir), function(progress)
    print("进度:", progress)
end)

-- 压缩文件夹
LuaFileUtil.compress(srcFolder, destZip, fileName)
```

---

## 2. json — JSON 模块

```lua
-- 编码
local str = json.encode({ name = "test", value = 123 })

-- 解码
local obj = json.decode('{"name":"test","value":123}')
print(obj.name)  -- "test"
```

---

## 3. file — 文件模块

```lua
-- 读写
file.write("test.txt", "内容")
local content = file.read("test.txt")

-- 目录操作
file.mkdir("newdir")
file.list(".")  -- 列出文件
```

---

## 4. res — 资源模块

```lua
-- 字符串资源（自动根据语言选择）
local title = res.string.app_title

-- 布局资源
local layout = res.layout.main

-- 当前语言
local lang = res.language  -- "zh", "en", "ja" 等
```

---

## 5. okhttp / Http — 网络模块

### 同步请求

```lua
-- GET
local body = okhttp.get("https://api.example.com/data")

-- POST
local body = okhttp.post("https://api.example.com/data", "key=value")
```

### 异步请求

```lua
-- 使用全局 okHttp 对象
okHttp.get("https://api.example.com/data", function(code, body)
    print("状态码:", code)
    print("响应:", body)
end)

okHttp.post("https://api.example.com/data", "key=value", function(code, body)
end)

-- 使用 Http 类
Http.get("https://api.example.com/data", function(code, body)
end)
```

---

## 6. xTask — 协程异步任务

```lua
-- 在后台线程执行，结果回到主线程
xTask(function()
    -- 后台线程（可执行耗时操作）
    local data = okhttp.get("https://api.example.com/data")
    return json.decode(data)
end, function(result)
    -- 主线程回调
    print("结果:", result.name)
end)
```

---

## 7. task — 异步任务

```lua
-- 基本用法
task(function()
    return "后台结果"
end, function(result)
    print(result)
end)
```

---

## 8. thread — 线程

```lua
-- 在新线程中执行
thread(function()
    -- 耗时操作
    local data = okhttp.get(url)
    -- 注意：不能直接更新 UI
    -- 需要用 activity.runOnUiThread 或 call
end)
```

---

## 9. timer — 定时器

```lua
-- 创建定时器（毫秒）
local t = timer(function()
    print("每秒执行")
end, 0, 1000)  -- 延迟0ms，间隔1000ms

-- 停止定时器
t.stop()

-- 启用/禁用
t.setEnabled(false)
```

---

## 10. lazy — 懒加载

```lua
-- 延迟初始化，首次访问时才执行
local heavyObject = lazy(function()
    return createExpensiveObject()
end)

-- 使用时自动初始化
print(heavyObject.value.someMethod())
```

---

## 11. saf — 存储访问框架

```lua
-- 选择文件
saf.openDocument(function(uri)
    local content = saf.readText(uri)
    print(content)
end)

-- 创建文件
saf.createDocument("test.txt", "text/plain", function(uri)
    saf.writeText(uri, "内容")
end)

-- 选择目录
saf.openDocumentTree(function(uri)
    local files = saf.listFiles(uri)
end)
```

---

## 12. loadlayout — 布局加载

```lua
-- 基本用法
local view = loadlayout(layoutTable)

-- 带绑定表（通过 id 自动绑定到表中）
local binding = {}
local view = loadlayout(layoutTable, binding)
-- 之后可通过 binding.viewId 访问视图

-- 加载资源布局
local view = loadlayout(res.layout.main)
```

---

## 13. print / printf — 打印

```lua
-- 打印到日志（会显示 Toast）
print("Hello", "World")

-- 格式化打印
printf("名字: %s, 年龄: %d", "张三", 25)
```

---

## 14. import — 导入

```lua
-- 导入 Java 类
import "android.widget.TextView"

-- 批量导入
import "android.widget.*", "android.view.*"

-- 导入后可直接使用类名
local tv = TextView(activity)

-- 导入 Lua 模块
local MyModule = require "mods.MyModule"
```

---

## 15. luajava — Java 互操作

```lua
-- 绑定 Java 类
local File = luajava.bindClass "java.io.File"
local f = File("/sdcard/test.txt")

-- 创建实例
local list = luajava.newInstance("java.util.ArrayList")

-- Java 数组转 Lua 表
local luaTable = luajava.astable(javaList)

-- 实现 Java 接口
local runnable = luajava.createProxy("java.lang.Runnable", {
    run = function()
        print("running")
    end
})
```

---

## 16. MaterialAlertDialogBuilder — 对话框

```lua
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"

-- 基本对话框
MaterialAlertDialogBuilder(activity)
    .setTitle("标题")
    .setMessage("内容")
    .setPositiveButton("确定", function()
        print("点击了确定")
    end)
    .setNegativeButton("取消", nil)
    .show()

-- 列表对话框
MaterialAlertDialogBuilder(activity)
    .setTitle("选择")
    .setItems({ "选项1", "选项2", "选项3" }, function(dialog, which)
        print("选择了:", which)
    end)
    .show()

-- 自定义视图对话框
local binding = {}
MaterialAlertDialogBuilder(activity)
    .setTitle("输入")
    .setView(loadlayout(inputLayout, binding))
    .setPositiveButton("确定", function()
        print(binding.editText.getText())
    end)
    .show()
```

---

## 17. BottomSheetDialog — 底部弹出

```lua
import "com.google.android.material.bottomsheet.BottomSheetDialog"

local dialog = BottomSheetDialog(activity)
dialog.setContentView(loadlayout(sheetLayout))
dialog.dismissWithAnimation = true
dialog.show()
```

---

## 18. Snackbar — 底部提示

```lua
import "com.google.android.material.snackbar.Snackbar"

Snackbar.make(rootView, "操作成功", Snackbar.LENGTH_SHORT)
    .setAction("撤销", function()
        print("撤销")
    end)
    .show()
```
