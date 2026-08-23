local _M = {}
_M.Available = false

local function dismissMagnifier()
  if not _M.magnifier then return end
  pcall(function() _M.magnifier.dismiss() end)
end

_M.initMagnifier = function(view)
  _M.destroy()
  try
    local Magnifier = bindClass "android.widget.Magnifier"
    if Magnifier.Builder then
      _M.magnifier = Magnifier.Builder(view)
        .setSize(320, 128)
        .setCornerRadius(24)
        .build()
      return
    end
    _M.magnifier = Magnifier(view)
  catch
    local Magnifier = bindClass "com.nekolaska.internal.CustomMagnifier"
    _M.magnifier = Magnifier(view)
      .setCornerRadius(24)
      .setDimensions(320, 128)
  end
end

_M.isNearChar = function(editor, relativeCaretX, relativeCaretY, x, y)
  local TOUCH_SLOP = editor.getTextSize() + 10
  return y >= (relativeCaretY - TOUCH_SLOP)
    and y < (relativeCaretY + TOUCH_SLOP + 100)
    and x >= (relativeCaretX - TOUCH_SLOP - 40)
    and x < (relativeCaretX + TOUCH_SLOP + 40)
end

_M.show = function(view, relativeCaretX, relativeCaretY, eventX, eventY)
  if not _M.magnifier then return end
  local magnifierX = eventX
  local magnifierY = relativeCaretY - view.getTextSize() / 2 + 2
  pcall(function()
    _M.magnifier.show(magnifierX, magnifierY)
  end)
end

_M.hide = function()
  dismissMagnifier()
end

_M.destroy = function()
  _M.Available = false
  if not _M.magnifier then return end
  pcall(function()
    if _M.magnifier.destroy then
      _M.magnifier.destroy()
    else
      _M.magnifier.dismiss()
    end
  end)
  _M.magnifier = nil
end

return _M
