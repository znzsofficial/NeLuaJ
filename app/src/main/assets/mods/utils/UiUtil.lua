local _M = {}

_M.isNightMode=function()
  local Configuration= bindClass"android.content.res.Configuration"
  local currentNightMode = activity.getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK
  return currentNightMode == Configuration.UI_MODE_NIGHT_YES
end

return _M