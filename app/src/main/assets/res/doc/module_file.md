## 介绍
file 文件操作模块
所有函数均支持绝对路径和项目路径

### readall
file.readall("main.lua")
file.readall("/sdcard/test.lua")
读取文件内容

### list
file.list("/sdcard")
返回文件夹内容表 (使用astable实现，效率较低)

### exists
file.exists(path)
判断文件是否存在

### save
file.save(path, "print('hello world')")
保存文件

### type
file.type(path)
返回 "dir" 或 "file"

### info
file.info(path)
返回文件信息表

### mkdir
file.mkdir("/sdcard/test")
创建文件夹及其父文件夹