### 介绍
NeLuaJ+ 实现了基于 kotlin 协程的异步函数。

## 使用
```lua
xTask(
        function()
            error('msg')
            return 'ret'
        end, function(arg)
            print(arg)
        end
)
```
回调函数的参数为异步函数的返回值或错误信息