--- 应用级目录准备（原 MainActivity.initFiles 的共享部分）。
--- 编辑器专属的 Init.initView2 初始化链保留在编辑器 onCreate 内；
--- 首页授权通过后调用本模块，保证工程目录与备份目录就绪。
local _M = {}

function _M.prepareDirs()
  LuaFileUtil.checkDirectory(Bean.Path.app_root_pro_dir)
  checkBackup()
end

return _M
