local _M = {}

_M.moveIfNotExist = function()
    if LuaFileUtil.isEmpty(Bean.Path.app_root_pro_dir) then
        xTask(function()
            LuaFileUtil.moveDirectory(Bean.Path.legacy_app_root_dir, Bean.Path.app_root_dir)
        end, function()
            print(res.string.finished_migrate)
        end)
    end
end

return _M