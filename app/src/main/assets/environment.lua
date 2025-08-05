bindClass = luajava.bindClass;

local reader = luajava.newInstance("com.nekolaska.internal.ClassNamesReader", this.applicationContext)
ClassesNames = {}
ClassesNames.classes = reader.getAllNames()
ClassesNames.top_classes = reader.getAllTopNames()
ClassesNames.simple_top_classes = reader.getAllTopSimpleNames()

MDC_R = bindClass "com.google.android.material.R"
Compat_R = bindClass "androidx.appcompat.R"

MainActivity={}
MainActivity.Public=require"activities.main.MainActivity$1"
MainActivity.RecyclerView=require"activities.main.MainActivity$RecyclerView"
Bean={}
Bean.Path = require "mods.bean.PathBean"
Bean.Project = require "mods.bean.ProjectBean"

local File = bindClass"java.io.File"
checkBackup = function()
  local p = this.getMediaDir().path
  Bean.Path.backup_dir = p.."/backups"
  local backup = File(Bean.Path.backup_dir.."/"..os.date("%Y-%m-%d"));
  if not backup.exists() then
    backup.mkdirs();
  end
end
LuaFileUtil = bindClass "com.nekolaska.io.LuaFileUtil".INSTANCE
PathManager = require "mods.utils.PathManager"