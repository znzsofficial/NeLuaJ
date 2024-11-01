## 介绍

NeLuaJ+ 实现了基于 kotlin 协程的异步函数。

### 使用

```lua
xTask {
    --dispatcher = "io",
    task = function(coroutineContext)
        return "ret"
    end,
    callback = function(result)
        print(result)
    end
}
-- 或
xTask(function(coroutineContext)  end,function()  end)
```

dispatcher为"io"，使用io调度器

回调函数的参数为异步函数的返回值或错误信息

允许忽略回调函数