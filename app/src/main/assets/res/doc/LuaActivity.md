### 介绍
**LuaActivity**比较全面的迁移到了 AndroidX，新增了一些方法

全局环境中的 this 和 activity 都指向当前 LuaActivity

### 可能被调用的全局函数
```lua
onCreate()
onStart()
onResume()
onPause()
onStop()
onDestroy()

onResult(name)
onActivityResult(requestCode, resultCode, data)
onContentChanged()
onConfigurationChanged(newConfig)
onReceive(context, intent)
onSupportActionModeStarted(mode)
onSupportActionModeFinished(mode)
onPanelClosed(featureId, menu)
onCreateOptionsMenu(menu)
onOptionsItemSelected(item)
onCreateContextMenu(contextMenu, view, contextMenuInfo)
onContextItemSelected(item)
onRequestPermissionsResult(requestCode, permissions, grantResults)
onServiceConnected(componentName, service)
onServiceDisconnected(componentName)

onKeyShortcut(keyCode, event)
onKeyLongPress(keyCode, event)
onKeyUp(keyCode, event)
onKeyDown(keyCode, event)
onTouchEvent(event)
onVersionChanged(new, old)

onError(error, message)
onNightModeChanged(mode)
```
### 示例

```lua
--[[
报错时调用
可通过修改返回值修改报错方式
（可选 "trace","log", "message", "title"）
返回其他非空值可以拦截原报错输出
]]
function onError(error, message)
    print(error, message)
    return ture
end

--切换UiMode时调用
function onNightModeChanged(mode)
    print(mode)
end

-- 等同于 setContentView(loadlayout(布局表))
this.setContentView(布局表)

--返回是否为夜间模式
this.isNightMode()

--返回ViewGroup
this.getRootView()
this.getDecorView()

--返回支持加载SVG和GIF的Coil ImageLoader唯一单例
this.getImageLoader()

--直接使用Coil异步加载图片
--data 类型见 https://coil-kt.github.io/coil/getting_started/#supported-data-types
this.loadImage(data, function(drawable)
end)
this.loadImage(data, imageView)

-- 直接设置 onBackPressedDispatcher 的 Callback
-- 监听返回键 (仅 API33 以上)
this.addOnBackPressedCallback(function()
end)

--获取指定颜色的
--BlendModeColorFilter / PorterDuffColorFilter
this.getFilter(color)

--获取 /Android/media 内的私有文件夹
this.getMediaDir()

--不建议使用
this.setAllowThread(bool)

-- 编译 Lua 文件
this.dumpFile(inputPath, outputPath)

-- 延迟执行
this.delay(1000, function() 
    print("hello")
end)

-- 测量函数执行时间，返回毫秒
this.measureTime(function()
end)

-- 循环执行
this.repeat(100, function()
end)
```