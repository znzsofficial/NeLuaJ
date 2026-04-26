# ext 模块

## 介绍

`ext` 是 NeLuaJ+ 的扩展模块，提供 Lua 5.5 风格的二进制打包和解包辅助函数。

当前包含：

- `ext.pack(format, ...)`
- `ext.unpack(format, data, pos)`
- `ext.packsize(format)`

---

## 格式字符串

### 字节序

| 选项 | 描述 |
| :--- | :--- |
| `<` | 小端序 |
| `>` | 大端序 |
| `=` | 使用本机字节序 |

### 对齐与填充

| 选项 | 描述 |
| :--- | :--- |
| `!n` | 设置最大对齐值 |
| `x` | 填充 1 个字节 |
| `Xop` | 按下一个选项的对齐要求进行填充 |
| 空格 | 忽略 |

### 数值类型

| 选项 | 描述 |
| :--- | :--- |
| `b` / `B` | 有符号 / 无符号 1 字节整数 |
| `h` / `H` | 有符号 / 无符号 2 字节整数 |
| `l` / `L` | 有符号 / 无符号 8 字节整数 |
| `j` / `J` | 有符号 / 无符号 Lua 整数，按 8 字节处理 |
| `T` | `size_t`，按 8 字节无符号整数处理 |
| `i[n]` / `I[n]` | 有符号 / 无符号 n 字节整数，默认 4 字节，范围 1 到 16 |
| `f` | 4 字节单精度浮点数 |
| `d` / `n` | 8 字节双精度浮点数 |

### 字符串类型

| 选项 | 描述 |
| :--- | :--- |
| `c[n]` | 固定长度字符串，不足部分用 `\0` 填充 |
| `s[n]` | 带长度前缀的字符串，长度字段 n 字节，默认 8 字节 |
| `z` | 以 `\0` 结尾的字符串 |

---

## ext.pack

```lua
local data = ext.pack("<i4 I2 f c5 z", -123456, 65535, 3.5, "abc", "hello")
```

按照 `format` 将参数打包为二进制字符串。

---

## ext.unpack

```lua
local i, u, f, c, z, nextPos = ext.unpack("<i4 I2 f c5 z", data)
```

按照 `format` 从二进制字符串中读取数据。最后一个返回值是下一次读取的位置。

`pos` 参数可选，默认从 1 开始：

```lua
local data = "XX" .. ext.pack("<h", -321)
local value, nextPos = ext.unpack("<h", data, 3)
```

---

## ext.packsize

```lua
local size = ext.packsize("<i4 I2 f c5")
```

返回固定长度格式的打包大小。

包含 `s` 或 `z` 这类可变长度格式时会报错：

```lua
-- variable-length format
ext.packsize("s2")
```

---

## 完整示例

```lua
local data = ext.pack("<i4 I2 f d c5 s2 z",
  -123456,
  65535,
  3.5,
  123.456,
  "abc",
  "hello",
  "world"
)

local i, u, f, d, c, s, z, nextPos = ext.unpack("<i4 I2 f d c5 s2 z", data)

print(i, u, f, d, c, s, z, nextPos)
print("size", #data)
```
