local Screen = require "app.screen"
local Routes = require "app.routes"
local views = Screen.show(require "res.layout.main", res.string.app_title)

views.open.setOnClickListener(function()
  local editable = views.message.getText()
  local message = tostring(editable):match("^%s*(.-)%s*$")
  if message == "" then message = res.string.default_message end
  Routes.openDetail(message)
end)
