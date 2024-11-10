local Environment = bindClass "android.os.Environment"
local _M = {}

-- public string
--[[
_M.legacy_system_root = tostring(Environment.getExternalStorageDirectory())
_M.system_root = this.mediaDir.path
_M.legacy_app_root_dir = _M.legacy_system_root.."/LuaJ"
]]

_M.system_root = tostring(Environment.getExternalStorageDirectory())
_M.app_root_dir = _M.system_root.."/LuaJ"
_M.app_root_pro_dir = _M.app_root_dir.."/Projects"
_M.this_dir = ""
_M.this_file = ""
_M.backup_dir = ""

return _M