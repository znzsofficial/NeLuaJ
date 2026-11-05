local bindClass = luajava.bindClass
local LinearLayout = bindClass "android.widget.LinearLayout"
local ScrollView = bindClass "android.widget.ScrollView"
local RadioGroup = bindClass "android.widget.RadioGroup"
local RadioButton = bindClass "com.google.android.material.radiobutton.MaterialRadioButton"
local Switch = bindClass "com.google.android.material.materialswitch.MaterialSwitch"
local TextView = bindClass "com.google.android.material.textview.MaterialTextView"
local Button = bindClass "com.google.android.material.button.MaterialButton"
local Screen = require "app.screen"

return Screen.wrap({
  ScrollView, layout_width = "match", layout_height = "match", fillViewport = true,
  { LinearLayout, orientation = "vertical", layout_width = "match", layout_height = "wrap", padding = "20dp",
    { TextView, text = res.string.settings_title, textSize = "24sp", textColor = "?attr/colorOnSurface" },
    { TextView, text = res.string.settings_description, textSize = "16sp", textColor = "?attr/colorOnSurfaceVariant", layout_marginTop = "12dp" },
    { TextView, text = res.string.behavior_heading, textSize = "14sp", textColor = "?attr/colorPrimary", textStyle = "bold",
      layout_marginTop = "24dp" },
    { Switch, id = "friendly", text = res.string.friendly_label,
      textSize = "16sp", textColor = "?attr/colorOnSurface", layout_marginTop = "12dp",
      layout_width = "match", layout_height = "wrap", minHeight = "48dp" },
    { TextView, text = res.string.size_heading, textSize = "14sp", textColor = "?attr/colorPrimary", textStyle = "bold",
      layout_marginTop = "24dp" },
    { RadioGroup, id = "sizes", orientation = "vertical", layout_width = "match",
      layout_height = "wrap", layout_marginTop = "12dp",
      { RadioButton, id = "standard", text = res.string.size_standard,
        textSize = "16sp", textColor = "?attr/colorOnSurface",
        layout_width = "match", layout_height = "wrap", minHeight = "48dp" },
      { RadioButton, id = "large", text = res.string.size_large,
        textSize = "16sp", textColor = "?attr/colorOnSurface",
        layout_width = "match", layout_height = "wrap", minHeight = "48dp" },
    },
    { TextView, text = res.string.preview_heading, textSize = "14sp", textColor = "?attr/colorPrimary", textStyle = "bold",
      layout_marginTop = "24dp" },
    { TextView, id = "preview", layout_width = "match", layout_height = "wrap",
      textSize = "16sp", textColor = "?attr/colorOnSurface", padding = "16dp",
      BackgroundColor = "?attr/colorSurfaceContainerLow",
      layout_marginTop = "12dp", accessibilityLiveRegion = 1 },
    { Button, id = "save", text = res.string.save_settings,
      textSize = "16sp", minHeight = "48dp",
      layout_width = "match", layout_height = "wrap", layout_marginTop = "24dp" },
    { TextView, id = "status", textSize = "14sp", accessibilityLiveRegion = 1,
      textColor = "?attr/colorOnSurfaceVariant",
      layout_width = "match", layout_marginTop = "12dp" },
  },
})
