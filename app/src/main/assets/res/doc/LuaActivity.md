### 介绍
**LuaActivity**比较全面的迁移到了 AndroidX，新增了一些方法，但是有没有差不多（


### 示例

```lua
function onError(error, message)
  print(error, message)
  return ture
end
报错时调用
返回(任意非空值)可以拦截原报错输出

function onNightModeChanged(mode)
  print(mode)
end
切换UiMode时调用

activity.getRootView()
返回ViewGroup
```