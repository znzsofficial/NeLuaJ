local bindClass = luajava.bindClass
local LinearLayout = bindClass "android.widget.LinearLayout"
local ScrollView = bindClass "android.widget.ScrollView"
local TextView = bindClass "com.google.android.material.textview.MaterialTextView"
local Button = bindClass "com.google.android.material.button.MaterialButton"
local Screen = require "app.screen"

return Screen.wrap({
  ScrollView, layout_width = "match", layout_height = "match", fillViewport = true,
  { LinearLayout, orientation = "vertical", layout_width = "match", layout_height = "wrap", padding = "20dp",
    { TextView, text = res.string.received_message, textSize = "24sp", textColor = "?attr/colorOnSurface" },
    { TextView, id = "message", textSize = "16sp", textIsSelectable = true, textColor = "?attr/colorOnSurface",
      layout_width = "match", layout_marginTop = "12dp" },
    { Button, id = "back", text = res.string.back_action,
      textSize = "16sp", minHeight = "48dp", styleAttr = "?attr/materialButtonOutlinedStyle",
      layout_width = "match", layout_height = "wrap", layout_marginTop = "24dp" },
  },
})
