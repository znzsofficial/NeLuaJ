local Screen = require "app.screen"
local Preferences = require "app.preferences"
local views = Screen.show(require "res.layout.main", res.string.app_title)
local settings = Preferences.load()
if not settings then
  views.status.setText(res.string.load_failed)
  views.save.setEnabled(false)
  return
end

views.friendly.setChecked(settings.friendly)
views.standard.setChecked(not settings.large)
views.large.setChecked(settings.large)

local function updatePreview()
  local friendly = views.friendly.isChecked()
  views.preview.setText(friendly and res.string.friendly_greeting or res.string.formal_greeting)
  views.preview.setTextSize(views.large.isChecked() and 24 or 16)
end

views.friendly.setOnCheckedChangeListener(function() updatePreview() end)
views.sizes.setOnCheckedChangeListener(function() updatePreview() end)
views.save.setOnClickListener(function()
  local nextSettings = {
    friendly = views.friendly.isChecked(),
    large = views.large.isChecked(),
  }
  local saved = Preferences.save(nextSettings)
  views.status.setText(saved and res.string.saved or res.string.save_failed)
end)
updatePreview()
