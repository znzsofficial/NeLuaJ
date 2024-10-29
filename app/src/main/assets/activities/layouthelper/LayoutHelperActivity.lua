bindClass = luajava.bindClass;

ColorUtil = luajava.newInstance("github.daisukiKaffuChino.utils.LuaThemeUtil",activity)
MDC_R = bindClass "com.google.android.material.R"
Compat_R = bindClass "androidx.appcompat.R"

ColorPrimary = ColorUtil.getColorPrimary() --这个 loadlayout 和 mods 都要用，所以直接全局la

local MotionEvent = bindClass "android.view.MotionEvent"
local MaterialAlertDialogBuilder = bindClass "com.google.android.material.dialog.MaterialAlertDialogBuilder"
local ProgressBar = bindClass "android.widget.ProgressBar"
local Paint = bindClass "android.graphics.Paint"
old_res = res
local TypedValue = bindClass("android.util.TypedValue")
local ProgressBarDialog = require "mods.functions.ProgressBarDialog"
LayoutHelperActivity = {
  data = require "activities.layouthelper.LayoutHelperActivity$data",
}

activity.setTitle(old_res.string.layout_helper)
.getSupportActionBar()
.setDisplayShowHomeEnabled(true)
.setDisplayHomeAsUpEnabled(true)

LayoutHelperActivity.data.this_file,LayoutHelperActivity.data.this_project_lua_dir = ...
package.path=package.path..";"..LayoutHelperActivity.data.this_project_lua_dir.."/?.lua;"
local load_dialog = ProgressBarDialog()
local loadlayout2

task(1,function()

  try

    LayoutHelperActivity.mods = require "activities.layouthelper.LayoutHelperActivity$1"
    LayoutHelperActivity.method = require "activities.layouthelper.LayoutHelperActivity$2"
    LayoutHelperActivity.event = require "activities.layouthelper.LayoutHelperActivity$3"
    res = require "activities.layouthelper.LayoutHelperActivity$res"
    loadlayout2 = require "activities.layouthelper.LayoutHelperActivity$loadlayout"

    local file_content = loadfile(LayoutHelperActivity.data.this_file)()
    activity.setContentView(loadlayout2(file_content,{}))
    LayoutHelperActivity.data.current_layout_table=file_content

   catch(e)

    MaterialAlertDialogBuilder(activity)
    .setTitle(old_res.string.tip)
    .setMessage(e)
    .setPositiveButton(android.R.string.ok,nil)
    .setNegativeButton(android.R.string.cancel,nil)
    .setOnDismissListener(function()
      activity.finish(true)
    end)
    .show()

   finally

    collectgarbage("collect") -- 清个内存
    load_dialog.dismiss()

  end

end)

local onTouchTime = 0

function onViewTouch(v,e)

  if e.getAction() == MotionEvent.ACTION_DOWN then

    onTouchTime = 0
    LayoutHelperActivity.mods.setSelectForeground(v)
    LayoutHelperActivity.data.current_view = v

   elseif e.getAction() == MotionEvent.ACTION_UP then

    if onTouchTime < 30 then
      LayoutHelperActivity.mods.showEditViewDialog(v)
    end

    v.setForeground(nil)

   elseif e.getAction() == MotionEvent.ACTION_MOVE then

    onTouchTime = onTouchTime + 1
    if onTouchTime > 30 then
      LayoutHelperActivity.mods.setCancelSelectForeground(v)
    end

  end
  return true
end

--[[ AbsoluteLayout  ]]

local dm=activity.getResources().getDisplayMetrics()

function dp(n)
  return TypedValue.applyDimension(1,n,dm)
end

local dn=dp(1)
local lastX=0
local lastY=0
local vx=0
local vy=0
local vw=0
local vh=0
local zoomX=false
local zoomY=false
local lp

function to(n)
  return string.format("%ddp",n//dn)
end

function onAbsoluteLayoutChildViewTouch(v,e)
  local curr=v.Tag
  LayoutHelperActivity.data.current_view=v
  local ry=e.getRawY()--获取触摸绝对Y位置
  local rx=e.getRawX()--获取触摸绝对X位置
  if e.getAction() == MotionEvent.ACTION_DOWN then
    lp=v.getLayoutParams()
    vy=v.getY()--获取视图的Y位置
    vx=v.getX()--获取视图的X位置
    lastY=ry--记录按下的Y位置
    lastX=rx--记录按下的X位置
    vw=v.getWidth()--记录控件宽度
    vh=v.getHeight()--记录控件高度
    if vw-e.getX()<20 then
      zoomX=true--如果触摸右边缘启动缩放宽度模式
     elseif vh-e.getY()<20 then
      zoomY=true--如果触摸下边缘启动缩放高度模式
    end

   elseif e.getAction() == MotionEvent.ACTION_MOVE then
    --lp.gravity=Gravity.LEFT|Gravity.TOP --调整控件至左上角
    if zoomX then
      lp.width=(vw+(rx-lastX))--调整控件宽度
     elseif zoomY then
      lp.height=(vh+(ry-lastY))--调整控件高度
     else
      lp.x=(vx+(rx-lastX))--移动的相对位置
      lp.y=(vy+(ry-lastY))--移动的相对位置
    end
    v.setLayoutParams(lp)--调整控件到指定的位置
    --v.Parent.invalidate()
   elseif e.getAction() == MotionEvent.ACTION_UP then
    if (rx-lastX)^2<100 and (ry-lastY)^2<100 then
      LayoutHelperActivity.mods.showEditViewDialog(LayoutHelperActivity.data.current_view)
     else
      curr.layout_x=to(v.getX())
      curr.layout_y=to(v.getY())
      if zoomX then
        curr.layout_width=to(v.getWidth())
       elseif zoomY then
        curr.layout_height=to(v.getHeight())
      end
    end
    zoomX=false--初始化状态
    zoomY=false--初始化状态
  end
  return true
end
--[[ AbsoluteLayout ]]

local copy = function(str)
  activity.getSystemService(this.CLIPBOARD_SERVICE).setText(str)
end

local finish = function()
  collectgarbage("collect")
  activity.finish(true)
end

local save_dialog = MaterialAlertDialogBuilder(activity)
.setTitle(old_res.string.tip)
.setMessage(old_res.string.confirm_dump_layouttable)
.setPositiveButton(android.R.string.ok,function()

  LayoutHelperActivity.mods.ret = {}

  local load_dialog = ProgressBarDialog()

  task(1,function()

    local dump_layouttable = LayoutHelperActivity.mods.dumpLayouttable(
    LayoutHelperActivity.data.current_layout_table
    )

    MaterialAlertDialogBuilder(activity)
    .setTitle(old_res.string.tip)
    .setMessage(dump_layouttable)
    .setPositiveButton(old_res.string.copy,function()
      copy(dump_layouttable)
      finish()
    end)
    .setNegativeButton(android.R.string.cancel,finish)
    .show()

    .create().findViewById(android.R.id.message)
    .setTextIsSelectable(true)

    defer load_dialog.dismiss()

  end)

end)
.setNegativeButton(android.R.string.cancel,finish)

if bindClass "android.os.Build".VERSION.SDK_INT >= 33 then
this.addOnBackPressedCallback(function()
  save_dialog.show()
end)
else
function onKeyDown(code,event)
    if string.find(tostring(event),"KEYCODE_BACK") ~= nil then
        save_dialog.show()
        return true
    end
end
end

function onOptionsItemSelected(m)
  switch m.getItemId() do
   case android.R.id.home
    save_dialog.show()
  end
end

