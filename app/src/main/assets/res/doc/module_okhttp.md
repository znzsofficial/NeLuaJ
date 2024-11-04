## 介绍
NeLuaJ+ 实现了基于 OkHttp3 的同步网络模块和异步网络模块

函数返回值均为 Response 对象

headers 均为可选参数

## 同步模式
headers 和 body 类型为 LuaTable

### okhttp.get
```lua
okhttp.get(url, headers)
```

### okhttp.delete
```lua
okhttp.delete(url, body, headers)
```

### okhttp.post
```lua
okhttp.post(url, body, headers)
```

### okhttp.put

```lua
okhttp.put(url, body, headers)
```

### okhttp.patch

```lua
okhttp.patch(url, body, headers)
```

### okhttp.head
```lua
okhttp.head(url, headers)
```

## 异步模式
headers 类型为 Map

body 类型为 application/x-www-form-urlencoded

或 text/plain

或 application/json

编码格式的字符串

### okHttp.unsafe
不安全的 okHttp 模块实例
```lua
okHttp.unsafe.get("https://m.baidu.com", function(code, body)
end)
```

### okHttp.get
```lua
okHttp.get(url, headers, function(code, body)
end)
```

### okHttp.post
```lua
okHttp.post(url, body, headers, function(code, body)
end)
```

### okHttp.postText
```lua
okHttp.post(url, body, headers, function(code, body)
end)
```

### okHttp.postJson
```lua
okHttp.post(url, body, headers, function(code, body)
end)
```