## 懒加载

```lua
local v = lazy(this.getMediaDir)
v = lazy(this.getLuaDir, "subdir")
v = lazy(function() return "value" end)
v = lazy(lambda () : "value")
print(v.value)
```