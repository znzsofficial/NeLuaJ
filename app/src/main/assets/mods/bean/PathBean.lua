local Environment = bindClass "android.os.Environment"
local _M = {}

-- public string
--[[
_M.legacy_system_root = tostring(Environment.getExternalStorageDirectory())
_M.system_root = this.mediaDir.path
_M.legacy_app_root_dir = _M.legacy_system_root.."/LuaJ"
]]

_M.system_root = tostring(Environment.getExternalStorageDirectory())
-- 软件目录
_M.app_root_dir = _M.system_root.."/LuaJ"
-- 工程目录
_M.app_root_pro_dir = _M.app_root_dir.."/Projects"
-- 当前打开的文件夹
_M.this_dir = _M.app_root_pro_dir
-- 当前打开的文件
_M.this_file = ""
-- 备份目录
_M.backup_dir = ""

return _M