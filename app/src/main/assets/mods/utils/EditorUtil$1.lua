local SelectMain = require "mods.PreSelection.SelectMain"
local Color = bindClass "android.graphics.Color"
local _M = {}

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
    if view.getSelectedText() and status then
        -- 判断内容不为空，并且选中状态
        local text = view.getSelectedText() -- 获取到选中文本
        SelectMain.new(text, function(content)
            if type(content) == "table" then
                -- 不为表则是错误信息
                for _, v in pairs(content[text]) do
                    SelectMain.addView(v)
                    --print(v)
                end
            else
                print("error:" .. content) --出现错误
            end
        end)
    else
        SelectMain.allMoveView() -- 移除所有新增的控件
    end
end

function _M.setHighLight(view)
    local data = this.sharedData
    view.basewordColor = data["BaseWord"] and Color.parseColor(data["BaseWord"]) or 0xff4477e0
    view.keywordColor = data["KeyWord"] and Color.parseColor(data["KeyWord"]) or 0xffb4002d
    view.stringColor = data["String"] and Color.parseColor(data["String"]) or 0xffc2185b
    view.userwordColor = data["UserWord"] and Color.parseColor(data["UserWord"]) or 0xff5c6bc0
end

return _M