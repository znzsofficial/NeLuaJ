--- 脚本/工程启动：全屏 / freeform / 已分屏旁侧
local RunWindowConfig = require "mods.utils.RunWindowConfig"

local _M = {}

local function supportsFreeformWindow(ctx)
  local ok, supported = pcall(function()
    local Build = luajava.bindClass "android.os.Build"
    if Build.VERSION.SDK_INT < 24 then return false end
    return ctx.getPackageManager()
        .hasSystemFeature("android.software.freeform_window_management")
  end)
  return ok and supported
end

local function isInMultiWindow(ctx)
  local ok, v = pcall(function()
    return ctx.isInMultiWindowMode()
  end)
  return ok and v == true
end

local function buildLaunchBounds(ctx)
  local Rect = luajava.bindClass "android.graphics.Rect"
  local dm = ctx.getResources().getDisplayMetrics()
  local w = math.floor(dm.widthPixels * 0.55 + 0.5)
  local h = math.floor(dm.heightPixels * 0.65 + 0.5)
  local minW = math.floor(ctx.dpToPx(300) + 0.5)
  local minH = math.floor(ctx.dpToPx(400) + 0.5)
  if w < minW then w = math.min(minW, dm.widthPixels) end
  if h < minH then h = math.min(minH, dm.heightPixels) end
  local left = math.floor((dm.widthPixels - w) * 0.55 + 0.5)
  local top = math.floor(dm.heightPixels * 0.15 + 0.5)
  return Rect(left, top, left + w, top + h)
end

local function launchFreeform(ctx, path)
  if not supportsFreeformWindow(ctx) then
    return false
  end
  local Intent = luajava.bindClass "android.content.Intent"
  local Uri = luajava.bindClass "android.net.Uri"
  local ActivityOptions = luajava.bindClass "android.app.ActivityOptions"
  local LuaActivityX = luajava.bindClass "com.androlua.LuaActivityX"

  local intent = Intent(ctx, LuaActivityX)
  intent.setData(Uri.parse("file://" .. path))
  intent.putExtra("name", path)
  intent.addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT)
  intent.addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
  intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

  local opts = ActivityOptions.makeBasic()
  pcall(function()
    opts.setLaunchBounds(buildLaunchBounds(ctx))
  end)
  local okStart = pcall(function()
    ctx.startActivity(intent, opts.toBundle())
  end)
  if not okStart then
    okStart = pcall(function()
      ctx.startActivity(intent)
    end)
  end
  return okStart == true
end

local function launchAdjacent(ctx, path)
  if not isInMultiWindow(ctx) then
    return false
  end
  local Intent = luajava.bindClass "android.content.Intent"
  local Uri = luajava.bindClass "android.net.Uri"
  local LuaActivityX = luajava.bindClass "com.androlua.LuaActivityX"

  local intent = Intent(ctx, LuaActivityX)
  intent.setData(Uri.parse("file://" .. path))
  intent.putExtra("name", path)
  intent.addFlags(Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT)
  intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
  intent.addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
  local okStart = pcall(function()
    ctx.startActivity(intent)
  end)
  return okStart == true
end

--- 按 run_window_mode 启动 Lua 脚本
--- @param ctx Activity (this/activity)
--- @param path string
--- @param opts { snack?: function }|nil
function _M.launchScript(ctx, path, opts)
  opts = opts or {}
  local snack = opts.snack
  local mode = RunWindowConfig.getMode(ctx)
  if mode == RunWindowConfig.MODE_FREEFORM then
    local ok, success = pcall(function()
      return launchFreeform(ctx, path)
    end)
    if ok and success then return true end
    if snack then
      pcall(function() snack(res.string.run_window_fallback_freeform) end)
    end
  elseif mode == RunWindowConfig.MODE_ADJACENT then
    local ok, success = pcall(function()
      return launchAdjacent(ctx, path)
    end)
    if ok and success then return true end
    if snack then
      pcall(function() snack(res.string.run_window_fallback_adjacent) end)
    end
  end
  ctx.newActivity(path)
  return true
end

--- 调试应用到外部包
function _M.launchDebugApp(ctx, packageName, mainPath)
  local Intent = luajava.bindClass "android.content.Intent"
  local ComponentName = luajava.bindClass "android.content.ComponentName"
  local Uri = luajava.bindClass "android.net.Uri"
  local intent = Intent()
  intent.setComponent(ComponentName(packageName, "com.androlua.LuaActivity"))
  intent.setData(Uri.parse("file://" .. mainPath))
  local mode = RunWindowConfig.getMode(ctx)
  if mode == RunWindowConfig.MODE_FREEFORM and supportsFreeformWindow(ctx) then
    local launched = false
    pcall(function()
      local ActivityOptions = luajava.bindClass "android.app.ActivityOptions"
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      intent.addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
      local opts = ActivityOptions.makeBasic()
      opts.setLaunchBounds(buildLaunchBounds(ctx))
      ctx.startActivity(intent, opts.toBundle())
      launched = true
    end)
    if launched then return true end
  elseif mode == RunWindowConfig.MODE_ADJACENT and isInMultiWindow(ctx) then
    local launched = false
    pcall(function()
      intent.addFlags(Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT)
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      intent.addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
      ctx.startActivity(intent)
      launched = true
    end)
    if launched then return true end
  end
  ctx.startActivity(intent)
  return true
end

_M.supportsFreeformWindow = supportsFreeformWindow
_M.isInMultiWindow = isInMultiWindow

return _M
