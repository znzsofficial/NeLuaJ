-- LuaActivity passes newActivity's argument array to the script as varargs.
local message = ...
local Screen = require "app.screen"
local views = Screen.show(require "res.layout.detail", res.string.detail_title)
views.message.setText(tostring(message or res.string.default_message))
views.back.setOnClickListener(function()
  activity.finish()
end)
