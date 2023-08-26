### 介绍
**github.znzsofficial.neluaj.LuaTask**
是一个使用Executors实现的异步任务类，用法与原task模块基本一致。
但是参数只能传一个，多个参数建议传table

### 使用

```lua
local LuaTask = luajava.newInstance("github.znzsofficial.neluaj.LuaTask", activity)
task = LuaTask.invoke
```