bindClass = luajava.bindClass;

ColorUtil = luajava.newInstance("github.daisukiKaffuChino.utils.LuaThemeUtil",activity)
MDC_R = bindClass "com.google.android.material.R"
Compat_R = bindClass "androidx.appcompat.R"

SupportProperties = require "mods.property.SupportProperties"

try
  bindClass "java.nio.file.Files";
  catch
  SupportProperties.NIO = false
end

MainActivity={}
MainActivity.Public=require"activities.znzsofficial.main.MainActivity$1"
MainActivity.RecyclerView=require"activities.znzsofficial.main.MainActivity$RecyclerView"
Bean={}
Bean.Path = require "mods.bean.PathBean"
Bean.Project = require "mods.bean.ProjectBean"

PathManager = require "mods.utils.PathManager"
LuaFileUtil = require "mods.utils.LuaFileUtil"
DrawableUtil = require "mods.utils.DrawableUtil"