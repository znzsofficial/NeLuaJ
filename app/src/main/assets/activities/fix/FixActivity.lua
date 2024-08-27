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

local rs
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
    local cache={}
    local function checkclass(path,ret)
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
          checkclass(p,ret)
        end
      end
      local lex=LuaLexer(str)
      local buf={}
      local last=nil
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
    checkclass(path,ret)
    return String(ret)
    catch(e)
    print(e)
    return nil
  end
end

local list=ListView(activity)
list.ChoiceMode=ListView.CHOICE_MODE_MULTIPLE;

xTask{
    task = fixImport,
    callback = function(v)
        try
            rs = v
            local adp=ArrayListAdapter(activity,android.R.layout.simple_list_item_multiple_choice,v)
            list.Adapter=adp
            activity.setContentView(list)
        catch
            print("分析失败")
            activity.finish()
        end
    end
}

function onCreateOptionsMenu(menu)
  menu.add(res.string.logs).setShowAsAction(1)
  menu.add("反选").setShowAsAction(1)
  menu.add("复制").setShowAsAction(1)
end


function onOptionsItemSelected(item)
  if item.Title=="复制" then
    try
      local buf={}
      local cm=activity.getSystemService(Context.CLIPBOARD_SERVICE)
      local cs=list.getCheckedItemPositions()
      local buf={}
      for n=0,#rs-1 do
        if cs.get(n) then
          insert(buf,string.format("import \"%s\"",rs[n]))
        end
      end

      local str=table.concat(buf,"\n")
      local cd = ClipData.newPlainText("label", str)
      cm.setPrimaryClip(cd)
      Toast.makeText(activity,"已复制到剪切板",1000).show()
    end
   elseif item.title=="反选" then
    try
      for n=0,#rs-1 do
        list.setItemChecked(n,not list.isItemChecked(n))
      end
    end
   elseif item.title==res.string.logs then
    import "mods.utils.ActivityUtil"
    ActivityUtil.showLog(activity)
  end
end
