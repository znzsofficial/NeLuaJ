### 介绍
**LuaActivity**比较全面的迁移到了 AndroidX，新增了一些方法，但是有没有差不多（


### 示例

```lua
function onError(error, message)
  print(error, message)
  return ture
end
报错时调用
可通过修改返回值修改报错方式 （可选 "trace","log","message","title"）
返回其他非空值可以拦截原报错输出

function onNightModeChanged(mode)
  print(mode)
end
切换UiMode时调用

activity.isNightMode()
返回是否为夜间模式

activity.getRootView()
activity.getDecorView()
返回ViewGroup

activity.setAllowThread(bool)
不建议使用（

activity.getImageLoader()
创建一个支持加载SVG和GIF的Coil ImageLoader实例

```