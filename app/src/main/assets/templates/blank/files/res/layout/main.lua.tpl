local bindClass = luajava.bindClass
local LinearLayout = bindClass "android.widget.LinearLayout"
local TextView = bindClass "android.widget.TextView"
local ScrollView = bindClass "android.widget.ScrollView"
local Screen = require "app.screen"
local colors = Screen.colors()

-- Set false for a truly toolbar-free NoActionBar page.
local showToolbar = true
return Screen.wrap({
  ScrollView,
  layout_width = "match", layout_height = "match", fillViewport = true,
  {
    LinearLayout,
    orientation = "vertical", layout_width = "match", layout_height = "wrap",
    padding = "20dp",
    { TextView, text = res.string.app_title, textSize = "24sp", textColor = colors.text,
      layout_width = "match", layout_height = "wrap" },
    { TextView, text = res.string.blank_message, textSize = "16sp", textColor = colors.secondary,
      layout_width = "match", layout_height = "wrap", layout_marginTop = "12dp" },
  },
}, showToolbar)
