--- 轻量启动环境：Bean / 工具 / ClassesNames
--- 二级页应 require 本模块，不要 require environment（会拉起主界面模块）
bindClass = luajava.bindClass

-- 类名数据（异步初始化）
local classNamesReader = luajava.newInstance("com.nekolaska.internal.ClassNamesReader", this.applicationContext)
ClassesNames = ClassesNames or {}
local classNamesLoaded = false
local function ensureClassNames()
  if classNamesLoaded then return end
  ClassesNames.classes = classNamesReader.getAllNames()
  ClassesNames.top_classes = classNamesReader.getAllTopNames()
  ClassesNames.simple_top_classes = classNamesReader.getAllTopSimpleNames()
  classNamesLoaded = true
end

xTask(function()
  classNamesReader.getAllNames()
  classNamesReader.getAllTopNames()
  classNamesReader.getAllTopSimpleNames()
end, function()
  ensureClassNames()
end)

ClassesNames.ensure = ensureClassNames
ClassesNames.reader = classNamesReader

MDC_R = bindClass "com.google.android.material.R"
Compat_R = bindClass "androidx.appcompat.R"

Bean = Bean or {}
Bean.Path = require "mods.bean.PathBean"
Bean.Project = require "mods.bean.ProjectBean"

LuaFileUtil = bindClass "com.nekolaska.io.LuaFileUtil".INSTANCE
PathManager = require "mods.utils.PathManager"

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

return true
