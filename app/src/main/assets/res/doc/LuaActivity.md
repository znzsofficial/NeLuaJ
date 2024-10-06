### 介绍
**LuaActivity**比较全面的迁移到了 AndroidX，新增了一些方法，但是有没有差不多（

全局环境中的 this 和 activity 都指向当前 LuaActivity

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

--返回是否为夜间模式
this.isNightMode()

--返回ViewGroup
this.getRootView()
this.getDecorView()

--返回支持加载SVG和GIF的Coil ImageLoader唯一单例
this.getImageLoader()

--直接使用Coil异步加载图片, data 类型见 https://coil-kt.github.io/coil/getting_started/#supported-data-types
this.loadImage(data, function(drawable)
end)
this.loadImage(data, imageView)

--获取指定颜色的 PorterDuffColorFilter
this.getFilter(color)

--不建议使用
this.setAllowThread(bool)
```