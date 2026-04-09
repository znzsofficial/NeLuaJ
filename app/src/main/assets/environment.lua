bindClass = luajava.bindClass

-- 类名数据（异步初始化，首次访问时如果还没加载完会同步等待）
local classNamesReader = luajava.newInstance("com.nekolaska.internal.ClassNamesReader", this.applicationContext)
ClassesNames = {}
local classNamesLoaded = false
local function ensureClassNames()
  if classNamesLoaded then return end
  ClassesNames.classes = classNamesReader.getAllNames()
  ClassesNames.top_classes = classNamesReader.getAllTopNames()
  ClassesNames.simple_top_classes = classNamesReader.getAllTopSimpleNames()
  classNamesLoaded = true
end

-- 异步预加载类名，不阻塞 UI
xTask(function()
  -- 在后台线程触发 lazy 初始化
  classNamesReader.getAllNames()
  classNamesReader.getAllTopNames()
  classNamesReader.getAllTopSimpleNames()
end, function()
  -- 回到主线程，填充全局表
  ensureClassNames()
end)

-- 提供同步访问保障（给需要立即使用的场景）
ClassesNames.ensure = ensureClassNames
ClassesNames.reader = classNamesReader

-- Material / AppCompat R 类
MDC_R = bindClass "com.google.android.material.R"
Compat_R = bindClass "androidx.appcompat.R"

-- 模块加载
MainActivity = {}
MainActivity.Public = require "activities.main.MainActivity$1"
MainActivity.RecyclerView = require "activities.main.MainActivity$RecyclerView"
Bean = {}
Bean.Path = require "mods.bean.PathBean"
Bean.Project = require "mods.bean.ProjectBean"

-- 工具类
LuaFileUtil = bindClass "com.nekolaska.io.LuaFileUtil".INSTANCE
PathManager = require "mods.utils.PathManager"

-- 备份目录检查（只在需要时创建目录）
local File = bindClass "java.io.File"
local backupDirChecked = false
checkBackup = function()
  if backupDirChecked then return end
  local p = this.getMediaDir().path
  Bean.Path.backup_dir = p .. "/backups"
  local backup = File(Bean.Path.backup_dir .. "/" .. os.date("%Y-%m-%d"))
  if not backup.exists() then
    backup.mkdirs()
  end
  backupDirChecked = true
end