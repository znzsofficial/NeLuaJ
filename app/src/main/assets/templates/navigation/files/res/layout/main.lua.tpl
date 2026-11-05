local bindClass = luajava.bindClass
local LinearLayout = bindClass "android.widget.LinearLayout"
local ScrollView = bindClass "android.widget.ScrollView"
local TextView = bindClass "com.google.android.material.textview.MaterialTextView"
local Button = bindClass "com.google.android.material.button.MaterialButton"
local InputLayout = bindClass "com.google.android.material.textfield.TextInputLayout"
local Input = bindClass "com.google.android.material.textfield.TextInputEditText"
local Screen = require "app.screen"

return Screen.wrap({
  ScrollView, layout_width = "match", layout_height = "match", fillViewport = true,
  { LinearLayout, orientation = "vertical", layout_width = "match", layout_height = "wrap", padding = "20dp",
    { TextView, text = res.string.navigation_title, textSize = "24sp", textColor = "?attr/colorOnSurface" },
    { TextView, text = res.string.navigation_description, textSize = "16sp", textColor = "?attr/colorOnSurfaceVariant", layout_marginTop = "12dp" },
    { InputLayout, hint = res.string.message_hint, layout_width = "match",
      layout_height = "wrap", layout_marginTop = "24dp",
      { Input, id = "message", layout_width = "match", layout_height = "wrap",
        textSize = "16sp", minHeight = "56dp", inputType = "textCapSentences", maxLength = 500 },
    },
    { Button, id = "open", text = res.string.open_detail,
      textSize = "16sp", minHeight = "48dp",
      layout_width = "match", layout_height = "wrap", layout_marginTop = "12dp" },
  },
})
