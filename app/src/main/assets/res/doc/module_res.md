## 介绍

NeLuaJ+ 对 LuaJ++ 的 res模块 进行了一些修改并增强了多语言支持。

### res.string

1. 读取 init.lua 中的信息。
2. 检查是否存在当前设备语言对应的文件。
3. 若存在相应语言文件，读取该文件。
4. 若不存在相应语言文件，则检查默认语言设置（设置在 default.lua 中）并加载。

### res.bitmap / res.drawable

返回 drawable 文件夹内图片的Bitmap对象或Drawable对象

### res.font

返回 font 文件夹内 ttf/otf 字体文件的 Typeface 对象

### res.layout

返回 layout 文件夹内的布局表

### res.view

对 layout 文件夹内布局表进行加载后返回

### res.dimen

1. 读取 init.lua 中的信息
2. 读取 land.lua(横屏时) 或 port.lua(竖屏时) 或 undefined.lua

### res.color

1. 读取 init.lua 中的信息
2. 读取 day.lua 或 night.lua