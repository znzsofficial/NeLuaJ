bindClass = luajava.bindClass;
local File = bindClass "java.io.File"

for _,v in File(this.getLuaDir("libs/")).listFiles() do
  v.setReadOnly()
end

this.globalData.ColorUtil = luajava.newInstance("github.daisukiKaffuChino.utils.LuaThemeUtil",activity)
MDC_R = bindClass "com.google.android.material.R"
Compat_R = bindClass "androidx.appcompat.R"

MainActivity={}
MainActivity.Public=require"activities.main.MainActivity$1"
MainActivity.RecyclerView=require"activities.main.MainActivity$RecyclerView"
Bean={}
Bean.Path = require "mods.bean.PathBean"
Bean.Project = require "mods.bean.ProjectBean"

checkBackup = function()
  local p = luajava.astable(activity.getExternalMediaDirs())[1].getPath()
  Bean.Path.backup_dir = p.."/backups"
  local backup = File(Bean.Path.backup_dir.."/"..os.date("%Y-%m-%d"));
  if not backup.exists() then
    backup.mkdirs();
  end
end
LuaFileUtil = bindClass "com.nekolaska.io.LuaFileUtil".INSTANCE
PathManager = require "mods.utils.PathManager"