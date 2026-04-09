local SelectMain = require "mods.PreSelection.SelectMain"
local _M = {}
_M._analyseToken = 0

--SelectMain.addView(text,view,list,id)
--使用了pcall,可以判断他返回的值来判断是否执行成功
--添加布局，下面那个快捷栏的添加，text必填，其他可选
--view为编辑框ID，list添加的位置，默认为0，第一个。id父id，默认为ps_bar，当有变动时，请手动修改或者传入id
--通过该方法添加会将id保存到SelectMain.ViewId表

--SelectMain.allMoveView(id)
--使用了pcall
--ID可选，父布局ID，调用后将历遍ViewId表，根据ID删除所有控件，并清空表

--SelectMain.new(code,callBack)

--SelectMain.AnalysisImport(code,callBack)
--分析导入功能，code 需要分析的代码，callBack回调 返回一张表
--请在初始化完成之后在用，由于使用了异步，无需担心在UI线程
--[[-- 使用荔枝，当无可导入时返回空表{}（注意，初始化未完成也返回空表）
SelectMain.AnalysisImport(code,function(content)
  if type(content) == "table" then -- 不为表则是错误信息
    print(dump(content))
   else
    print("error:"..content) --出现错误
  end
end)
]]

function _M.init()
    return SelectMain.init()
end

function _M.javaClassAnalyse(view, status)
    local hintBar = select_hint_bar or ps_bar
    local hintBarParent = hintBar.getParent() -- HorizontalScrollView
    if view.getSelectedText() and status then
        -- 判断内容不为空，并且选中状态
        local text = view.getSelectedText() -- 获取到选中文本
        _M._analyseToken = (_M._analyseToken or 0) + 1
        local analyseToken = _M._analyseToken
        SelectMain.allMoveView(hintBar) -- 避免连续选择时重复堆叠旧结果
        SelectMain.new(text, function(content)
            if analyseToken ~= _M._analyseToken then
                return -- 过期请求，丢弃旧结果
            end
            if view.getSelectedText() ~= text then
                return -- 选区已变化，避免回写旧数据
            end
            if type(content) == "table" then
                -- 不为表则是错误信息
                local classList = content[text] or {}
                if next(classList) and hintBarParent then
                    hintBarParent.setVisibility(0) -- 有结果时显示
                end
                for _, v in pairs(classList) do
                    SelectMain.addView(v, nil, nil, hintBar)
                    --print(v)
                end
            else
                print("error:" .. content) --出现错误
            end
        end)
    else
        _M._analyseToken = (_M._analyseToken or 0) + 1 -- 使在途请求失效
        SelectMain.allMoveView(hintBar) -- 移除所有新增的控件
        if hintBarParent then
            hintBarParent.setVisibility(8) -- 无选中时隐藏
        end
    end
end

return _M