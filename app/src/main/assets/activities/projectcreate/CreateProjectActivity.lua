---@diagnostic disable: undefined-global
require "mods.bootstrap"
local File = luajava.bindClass "java.io.File"
local ColorDrawable = luajava.bindClass "android.graphics.drawable.ColorDrawable"
local TextWatcher = luajava.bindClass "android.text.TextWatcher"
local Toast = luajava.bindClass "android.widget.Toast"
local ArrayAdapter = luajava.bindClass "android.widget.ArrayAdapter"
local R = luajava.bindClass "github.znzsofficial.neluaj.R"
local ActivityUtil = require "mods.utils.ActivityUtil"
local ProjectTheme = require "mods.utils.ProjectTheme"
local Registry = require "mods.project.templates.Registry"
local Generator = require "mods.project.templates.Generator"
local Controller = require "activities.projectcreate.Controller"
local Layout = require "activities.projectcreate.Layout"
local modules = { "time", "array", "strings", "anim", "rxlua", "vconsole" }
local binding, flow, updating = {}, nil, false
local shownPreview, shownError
local lastAutoPkg = "com.neluaj.demo1"
local host = this
this.setTheme(R.style.Theme_NeLuaJ_Material3_DynamicColors)
this.dynamicColor()
local colors = this.themeUtil
-- Keep the existing generator theme contract while presenting two independent choices.
local themeFamilies = { "m3", "dyn", "mc", "compat" }
local themeValues = {}
for _, option in ipairs(ProjectTheme.CREATE_CHIPS) do themeValues[option.chip] = option.value end

local function failureText(result)
  local text = res.string.project_create_failed
  if type(result) ~= "table" then return text .. "\n" .. tostring(result) end
  text = text .. "\n" .. tostring(result.phase or "") .. ": " .. tostring(result.message or result.error or "")
  for _, key in ipairs({ "file", "projectPath", "stagingPath", "cleanupError" }) do
    if result[key] then text = text .. "\n" .. tostring(result[key]) end
  end
  return text
end
local function selectedTheme()
  local family = themeFamilies[binding.project_theme_family.getSelectedItemPosition() + 1] or "m3"
  local suffix = binding.project_titlebar.getSelectedItemPosition() == 1 and "_ab" or ""
  return assert(themeValues["theme_" .. family .. suffix])
end
local function compatible(template)
  local theme = selectedTheme()
  local family = ProjectTheme.isCompat(theme) and "compat"
    or ProjectTheme.isMaterialComponent(theme) and "mc"
    or ProjectTheme.isDynamic(theme) and "dynamic" or "m3"
  for _, value in ipairs(template.themeFamilies) do if value == family then return true end end
  return false
end
local function previewText(result)
  local lines = { res.string.project_review, "", result.projectPath, "", res.string.project_preview_files }
  for _, entry in ipairs(result.files) do lines[#lines + 1] = entry.path end
  lines[#lines + 1] = ""
  lines[#lines + 1] = res.string.project_permissions
  if #result.permissions == 0 then lines[#lines + 1] = res.string.project_no_permissions end
  for _, permission in ipairs(result.permissions) do lines[#lines + 1] = permission end
  return table.concat(lines, "\n")
end
local function render(state)
  local configuring = state.page == "configuration"
  binding.templates.setVisibility(configuring and 8 or 0)
  binding.configuration.setVisibility(configuring and 0 or 8)
  binding.footer.setVisibility((configuring or state.busy) and 0 or 8)
  binding.primary.setVisibility(configuring and 0 or 8)
  binding.primary.setEnabled(not state.busy)
  binding.primary.setText(state.preview and res.string.create_project or res.string.project_review)
  binding.progress.setVisibility(state.busy and 0 or 8)
  binding.status.setVisibility(state.busy and 0 or 8)
  binding.status.setText(state.phase == "generate" and res.string.project_creating or res.string.project_preparing)
  for _, id in ipairs({ "project_appName", "project_packageName", "project_change_template",
      "project_internet", "project_debug_mode", "project_open_after", "project_advanced_toggle" }) do
    binding[id].setEnabled(not state.busy)
  end
  binding.project_theme_family.setEnabled(not state.busy)
  binding.project_titlebar.setEnabled(not state.busy)
  local family = themeFamilies[binding.project_theme_family.getSelectedItemPosition() + 1] or "m3"
  binding.project_theme_description.setText(res.string["project_theme_family_" .. family .. "_desc"])
  binding.project_titlebar_description.setText(binding.project_titlebar.getSelectedItemPosition() == 1
    and res.string.project_titlebar_system_desc or res.string.project_titlebar_custom_desc)
  for _, id in ipairs(modules) do binding["module_" .. id].setEnabled(not state.busy) end
  binding.review.setVisibility(state.preview and 0 or 8)
  if state.preview then binding.review.setText(previewText(state.preview)) end
  local errorText = state.error and failureText(state.error)
  if state.template then
    binding.project_template_summary.setText(res.string[state.template.titleKey])
    binding.project_template_description.setText(res.string[state.template.descriptionKey])
    binding.project_theme_compatibility.setText(state.template.id == "blank"
      and res.string.project_theme_blank_support or res.string.project_theme_m3_support)
    if not compatible(state.template) then errorText = res.string.project_theme_incompatible end
  end
  binding.project_error.setText(errorText or "")
  binding.project_error.setVisibility(errorText and 0 or 8)
  if (state.preview and state.preview ~= shownPreview) or (errorText and errorText ~= shownError) then
    binding.configuration.post(function()
      if not host.isFinishing() and not host.isDestroyed() then binding.configuration.fullScroll(130) end
    end)
  end
  shownPreview, shownError = state.preview, errorText
end
local function selectTemplate(template)
  if flow.busy then return end
  -- Retain user configuration when moving back, but use template defaults initially.
  if not flow.template then
    updating = true
    binding.project_internet.setChecked(template.defaults.useInternet == true)
    binding.project_debug_mode.setChecked(template.defaults.debugMode ~= false)
    updating = false
  end
  flow.select(template)
end
local content = loadlayout(Layout.build(Registry.list(), selectTemplate), binding)
activity.setTitle(res.string.create_project)
activity.setContentView(content)
local actionBar = activity.getSupportActionBar()
actionBar.setElevation(0)
actionBar.setBackgroundDrawable(ColorDrawable(colors.getColorBackground()))
actionBar.setDisplayShowTitleEnabled(true)
actionBar.setDisplayHomeAsUpEnabled(true)
activity.getWindow().setSoftInputMode(0x10)
require("mods.utils.SystemBars").apply(activity.getWindow(), colors.getColorBackground(), colors.getColorSurface())

flow = Controller.new {
  alive = function() return not host.isFinishing() and not host.isDestroyed() end,
  task = xTask, generator = Generator, changed = render,
  complete = function(result, openAfter)
    local message = res.string.create_success .. ": " .. result.config.appName .. "\n" .. res.string.project_readme_hint
    if result.cleanupError then
      message = message .. "\n" .. res.string.project_staging_path .. " " .. tostring(result.stagingPath or "")
        .. "\n" .. tostring(result.cleanupError)
    end
    Toast.makeText(host, message, Toast.LENGTH_LONG).show()
    ActivityUtil.finishWith(openAfter and "open_project" or "project_created", result.projectPath)
    host.finish()
  end,
}
local function edited() if not updating then flow.edit() end end
local function pathPreview(name)
  binding.project_path_preview.setText(res.string.project_path_label .. "\n" .. Bean.Path.app_root_pro_dir .. "/" .. (name ~= "" and name or "…"))
end
binding.project_appName.setText("demo1")
binding.project_packageName.setText(lastAutoPkg)
local function setupSpinner(view, labels)
  local adapter = ArrayAdapter(activity, android.R.layout.simple_spinner_item)
  for _, text in ipairs(labels) do adapter.add(text) end
  adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
  view.setAdapter(adapter)
  view.setSelection(0)
  local previous = 0
  view.setOnItemSelectedListener {
    onItemSelected = function(_, _, position)
      if position == previous then return end
      previous = position
      edited()
    end,
    onNothingSelected = function() end,
  }
end
setupSpinner(binding.project_theme_family, {
  res.string.project_theme_family_m3, res.string.project_theme_family_dyn,
  res.string.project_theme_family_mc, res.string.project_theme_family_compat,
})
setupSpinner(binding.project_titlebar, { res.string.project_titlebar_custom, res.string.project_titlebar_system })
pathPreview("demo1")
binding.project_appName.addTextChangedListener(TextWatcher {
  beforeTextChanged = function() end, onTextChanged = function() end,
  afterTextChanged = function(value)
    local name = tostring(value or "")
    pathPreview(name)
    local current = tostring(binding.project_packageName.text)
    if current == lastAutoPkg or current == "" then
      local segment = name:lower():gsub("[^%w_]", "")
      if segment == "" then segment = "app" end
      if segment:match("^%d") then segment = "a" .. segment end
      lastAutoPkg = "com.neluaj." .. segment
      binding.project_packageName.setText(lastAutoPkg)
    end
    edited()
  end,
})
binding.project_packageName.addTextChangedListener(TextWatcher {
  beforeTextChanged = function() end, onTextChanged = function() end, afterTextChanged = edited,
})
for _, id in ipairs({ "project_internet", "project_debug_mode", "project_open_after" }) do
  binding[id].setOnCheckedChangeListener(edited)
end
for _, id in ipairs(modules) do binding["module_" .. id].setOnCheckedChangeListener(edited) end
binding.project_change_template.onClick = function() flow.back() end
local advanced = false
binding.project_advanced_toggle.onClick = function()
  advanced = not advanced
  binding.project_advanced.setVisibility(advanced and 0 or 8)
  binding.project_advanced_toggle.setText(advanced and res.string.project_advanced_hide or res.string.project_advanced_show)
end
binding.primary.onClick = function()
  if flow.busy then return end
  if flow.preview then flow.create() return end
  if not compatible(flow.template) then render(flow) return end
  local function trim(value) return tostring(value or ""):match("^%s*(.-)%s*$") end
  local options = { templateId = flow.template.id, appName = trim(binding.project_appName.text),
    packageName = trim(binding.project_packageName.text), themeName = selectedTheme(),
    rootPath = tostring(Bean.Path.app_root_pro_dir), useInternet = binding.project_internet.isChecked(),
    debugMode = binding.project_debug_mode.isChecked(), modules = {} }
  for _, id in ipairs(modules) do
    if binding["module_" .. id].isChecked() then options.modules[#options.modules + 1] = id end
  end
  flow.review(options, binding.project_open_after.isChecked())
end
function onBackPressed()
  if not flow.back() then flow.dispose() host.finish() end
  return true
end
function onOptionsItemSelected(item)
  if item.getItemId() == android.R.id.home then return onBackPressed() end
end
function onDestroy() flow.dispose() end
local root = tostring(Bean.Path.app_root_pro_dir)
flow.initialize(function()
  for i = 1, 1000 do if not File(root .. "/demo" .. i).exists() then return "demo" .. i end end
  return "demo1"
end, function(name)
  updating = true
  lastAutoPkg = "com.neluaj." .. name
  binding.project_appName.setText(name)
  binding.project_packageName.setText(lastAutoPkg)
  updating = false
end)
