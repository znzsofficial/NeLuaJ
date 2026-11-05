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
    { TextView, text = res.string.list_title, textSize = "24sp", textColor = "?attr/colorOnSurface" },
    { TextView, text = res.string.list_description, textSize = "16sp", textColor = "?attr/colorOnSurfaceVariant", layout_marginTop = "12dp" },
    { InputLayout, id = "taskBox", hint = res.string.task_hint,
      layout_width = "match", layout_height = "wrap", layout_marginTop = "24dp",
      { Input, id = "task", layout_width = "match", layout_height = "wrap",
        textSize = "16sp", minHeight = "56dp", inputType = "textCapSentences", singleLine = true },
    },
    { Button, id = "add", text = res.string.add_action,
      textSize = "16sp", minHeight = "48dp",
      layout_width = "match", layout_height = "wrap", layout_marginTop = "12dp" },
    { TextView, id = "status", accessibilityLiveRegion = 1, textSize = "14sp",
      textColor = "?attr/colorOnSurfaceVariant",
      layout_width = "match", layout_marginTop = "12dp" },
    { TextView, id = "empty", text = res.string.empty_list, textSize = "16sp",
      textColor = "?attr/colorOnSurfaceVariant",
      layout_width = "match", layout_marginTop = "24dp" },
    { LinearLayout, id = "rows", orientation = "vertical",
      layout_width = "match", layout_height = "wrap" },
  },
})
