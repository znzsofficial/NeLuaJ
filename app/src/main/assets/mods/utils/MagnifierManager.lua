local _M = {}
local Magnifier
_M.Available=false

_M.initMagnifier=function(view)
  try

    Magnifier = bindClass "android.widget.Magnifier"

    if Magnifier.Builder then
      _M.magnifier = Magnifier.Builder(view)
      .setSize(320, 128)
      .setCornerRadius(24)
      .build();
      return
    end

    _M.magnifier = Magnifier(view)

    catch

    -- 不存在Magnifier时
    SupportProperties.Magnifier = false

    Magnifier = bindClass "com.nekolaska.internal.CustomMagnifier";
    _M.magnifier = Magnifier(view)
    .setCornerRadius(24)
    .setDimensions(320,128)

  end
end

_M.isNearChar=function(editor,relativeCaretX,relativeCaretY,x,y)
  local TOUCH_SLOP=editor.getTextSize()+10
  return (y >= (relativeCaretY - TOUCH_SLOP)
  and y < (relativeCaretY + TOUCH_SLOP+100)
  and x >= (relativeCaretX - TOUCH_SLOP-40)
  and x < (relativeCaretX + TOUCH_SLOP+40))
end

_M.show=function(view,relativeCaretX,relativeCaretY,eventX,eventY)
  local magnifierX=eventX
  local magnifierY=relativeCaretY-view.getTextSize()/2+2
  _M.magnifier.show(magnifierX, magnifierY);
end

_M.hide=function()
  _M.magnifier.dismiss()
end

return _M