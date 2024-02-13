local:res
local:table
local ColorUtil = this.globalData.ColorUtil
import "mods.utils.LuaFileUtil"
import "mods.utils.TabUtil"
import "mods.utils.MagnifierManager"
local _M1 = require "mods.utils.EditorUtil$1"
local ActionMode = bindClass "androidx.appcompat.view.ActionMode"
local MotionEvent = bindClass "android.view.MotionEvent"
local File = bindClass "java.io.File"
local _M={}
_M.last_history = {}
_M.fromRecy=false

local _clipboardActionMode=nil

local function getActionMode(view)
  return ActionMode.Callback{
    onCreateActionMode=function(mode,menu)
      _clipboardActionMode=mode
      mode.setTitle(android.R.string.selectTextMode)
      local array=activity.getTheme().obtainStyledAttributes({
        android.R.attr.actionModeSelectAllDrawable,
        android.R.attr.actionModeCutDrawable,
        android.R.attr.actionModeCopyDrawable,
        android.R.attr.actionModePasteDrawable
      })
      menu.add(0,0,0,android.R.string.selectAll)
      .setShowAsAction(2)--MenuItem.SHOW_AS_ACTION_ALWAYS
      .setIcon(array.getResourceId(0,0))
      menu.add(0,1,0,android.R.string.cut)
      .setShowAsAction(2)
      .setIcon(array.getResourceId(1,0))
      menu.add(0,2,0,android.R.string.copy)
      .setShowAsAction(2)
      .setIcon(array.getResourceId(2,0))
      menu.add(0,3,0,android.R.string.paste)
      .setShowAsAction(2)
      .setIcon(array.getResourceId(3,0))
      array.recycle()
      return true
    end,
    onActionItemClicked=function(mode,item)
      switch(item.getItemId()) do
       case 0 then
        view.selectAll()
       case 1 then
        view.cut()
        mode.finish()
       case 2 then
        view.copy()
        mode.finish()
       case 3 then
        view.paste()
        mode.finish()
      end
      return false
    end,
    onDestroyActionMode=function(mode)
      view.selectText(false)
      _clipboardActionMode=nil
    end,
  }
end


local function changeTitle(path)
  --print"改变标题"
  try
    local pattern = Bean.Path.app_root_pro_dir .. "(.*)/"
    local subfolder = string.match(path, pattern).."/"
    local projectName = subfolder:match("/(.-)/")
    Bean.Project.this_project = projectName
    activity.setTitle(projectName)
    catch
    Bean.Project.this_project = ""
    activity.setTitle("")
    finally
    activity.getSupportActionBar().setSubtitle(File(path).getName())
  end
end

local function initTab()
  -- TabLayout.OnTabSelectedListener
  mTab.addOnTabSelectedListener({
    onTabUnselected=function(tab)
    end;
    onTabSelected=function(tab)
      if not tab.tag.first then
        --print("Tab选择事件")
        _M.save()
        local path = tab.tag.path
        -- 更新当前文件
        PathManager.update_this_file(path)
        -- 载入文件
        _M.load(path)
       else
        tab.tag.first=nil
        local path = tab.tag.path
        -- 更新当前文件
        PathManager.update_this_file(path)
        -- 载入文件
        changeTitle(path)
        --print"第一次被选择的tab，editor读取"
        mLuaEditor.setText(LuaFileUtil.read(path))
      end
    end;
    onTabReselected=function(tab)
      --print"tab再次选择"
    end;
  })
end

function _M.save(path, str, editor)
  editor = editor or mLuaEditor
  path = path or Bean.Path.this_file
  str = str or tostring(editor.getText())

  if Bean.Path.this_file == ""
    return
   elseif str == LuaFileUtil.read(path)
    return "same"
  end
  _M.last_history[path] = editor.getSelectionEnd()
  -- 检查备份文件夹
  LuaFileUtil.checkBackup()
  -- 保存备份
  local _path = path:gsub(Bean.Path.app_root_pro_dir,"")
  local backups = Bean.Path.backup_dir.."/"..os.date("%Y-%m-%d").."/"..os.date("%H_%M").._path
  local backup_file = File(backups)
  -- 每分钟保存一次
  if not backup_file.exists() then
    File(backup_file.getParent()).mkdirs()
    LuaFileUtil.create(backups, str)
  end
  -- 返回写入结果
  return LuaFileUtil.write(path, str)
end

function _M.init()
  -- 初始化放大镜
  MagnifierManager.initMagnifier(mLuaEditor);
  _M1.init()
  -- 初始化Tab
  initTab();

  -- 设置高亮
  _M1.setHighLight(mLuaEditor)

  --设置字体
  mLuaEditor.setTypeface(res.font.code)

  --编辑器 放大镜 和 ActionMode
  mLuaEditor.OnSelectionChangedListener=function(status,start,end_)
    _M1.javaClassAnalyse(mLuaEditor,status)
    if not(_clipboardActionMode) and status then
      activity.startSupportActionMode(getActionMode(mLuaEditor))
      MagnifierManager.Available=true
     elseif _clipboardActionMode and not(status) then
      _clipboardActionMode.finish()
      _clipboardActionMode=nil
      MagnifierManager.hide()
      MagnifierManager.Available=false
    end
  end

  mLuaEditor.onTouch=function(view,event)
    if MagnifierManager.Available == true
      local action=event.action
      if action==MotionEvent.ACTION_DOWN or action==MotionEvent.ACTION_MOVE then
        local relativeCaretX=view.getCaretX()-view.getScrollX()
        local relativeCaretY=view.getCaretY()-view.getScrollY()
        local x=event.getX()
        local y=event.getY()
        if MagnifierManager.isNearChar(view, relativeCaretX, relativeCaretY, x, y) then
          MagnifierManager.show(view, relativeCaretX, relativeCaretY, x, y)
         else
          MagnifierManager.hide()
        end
       elseif action==MotionEvent.ACTION_CANCEL or action==MotionEvent.ACTION_UP then
        MagnifierManager.hide()
      end
    end
  end


  thread(function(mLuaEditor, bindClass)
    --activity补全
    local LuaActivity = bindClass "com.androlua.LuaActivity"
    local act={}
    local tmp={}
    for k,v : (LuaActivity.getMethods()) do
      v=tostring(v.getName())
      if not tmp[v] then
        tmp[v]=true
        act[#act+1] = v.."()"
      end
    end
    --补全

    local classes
    try
      classes = require "activities.znzsofficial.api.PublicClasses"
      catch(e)
      classes = {"LuaActivity","LuaServer","LuaService","List","ArrayList","HashMap","Object","Map"}
    end
    local ms = {
      "onCreate","onStart","onResume",
      "onPause","onStop","onDestroy","onError",
      "onActivityResult","onResult","onNightModeChanged",
      "onContentChanged","onConfigurationChanged",
      "onContextItemSelected","onCreateContextMenu",
      "onCreateOptionsMenu","onOptionsItemSelected","onRequestPermissionsResult",
      "onClick","onTouch","onLongClick",
      "onItemClick","onItemLongClick","onVersionChanged","this","android"
    }
    local l = #ms
    local match = string.match
    for k, v in ipairs(classes) do
      ms[l + k] = match(v, "%w+$")
    end
    mLuaEditor.addNames(ms)
    .addNames({"byte", "boolean", "short", "int", "long", "float", "double", "char"})
    .addNames({"R","dump","toutf8","loadlayout","printf","thread","xTask"})
    .addPackage("activity",act)
    .addPackage("this",act)
    .addPackage("debug",{"debug","gethook","getinfo","getlocal","getmetatable","getregistry","getupvalue","getuservalue","sethook","setlocal","setmetatable","setupvalue","setuservalue","traceback","upvalueid","upvaluejoin"})
    .addPackage("coroutine",{"create","resume","running","status","wrap","yield"})
    .addPackage("math",{"abs","acos","asin","atan","atan2","ceil","cos","cosh","deg","exp","floor","fmod","frexp","huge","ldexp","log","max","min","modf","pi","pow","rad","random","randomseed","sin","sinh","sqrt","tan","tanh"})
    .addPackage("string",{"byte","char","dump","find","format","gfind","gmatch","gsub","len","lower","match","pack","rep","reverse","sub","toutf8","unpack","upper"})
    .addPackage("utf8",{"byte","char","find","format","gfind","gmatch","gsub","len","lower","match","rep","reverse","sub","upper"})
    .addPackage("bit32",{"arshift","band","bnot","bor","btest","bxor","extract","lrotate","lshift","replace","rrotate","rshift"})
    .addPackage("table",{"add","clear","clone","concat","const","copy","dump","find","foreach","foreachi","gfind","insert","pack","remove","size","sort","sub","unpack"})
    .addPackage("os",{"clock","date","difftime","execute","exit","getenv","remove","rename","setlocale","time","tmpname"})
    .addPackage("file",{"exists","info","list","mkdir","readall","save","type"})
    .addPackage("json",{"decode","encode"})
    .addPackage("res",{"bitmap","dimen","drawable","font","layout","string","view",})
    .addPackage("luajava",{"astable","bindClass","createProxy","instanceof","loadLib","new","newInstance"})
    .addPackage("io",{"close","flush","input","lines","open","output","popen","read","tmpfile","type","write"})
  end,mLuaEditor, bindClass)

end

-- 加载文件请求
function _M.load(path)
  --显示编辑器
  if mLuaEditor.getVisibility() == 4 then
    mLuaEditor.setVisibility(0)
  end
  --更新当前文件
  PathManager.update_this_file(path)
  --判断Tab操作
  if TabUtil.Table[path] == nil then
    --print"editor判断为添加tab"
    TabUtil.add(path)
   else
    --print"已经存在的tab，editor读取"
    mLuaEditor.setText(LuaFileUtil.read(path))
    changeTitle(path)
    --print("来自RecyclerView"..tostring(_M.fromRecy))
    --如果是来自RV的加载就选择tab
    if _M.fromRecy
      TabUtil.Table[path].obj.select()
    end
    --载入指针位置
    if _M.last_history[path] ~= nil then
      mLuaEditor.setSelection(_M.last_history[path])
    end
  end
  table.insert(_M.last_history, 1, path)
  for n = 2, #_M.last_history do
    if n > 50 then
      _M.last_history[n] = nil
     elseif _M.last_history[n] == path then
      table.remove(_M.last_history, n)
    end
  end
  -- 销毁来自RV的标识
  _M.fromRecy=nil
end

return _M