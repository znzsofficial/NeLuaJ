local bindClass = luajava.bindClass
local LinearLayout = bindClass "android.widget.LinearLayout"
local TextView = bindClass "com.google.android.material.textview.MaterialTextView"
local WebView = bindClass "android.webkit.WebView"
local Screen = require "app.screen"

return Screen.wrap({
  LinearLayout, orientation = "vertical", layout_width = "match", layout_height = "match",
  { TextView, id = "status", text = res.string.web_description, textSize = "14sp",
    textColor = "?attr/colorOnSurfaceVariant",
    paddingLeft = "20dp", paddingRight = "20dp", paddingTop = "12dp", paddingBottom = "12dp",
    layout_width = "match", layout_height = "wrap",
    accessibilityLiveRegion = 1 },
  { WebView, id = "web", layout_width = "match", layout_height = 0, layout_weight = 1 },
})
