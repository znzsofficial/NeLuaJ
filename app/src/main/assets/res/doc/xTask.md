### 介绍

NeLuaJ+ 实现了基于 kotlin 协程的异步函数。

## 使用

```lua
xTask {
    --dispatcher = "io",
    task = function()
        return "ret"
    end,
    callback = function(result)
    end
}
```

dispatcher为"io"或"unconfined"时，使用对应调度器

回调函数的参数为异步函数的返回值或错误信息

允许忽略回调函数