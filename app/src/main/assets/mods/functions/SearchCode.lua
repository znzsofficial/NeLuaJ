return function()
  -- 来自OpenLua+的代码，看看就行了
  local LuaString = import "com.open.lua.util.LuaString"
  local Snackbar = bindClass "com.google.android.material.snackbar.Snackbar"
  import "res"

  local function print(content)
    Snackbar.make(coordinatorLayout, content, Snackbar.LENGTH_SHORT)
    .setAnchorView(ps_bar)
    .show();
  end

  local 搜索关键字 = ""

  local 搜索关键字结果 = {}

  local 搜索关键字位置 = 1

  local 搜索关键字长度 = 0

  search_down.onClick=function()

    if mLuaEditor.getVisibility() == 4 then
      print(res.string.no_file)
      return true
    end
    if mSearchEdit.Text==nil or mSearchEdit.Text=="" then
      print("请输入关键字")
      return
    end
    --判断是否是上次的搜索的关键字
    if mSearchEdit.Text == 搜索关键字 then
      --判断搜索有没有内容
      if (#搜索关键字结果) == 0 then
        print("结果为空")
        return
       else
        --定位关键字下一个位置
        搜索关键字位置 = 搜索关键字位置 + 1
      end
      if 搜索关键字位置 < (#搜索关键字结果) then
        local first = 搜索关键字结果[搜索关键字位置][0]
        mLuaEditor.setSelection(first,搜索关键字长度)
       elseif 搜索关键字位置 == (#搜索关键字结果) then
        local first = 搜索关键字结果[搜索关键字位置][0]
        mLuaEditor.setSelection(first,搜索关键字长度)
        搜索关键字位置 = 0
       elseif 搜索关键字位置 > (#搜索关键字结果) then
        搜索关键字位置 = 1
        local first = 搜索关键字结果[搜索关键字位置][0]
        mLuaEditor.setSelection(first,搜索关键字长度)
      end
     else
      --重新搜索并定位第一个关键字
      搜索关键字 = mSearchEdit.Text

      搜索关键字位置 = 1

      搜索关键字长度 = utf8.len(搜索关键字)

      搜索关键字结果 = luajava.astable(LuaString.gfind(mLuaEditor.Text,搜索关键字))

      if (#搜索关键字结果)==0 then

        print("结果为空")

       else

        local first = 搜索关键字结果[搜索关键字位置][0]

        mLuaEditor.setSelection(first,搜索关键字长度)

      end

    end


  end



  search_up.onClick=function()

    if mLuaEditor.getVisibility() == 4 then
      print(res.string.no_file)
      return true
    end
    if mSearchEdit.Text==nil or mSearchEdit.Text=="" then
      print("请输入关键字")
      return
    end
    --判断是否是上次的搜索的关键字
    if mSearchEdit.Text == 搜索关键字 then
      --判断搜索有没有内容
      if (#搜索关键字结果) == 0 then
        print("结果为空")
        return
       else
        --定位关键字下一个位置
        搜索关键字位置 = 搜索关键字位置 - 1
        if 搜索关键字位置 == -1 then
          if (#搜索关键字结果) == 1 then
            搜索关键字位置 = 1
           elseif (#搜索关键字结果) > 1 then
            搜索关键字位置 = #搜索关键字结果 - 1
          end
        end
      end
      if 搜索关键字位置 > 0 then

        local first = 搜索关键字结果[搜索关键字位置][0]

        mLuaEditor.setSelection(first,搜索关键字长度)

       elseif 搜索关键字位置 == 0 then

        搜索关键字位置 = #搜索关键字结果

        local first = 搜索关键字结果[搜索关键字位置][0]

        mLuaEditor.setSelection(first,搜索关键字长度)

      end

    end


  end

end