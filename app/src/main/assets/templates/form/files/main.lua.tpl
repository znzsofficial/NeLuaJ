local bindClass = luajava.bindClass
local AndroidR = bindClass "android.R"
local Screen = require "app.screen"
local views = Screen.show(require "res.layout.main", res.string.app_title)

-- Use the MaterialButton's themed icon tint, not a background replacement.
local clearIcon = activity.getDrawable(AndroidR.drawable.ic_menu_close_clear_cancel)
views.clear.setIcon(clearIcon)
views.clear.setContentDescription(res.string.clear_action)
views.clear.setTooltipText(res.string.clear_action)

views.submit.setOnClickListener(function()
  local editable = views.name.getText()
  local name = tostring(editable):match("^%s*(.-)%s*$")
  if name == "" then
    views.nameBox.setError(res.string.name_required)
    views.name.requestFocus()
    return
  end
  if utf8.len(name) > 40 then
    views.nameBox.setError(res.string.name_too_long)
    views.name.requestFocus()
    return
  end
  views.nameBox.setError(nil)
  views.result.setText(res.string.greeting_prefix .. name .. "!")
end)

views.clear.setOnClickListener(function()
  views.name.setText("")
  views.nameBox.setError(nil)
  views.result.setText("")
  views.name.requestFocus()
end)
