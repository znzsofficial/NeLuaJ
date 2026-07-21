--- 主界面完整环境 = bootstrap + MainActivity 模块
--- 二级页请改用 require "mods.bootstrap"
require "mods.bootstrap"

MainActivity = MainActivity or {}
MainActivity.Public = require "activities.main.MainPublic"
MainActivity.RecyclerView = require "activities.main.MainFileList"

return true
