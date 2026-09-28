--- 选中文本后的界面：类名提示、复制菜单和放大镜。
local SelectMain = require "mods.PreSelection.SelectMain"
local MagnifierManager = require "mods.utils.MagnifierManager"
local Minimap = require "mods.editor.EditorMinimap"
local ActionMode = bindClass "androidx.appcompat.view.ActionMode"
local MotionEvent = bindClass "android.view.MotionEvent"
local _M = {}
local clipboardActionMode = nil
local analyseToken = 0

function _M.init()
    return SelectMain.init()
end

function _M.javaClassAnalyse(view, status)
    local hintBar = select_hint_bar or ps_bar
    if not hintBar then return end
    local hintBarParent = hintBar.getParent()
    if view.getSelectedText() and status then
        local text = view.getSelectedText()
        analyseToken = analyseToken + 1
        local token = analyseToken
        SelectMain.allMoveView(hintBar) -- 避免连续选择时重复堆叠旧结果
        SelectMain.new(text, function(content)
            if token ~= analyseToken then
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
                end
            else
                print("error:" .. content) --出现错误
            end
        end)
    else
        analyseToken = analyseToken + 1 -- 使在途请求失效
        SelectMain.allMoveView(hintBar) -- 移除所有新增的控件
        if hintBarParent then
            hintBarParent.setVisibility(8) -- 无选中时隐藏
        end
    end
end

local function commentEnabled()
    local value = this.getSharedData("editor_actionmode_comment", true)
    return value == true or value == "true" or value == 1
end

local function magnifierEnabled()
    local value = this.getSharedData("editor_magnifier", true)
    return value == true or value == "true" or value == 1
end

local function actionMode(view, toggleBlockComment)
    return ActionMode.Callback {
        onCreateActionMode = function(mode, menu)
            clipboardActionMode = mode
            mode.setTitle(android.R.string.selectTextMode)
            local array = activity.getTheme().obtainStyledAttributes({
                android.R.attr.actionModeSelectAllDrawable,
                android.R.attr.actionModeCutDrawable,
                android.R.attr.actionModeCopyDrawable,
                android.R.attr.actionModePasteDrawable
            })
            menu.add(0, 0, 0, android.R.string.selectAll)
                .setShowAsAction(2)
                .setIcon(array.getResourceId(0, 0))
            menu.add(0, 1, 0, android.R.string.cut)
                .setShowAsAction(2)
                .setIcon(array.getResourceId(1, 0))
            menu.add(0, 2, 0, android.R.string.copy)
                .setShowAsAction(2)
                .setIcon(array.getResourceId(2, 0))
            menu.add(0, 3, 0, android.R.string.paste)
                .setShowAsAction(2)
                .setIcon(array.getResourceId(3, 0))
            if commentEnabled() then
                local commentItem = menu.add(0, 4, 0, res.string.block_comment)
                commentItem.setShowAsAction(2)
                commentItem.setIcon(res.drawable("ic_comment"))
            end
            array.recycle()
            return true
        end,
        onPrepareActionMode = function()
            return false
        end,
        onActionItemClicked = function(mode, item)
            local id = item.getItemId()
            if id == 0 then
                view.selectAll()
            elseif id == 1 then
                view.cut()
                mode.finish()
            elseif id == 2 then
                view.copy()
                mode.finish()
            elseif id == 3 then
                view.paste()
                mode.finish()
            elseif id == 4 then
                toggleBlockComment(view)
                mode.finish()
            end
            return true
        end,
        onDestroyActionMode = function()
            view.selectText(false)
            clipboardActionMode = nil
        end,
    }
end

function _M.install(editor, toggleBlockComment)
    MagnifierManager.initMagnifier(editor)
    editor.OnSelectionChangedListener = function(status)
        _M.javaClassAnalyse(editor, status)
        if not clipboardActionMode and status then
            activity.startSupportActionMode(actionMode(editor, toggleBlockComment))
            MagnifierManager.Available = magnifierEnabled()
        elseif clipboardActionMode and not status then
            clipboardActionMode.finish()
            clipboardActionMode = nil
            MagnifierManager.hide()
            MagnifierManager.Available = false
        end
        Minimap.syncSelection()
    end
    editor.setOnTouchListener(function(view, event)
        if MagnifierManager.Available == true and magnifierEnabled() then
            local action = event.action
            if action == MotionEvent.ACTION_DOWN or action == MotionEvent.ACTION_MOVE then
                local relativeCaretX = view.getCaretX() - view.getScrollX()
                local relativeCaretY = view.getCaretY() - view.getScrollY()
                local x = event.getX()
                local y = event.getY()
                if MagnifierManager.isNearChar(view, relativeCaretX, relativeCaretY, x, y) then
                    MagnifierManager.show(view, relativeCaretX, relativeCaretY, x, y)
                else
                    MagnifierManager.hide()
                end
            elseif action == MotionEvent.ACTION_CANCEL or action == MotionEvent.ACTION_UP then
                MagnifierManager.hide()
            end
        end
        Minimap.onTouch(event)
        return false
    end)
end

return _M