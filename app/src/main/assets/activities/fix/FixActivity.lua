require "environment"
import "android.content.ClipData"
import "android.content.Context"
import "android.widget.ListView"
import "android.widget.Toast"
import "com.androlua.LuaLexer"
import "com.androlua.LuaTokenTypes"
import "com.androlua.adapter.ArrayListAdapter"
import "java.io.File"
import "java.lang.String"
import "res"

local clazzList
local path = ...
local table = table
local string = string
local package = package
activity.setTitle('需要导入的类')
.setContentView(res.layout.fix_layout)
.getSupportActionBar()
.setElevation(0)

local function fixImport()
  try
    local allClasses = require "activities.api.PublicClasses"
    local cache = {}
    local function check(path, ret)
      if cache[path] then
        return
      end
      cache[path]=true
      local f=io.open(path)
      local str=f:read("a")
      f:close()
      if not str then
        return
      end
      --[[
    for s,e,t in str:gfind("(import \"[%w%.]+%*\")") do
      --local p=package.searchpath(t,searchpath)
      --print(t,p)
    end]]
      for s,e,t in str:gfind("import \"([%w%.]+)\"") do
        local p=package.searchpath(t,path)
        if p then
            check(p,ret)
        end
      end
      local lex=LuaLexer(str)
      local buf = {}
      local last = nil
      while true do
        local t=lex.advance()
        if not t then
          break
        end
        if last~=LuaTokenTypes.DOT and t==LuaTokenTypes.NAME then
          local text=lex.yytext()
          buf[text]=true
        end
        last=t
      end
      -- table.sort(buf)
      for k,v in pairs(buf) do
        k="[%.$]"..k.."$"
        for a,b in ipairs(allClasses) do
          if string.find(b,k) then
            if cache[b]==nil then
              ret[#ret+1]=b
              cache[b]=true
            end
          end
        end
      end
    end
    local ret={}
    check(path,ret)
    return ret
    catch(e)
      print(e)
      return {}
  end
end

local list=ListView(activity)
list.ChoiceMode=ListView.CHOICE_MODE_MULTIPLE;

xTask{
    task = fixImport,
    callback = function(slist)
        try
            if #slist == 0 then
                print("未找到可导入的类")
                activity.finish()
                return
            end
            clazzList = slist
            list.Adapter = ArrayListAdapter(activity,android.R.layout.simple_list_item_multiple_choice, slist)
            activity.setContentView(list)
        catch(e)
            print("分析失败", e)
            activity.finish()
        end
    end
}

function onCreateOptionsMenu(menu)
  menu.add(res.string.logs).setShowAsAction(1)
  menu.add(res.string.invert).setShowAsAction(1)
  menu.add(res.string.copy).setShowAsAction(1)
end


function onOptionsItemSelected(item)
  if item.Title==res.string.copy then
      local insert = table.insert
      local buffer = {}
      local cm = activity.getSystemService(Context.CLIPBOARD_SERVICE)
      local cs = list.getCheckedItemPositions()
      local buffer = {}
      for n = 0, #clazzList do
        if cs.get(n) then
          insert(buffer, string.format("import \"%s\"",clazzList[n+1]))
        end
      end

      local str=table.concat(buffer,"\n")
      local cd = ClipData.newPlainText("import", str)
      cm.setPrimaryClip(cd)
      Toast.makeText(activity,res.string.copy_success, 1000).show()
   elseif item.title=="反选" then
    try
      for n=0,#clazzList-1 do
        list.setItemChecked(n,not list.isItemChecked(n))
      end
    end
   elseif item.title==res.string.logs then
    import "mods.utils.ActivityUtil"
    ActivityUtil.showLog(activity)
  end
end
