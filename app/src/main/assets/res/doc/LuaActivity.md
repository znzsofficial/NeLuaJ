# LuaActivity 完整文档

`LuaActivity` 是 NeLuaJ+ 的核心宿主 Activity，继承自 `AppCompatActivity`。所有 Lua 脚本都运行在它的上下文中。

全局变量 `this` 和 `activity` 都指向当前 `LuaActivity` 实例。

---

## 1. 生命周期回调

在 Lua 脚本中定义以下函数，Activity 会在对应时机自动调用：

```lua
function onCreate()     end  -- Activity 创建完成，布局已加载
function onStart()      end  -- Activity 可见
function onResume()     end  -- Activity 获得焦点
function onPause()      end  -- Activity 失去焦点
function onStop()       end  -- Activity 不可见
function onDestroy()    end  -- Activity 销毁
```

---

## 2. 事件回调

### 按键与触摸

```lua
-- 返回 true 可拦截事件
function onKeyDown(keyCode, event)      end
function onKeyUp(keyCode, event)        end
function onKeyLongPress(keyCode, event) end
function onKeyShortcut(keyCode, event)  end
function onTouchEvent(event)            end
```

### 菜单

```lua
function onCreateOptionsMenu(menu)
    menu.add("菜单项").setShowAsAction(1)
end

function onOptionsItemSelected(item)
    if item.getItemId() == android.R.id.home then
        activity.finish()
    end
end

function onCreateContextMenu(contextMenu, view, contextMenuInfo) end
function onContextItemSelected(item) end
```

### Activity 结果

```lua
-- 方式一：命名结果（推荐）
this.newActivity(1, "other.lua", { "参数" })
function onResult(name, ...)
    print("返回自:", name)
end

-- 方式二：原始回调
function onActivityResult(requestCode, resultCode, data) end
```

### 错误处理

```lua
--[[
  报错时调用，返回值控制输出方式：
  "trace"   — 完整堆栈
  "log"     — 仅日志
  "message" — 仅消息
  "title"   — 仅标题
  返回其他非空值可拦截默认报错
]]
function onError(error, message)
    print(error, message)
    return true
end
```

### 其他回调

```lua
function onVersionChanged(newVersion, oldVersion) end  -- 应用版本变化
function onNightModeChanged(mode)                 end  -- 深色模式切换
function onStorageRequestResult(isGranted)        end  -- 存储权限结果
function onConfigurationChanged(newConfig)        end  -- 屏幕旋转等
function onContentChanged()                       end  -- 内容视图变化
function onReceive(context, intent)               end  -- 广播接收
function onServiceConnected(componentName, service) end
function onServiceDisconnected(componentName)       end
```

---

## 3. 视图与布局

```lua
-- 用 Lua 布局表设置内容视图（等同于 setContentView(loadlayout(table))）
this.setContentView({
    LinearLayout,
    orientation = "vertical",
    { TextView, text = "Hello" }
})

-- 用布局表 + 自定义环境
this.setContentView(layoutTable, envTable)

-- 设置 Fragment 为内容
this.setFragment(fragment)

-- 获取视图
this.getRootView()   -- 返回根 ViewGroup
this.getDecorView()  -- 返回 DecorView
```

---

## 4. Activity 导航

```lua
-- 基本启动
this.newActivity("other.lua")
this.newActivity("other.lua", { "参数1", "参数2" })

-- 带请求码（用于 onResult 回调）
this.newActivity(1, "other.lua", { "参数" })

-- 带转场动画
this.newActivity("other.lua", android.R.anim.fade_in, android.R.anim.fade_out)

-- 多文档模式（独立任务栈）
this.newActivity("other.lua", true)

-- 返回结果给调用者
this.result({ "返回数据" })

-- 结束 Activity
this.finish()
this.finish(true)  -- 同时结束任务栈
```

---

## 5. 图片加载 (Coil)

```lua
-- 异步加载 Bitmap
this.loadBitmap("https://example.com/image.png", function(bitmap)
    imageView.setImageBitmap(bitmap)
end)

-- 异步加载 Drawable
this.loadImage("https://example.com/image.png", function(drawable)
    view.setBackground(drawable)
end)

-- 直接加载到 ImageView
this.loadImage("https://example.com/image.png", imageView)
this.loadImageWithCrossFade(data, imageView)  -- 带淡入效果

-- 同步加载（⚠️ 会阻塞主线程，不推荐）
local bitmap = this.syncLoadBitmap(data)
local drawable = this.syncLoadDrawable(data)

-- 获取 ImageLoader 单例（支持 SVG、GIF）
local loader = this.getImageLoader()
```

支持的 data 类型：URL 字符串、File 对象、Uri、Drawable 资源 ID 等。

---

## 6. 文件与路径

```lua
-- Lua 工作目录
this.getLuaDir()                -- "/data/.../files"
this.getLuaDir("res")           -- "/data/.../files/res"

-- Lua 文件路径
this.getLuaPath()               -- 当前 Lua 文件路径
this.getLuaPath("test.lua")     -- 工作目录下的文件
this.getLuaPath("sub", "a.lua") -- 子目录下的文件

-- 外部存储
this.getLuaExtDir()             -- "/sdcard/LuaJ"
this.getLuaExtDir("Projects")   -- "/sdcard/LuaJ/Projects"

-- 媒体目录（无需权限）
this.getMediaDir()              -- "/Android/media/{包名}"

-- Uri 转换
this.getUriForPath("/sdcard/test.apk")  -- 转为 FileProvider Uri
this.getPathFromUri(uri)                -- Uri 转路径

-- 资源查找
this.findFile("test.lua")       -- 查找文件完整路径
this.checkResource("icon.png")  -- 检查资源是否存在
this.findResource("icon.png")   -- 获取资源 InputStream
```

---

## 7. 权限管理

```lua
-- 检查存储权限（已授权返回 true）
if this.checkStoragePermission() then
    -- 有权限
end

-- 请求存储权限（结果回调 onStorageRequestResult）
this.requestStoragePermission()
function onStorageRequestResult(isGranted)
    if isGranted then print("已授权") end
end

-- 检查并请求所有 init.lua 中声明的危险权限
this.checkAllPermissions()

-- 创建权限请求 Launcher
local launcher = this.permissionLauncher(function(granted)
    print("权限结果:", granted)
end)
launcher.launch("android.permission.CAMERA")
```

---

## 8. 主题与颜色

### 主题设置

Activity 启动时会自动读取 `init.lua` 中的主题配置：

```lua
-- init.lua 中设置（推荐，自动生效）
NeLuaJ_Theme = "Theme_NeLuaJ_Material3"                        -- 应用自带主题
NeLuaJ_Theme = "Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay" -- 无 ActionBar

-- 或使用 Android 系统主题
theme = "Theme_Material3_DayNight"   -- 字符串：从 android.R.style 查找
theme = 0x01030224                    -- 整数：直接使用样式 ID
```

如果需要在运行时动态切换，可在 `main.lua` 中手动调用（必须在 `setContentView` 之前）：

```lua
activity.setTheme(R.style.Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay)
```

### 动态颜色与深色模式

```lua
-- 启用 Material You 动态颜色
this.dynamicColor()

-- 判断深色模式
if this.isNightMode() then
    print("当前为深色模式")
end
```

### 主题颜色工具

```lua
-- 详见 LuaThemeUtil 文档
local ColorUtil = this.themeUtil
local primary = ColorUtil.primary.main
local surface = ColorUtil.surface.container

-- 颜色滤镜（自动适配 API 级别）
local filter = this.getFilter(0xFFFF0000)
drawable.setColorFilter(filter)
```

---

## 9. 工具方法

```lua
-- 单位转换
local px = this.dpToPx(16)   -- dp → px
local px = this.spToPx(14)   -- sp → px

-- 延迟执行
this.delay(2000, function()
    print("2秒后执行")
end)

-- 测量执行时间
local ms = this.measureTime(function()
    -- 要测量的代码
end)
print("耗时:", ms, "ms")

-- 返回键拦截
this.addOnBackPressedCallback(function()
    if canGoBack then
        webView.goBack()
    else
        activity.finish()
    end
end)

-- 显示日志对话框
this.showLogs()

-- 获取版本名
local ver = this.getVersionName("1.0")

-- 启动其他应用
if not this.startPackage("com.example.app") then
    print("未找到应用")
end

-- 线程策略（允许主线程网络，仅调试用）
this.setAllowThread(true)

-- 编译 Lua 文件
this.dumpFile("input.lua", "output.luac")

-- 加载编译后的 XML 布局
local view = this.loadXmlView(File(this.getLuaDir("layout.xml")))
```

---

## 10. 数据存储

```lua
-- SharedPreferences（跨 Activity 持久化）
this.setSharedData("key", "value")
local val = this.getSharedData("key")
local val = this.getSharedData("key", "默认值")
local all = this.getSharedData()  -- 获取所有

-- 全局数据（仅内存，应用关闭后丢失）
local data = this.getGlobalData()
```

---

## 11. 服务与广播

```lua
-- 启动 Lua 服务
this.startService("service.lua", { "参数" })
this.stopService()

-- 绑定服务
this.bindService(Context.BIND_AUTO_CREATE)
function onServiceConnected(name, binder)
    local service = binder.getService()
end

-- 注册广播
import "android.content.IntentFilter"
this.registerReceiver(IntentFilter("android.intent.action.BATTERY_CHANGED"))
function onReceive(context, intent)
    print("电量:", intent.getIntExtra("level", 0))
end
```

---

## 12. Dex 加载

```lua
-- 加载外部 Dex/Jar
local loader = this.loadDex("/sdcard/plugin.dex")
local clazz = loader.loadClass("com.example.Plugin")

-- 获取所有类加载器
local loaders = this.getClassLoaders()
```

---

## 13. Activity 结果 Launcher

```lua
-- 创建结果 Launcher（替代 startActivityForResult）
local launcher = this.resultLauncher(function(result)
    if result.getResultCode() == -1 then
        local data = result.getData()
        print("返回数据:", data)
    end
end)

-- 使用
import "android.content.Intent"
local intent = Intent(Intent.ACTION_PICK)
launcher.launch(intent)
```

---

## 14. 静态方法

```lua
-- 获取其他 Activity 实例（按 Lua 文件名，不含扩展名）
local main = luajava.bindClass("com.androlua.LuaActivity").getActivity("main")

-- 日志列表
local logs = luajava.bindClass("com.androlua.LuaActivity").logs
```