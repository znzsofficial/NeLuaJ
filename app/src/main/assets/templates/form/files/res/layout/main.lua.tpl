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
    { TextView, text = res.string.form_title, textSize = "24sp", textColor = "?attr/colorOnSurface" },
    { TextView, text = res.string.form_description, textSize = "16sp", textColor = "?attr/colorOnSurfaceVariant", layout_marginTop = "12dp" },
    { InputLayout, id = "nameBox", hint = res.string.name_hint,
      layout_width = "match", layout_height = "wrap", layout_marginTop = "24dp",
      { Input, id = "name", layout_width = "match", layout_height = "wrap",
        textSize = "16sp", minHeight = "56dp", inputType = "textPersonName", singleLine = true },
    },
    { Button, id = "submit", text = res.string.greet_action,
      textSize = "16sp", minHeight = "48dp",
      layout_width = "match", layout_height = "wrap", layout_marginTop = "12dp" },
    { Button, id = "clear", styleAttr = "?attr/materialIconButtonStyle",
      contentDescription = res.string.clear_action,
      layout_width = "48dp", layout_height = "48dp", layout_gravity = "end",
      layout_marginTop = "12dp" },
    { TextView, id = "result", textSize = "16sp", textColor = "?attr/colorOnSurface", accessibilityLiveRegion = 1,
      layout_width = "match", layout_height = "wrap", layout_marginTop = "12dp" },
  },
})
