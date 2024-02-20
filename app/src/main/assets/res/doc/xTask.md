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
第一个参数为数值时，延迟指定时长后调用回调函数
第三个参数为"io"时，使用IO调度器
回调函数的参数为异步函数的返回值或错误信息
允许忽略回调函数