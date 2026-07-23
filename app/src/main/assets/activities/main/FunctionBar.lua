--- 功能栏 chips：catalog + Actions 映射 + 渲染
import "android.widget.LinearLayout"
import "android.widget.TextView"

local FunctionBarConfig = require "mods.utils.FunctionBarConfig"
local ActivityUtil = require "mods.utils.ActivityUtil"
local loadlayout = loadlayout
local rippleRes = activity.obtainStyledAttributes({ android.R.attr.selectableItemBackground }).getResourceId(0, 0)

local DEFAULT_FUNCTION_TAB_TEXT_SIZE = 5
local MIN_BAR_TEXT_SIZE = 5
local MAX_BAR_TEXT_SIZE = 24

local _M = {}

local function clampBarTextSize(value, defaultSize)
  local n = tonumber(value)
  if not n then return defaultSize end
  n = math.floor(n + 0.5)
  if n < MIN_BAR_TEXT_SIZE then return MIN_BAR_TEXT_SIZE end
  if n > MAX_BAR_TEXT_SIZE then return MAX_BAR_TEXT_SIZE end
  return n
end

local function getFunctionTabTextSize()
  return clampBarTextSize(
    this.getSharedData("function_tab_text_size", DEFAULT_FUNCTION_TAB_TEXT_SIZE),
    DEFAULT_FUNCTION_TAB_TEXT_SIZE
  )
end

local function addChip(parent, text, onClick, onLongClick)
  local textSize = getFunctionTabTextSize()
  local chip = {
    TextView,
    TextSize = textSize .. "sp",
    BackgroundResource = rippleRes,
    text = text,
    paddingLeft = "8dp",
    paddingRight = "8dp",
    paddingTop = "6dp",
    paddingBottom = "6dp",
    clickable = true,
    focusable = true,
    onClick = onClick,
  }
  if onLongClick then
    chip.longClickable = true
    chip.onLongClick = function()
      onLongClick()
      return true
    end
  end
  parent.addView(loadlayout {
    LinearLayout,
    chip,
  })
end

local function buildClickMap(Actions)
  return {
    save = function() Actions.saveCurrentFile() end,
    backup = function() Actions.backupCurrentProject() end,
    format = function() Actions.formatCode() end,
    undo = function() Actions.undo() end,
    redo = function() Actions.redo() end,
    search = function() Actions.showSearchBar() end,
    check_error = function() Actions.checkError() end,
    compile = function() Actions.compileCurrentFile() end,
    analysis_import = function() Actions.openJavaAnalysis() end,
    java_editor = function() Actions.openJavaEditor() end,
    layout_helper = function() Actions.openLayoutHelper() end,
    api = function() Actions.openApi() end,
    resource = function() Actions.openResource() end,
    media = function() Actions.openMedia() end,
    build = function() Actions.openBuild() end,
    create_project = function() Actions.createProject() end,
    project_settings = function() Actions.openProjectSettings() end,
    run = function() Actions.runCurrent() end,
    logs = function() ActivityUtil.showLog(activity) end,
    setting = function() Actions.openSetting() end,
    help = function() Actions.openHelp() end,
  }
end

local function buildLongClickMap()
  local RunKeyConfig = require "mods.utils.RunKeyConfig"
  return {
    -- 长按运行 → 与设置页相同的运行键配置
    run = function()
      RunKeyConfig.showPicker(this)
    end,
  }
end

function _M.buildActions(Actions)
  local click = buildClickMap(Actions)
  local longClick = buildLongClickMap()
  local ids = FunctionBarConfig.parseIds(this.getSharedData("function_bar", nil))
    or FunctionBarConfig.getDefaultIds()
  local actions = {}
  for _, id in ipairs(ids) do
    local item = FunctionBarConfig.getItem(id)
    local onClick = click[id]
    if item and onClick then
      actions[#actions + 1] = {
        id = id,
        title = FunctionBarConfig.resolveTitle(item),
        onClick = onClick,
        onLongClick = longClick[id],
      }
    end
  end
  if #actions == 0 then
    for _, id in ipairs(FunctionBarConfig.getDefaultIds()) do
      local item = FunctionBarConfig.getItem(id)
      local onClick = click[id]
      if item and onClick then
        actions[#actions + 1] = {
          id = id,
          title = FunctionBarConfig.resolveTitle(item),
          onClick = onClick,
          onLongClick = longClick[id],
        }
      end
    end
  end
  return actions
end

function _M.render(parent, Actions)
  parent.removeAllViews()
  for _, action in ipairs(_M.buildActions(Actions)) do
    addChip(parent, action.title, action.onClick, action.onLongClick)
  end
end

return _M
