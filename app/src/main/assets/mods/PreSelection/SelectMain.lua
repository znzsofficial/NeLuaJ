---@diagnostic disable: undefined-global
local _M = {}

_M.ViewId = {}

local:bindClass
local next ,table ,string ,pairs ,ipairs = next ,table ,string ,pairs ,ipairs
local task ,thread = task ,thread
local:pcall
local:loadlayout
-- local HashMap = bindClass "java.util.HashMap"

local table_insert = table.insert

-- _M.Map = HashMap()
_M.Map = {}
local map = _M.Map

local ViewId = _M.ViewId


local match = string.match
local format = string.format

local LinearLayout = bindClass "android.widget.LinearLayout"
local TextView = bindClass "android.widget.TextView"
local rippleRes = activity.obtainStyledAttributes({android.R.attr.selectableItemBackground}).getResourceId(0,0)
local PopupMenu = bindClass "androidx.appcompat.widget.PopupMenu"

local LuaLexer = bindClass "com.androlua.LuaLexer"
local LuaTokenTypes = bindClass "com.androlua.LuaTokenTypes"

local function copy(str)
  activity.getSystemService("clipboard").setText(str)
end

local function LuaLexerIteratorBuilder(code)
  local lexer=LuaLexer(code)
  return function()
    local advance=lexer.advance()
    local text=lexer.yytext()
    local column=lexer.yycolumn()
    return advance,text,column
  end
end


-- 输入{"a.b.c","a.c.b.c","a.d.c.d"}
-- 返回{"c"= {"a.b.c","a.c.b.c"},"d" = {"a.d.c.d"}}
function _M.init_Calendar(tab)
  local allClasses = {}
  local insertedClasses = {}
  local pattern2 = "^[%w]*[^%$]$"
  local pattern1 = "^[%w]*[%$]?[%w]*[^%d]*[%w]*[^%$]$"
  for i = 0 ,#tab-1 do
    local className = match(tab[i],".*%.(.*)$")
    if match(className,pattern2) or match(className,pattern1) then
      local fastReadClassesSelf=allClasses[className]
      if not(fastReadClassesSelf) then
        fastReadClassesSelf={}
        allClasses[className]=fastReadClassesSelf
      end
      local class = tab[i]
      if not(insertedClasses[class]) then
        insertedClasses[class]=true
        table_insert(fastReadClassesSelf,class)
      end
      fastReadClassesSelf = nil
    end
  end

  return allClasses
end


-- 初始化，会将表进行保存，{[1]={...},[2]={...}} 2是系统的类，1是软件的
function _M.init()
  xTask(function()
      local init_table = map["PreSelection_init"]
      if not (init_table) then
        local Classes = ClassesNames.classes
        init_table = {}
        for index,content in ipairs({Classes}) do -- 这里的循环设计原本想的是可能会有多个表
          init_table[index] = _M.init_Calendar(content)
        end
        map["PreSelection_init"] = init_table
        --print(map["PreSelection_init"][1])
      end
  end)
end

function _M.AnalysisImport(code,callBack)
  xTask(function()
    return pcall(function()
      local importClassList={}
      local buf={}
      local last
      local init_table = map["PreSelection_init"]
      if not (init_table) then
        _M.init() -- 初始化
        print("正在初始化，请稍后再试")
       else
        for advance,text,column in LuaLexerIteratorBuilder(code) do
          if last~=LuaTokenTypes.DOT and advance==LuaTokenTypes.NAME then
            if not(buf[text]) then
              buf[text]=true
              for i,v in pairs(init_table) do
                local fastReadClassesSelf=v[text]
                if fastReadClassesSelf then
                  for i2,v2 in pairs(fastReadClassesSelf) do
                    if not v2:find("^org.luaj.android") then
                      importClassList[#importClassList+1] = v2
                    end
                  end
                end
              end
            end
          end
          last = advance
        end
      end
      return importClassList
    end)
  end,
  function(success,content)
    if success then
      callBack(content or {})
     else
      -- 当有错误的时候也通过此回调，请判断返回的类型，正常为table
      callBack(content)
    end
  end)
end

function _M.Obtain(code)
  return pcall(function()
    local importClassList = {}
    local ClassList = map[code]
    if not (ClassList) then
      local init_table = map["PreSelection_init"]
      if not (init_table) then
        _M.init() -- 初始化
       else
        for i,v in pairs(init_table) do
          for i2,v2 in pairs(v) do
            if match(i2,"^"..code.."$") or match(i2,"%$"..code.."$") or match(i2,"%$"..code.."%$") then
              --table.insert(importClassList,v)
              if importClassList[code] == nil then
                importClassList[code] = {}
              end
              for i = 1 ,#v2 do
                importClassList[code][#importClassList[code]+1] = v2[i]
              end
              continue
            end
          end
          continue
        end
        map[code] = importClassList
      end
     else
      importClassList = ClassList
      ClassList = nil
    end
    return importClassList
  end)
end

function _M.addView(text,view,list,id)
  return pcall(function()
    ViewId[#ViewId+1] = {}
    local Item=loadlayout({
      LinearLayout,
      id = "item_root",
      layout_width="wrap",
      layout_height="36dp",
      layout_gravity="center",
      {
        TextView,
        layout_width="wrap",
        layout_height="36dp",
        gravity="center",
        clickable=true,
        focusable=true,
        textStyle="bold",
        TextSize="5sp",
        paddingLeft='10dp',
        paddingRight='10dp',
        BackgroundResource=rippleRes,
        text=text,
        onClick=function(v)
          local popupMenu=PopupMenu(activity,v)
          local menu=popupMenu.menu
          menu.add("复制导入类代码")
          menu.add("查看Api")
          popupMenu.onMenuItemClick=function(item)
            ;(mLuaEditor or view).selectText(false)
            switch item.title
             case "复制导入类代码"
              copy(format('local %s = luajava.bindClass "%s"',match(text,".*%.(.*)$"),text))
              --mLuaEditor.paste(v)
              print("已复制导入代码")
             case "查看Api"
              activity.newActivity(activity.getLuaDir().."/activities/api/sub/main",{text})
            end
          end
          popupMenu.show()
        end,
      },
    },ViewId[#ViewId])
    ;(ps_bar or id).addView(Item,list or 0)
  end)
end

function _M.allMoveView(id)
  return pcall(function()
    for _, v in pairs(ViewId) do
      ;(ps_bar or id).removeView(v.item_root)
    end
    ViewId = {}
  end)
end

function _M.new(text,callBack)
  if text and text ~= "" then
    task(_M.Obtain, text,
    function(success,content)
      if success then
        if next(content or {})
          callBack(content)
        end
       else
        -- 当有错误的时候也通过此回调，请判断返回的类型，正常为table
        callBack(content)
      end
    end)
  end
end

return _M