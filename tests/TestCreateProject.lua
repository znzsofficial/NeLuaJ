local assets = ASSETS or "app/src/main/assets/"
package.path = assets .. "?.lua;" .. package.path
local Controller = require "activities.projectcreate.Controller"
local function harness()
  local h = { jobs = {}, completions = {}, events = 0, alive = true, writes = 0 }
  local function result(options)
    return { ok = true, config = options, projectPath = "/Projects/" .. options.appName,
      files = { { path = "main.lua" } }, permissions = {} }
  end
  h.state = Controller.new {
    alive = function() return h.alive end,
    changed = function() h.events = h.events + 1 end,
    task = function(work, callback, dispatcher)
      assert(dispatcher == "io")
      if h.launchFailure then error("cannot launch") end
      h.jobs[#h.jobs + 1] = { work = work, callback = callback }
      return { cancel = function() error("writer must not be cancelled") end }
    end,
    generator = {
      preview = function(options)
        if h.previewFailure then return { ok = false, phase = "validate", message = "invalid" } end
        return result(options)
      end,
      generate = function(options)
        h.writes = h.writes + 1
        if h.throwGenerate then error("write failed") end
        if h.generateFailure then return { ok = false, phase = "write", stagingPath = "/stage", cleanupError = "cleanup" } end
        return result(options)
      end,
    },
    complete = function(value, openAfter) h.completions[#h.completions + 1] = { value, openAfter } end,
  }
  function h.run()
    local job = table.remove(h.jobs, 1)
    assert(job)
    job.result = job.work()
    job.callback(job.result)
    return job
  end
  return h
end
local function options()
  return { appName = "demo", templateId = "form", modules = { "time" } }
end
local function selected()
  local h = harness()
  assert(h.state.page == "templates")
  assert(h.state.select({ id = "form" }))
  assert(h.state.page == "configuration")
  return h
end
-- Preview and generation capture detached config; duplicate callbacks are inert.
local h = selected()
local input = options()
h.state.review(input, true)
input.appName, input.modules[1] = "changed", "array"
assert(h.state.busy and #h.jobs == 1)
assert(not h.state.select({ id = "blank" }))
local previewJob = h.run()
assert(h.state.preview.config.appName == "demo")
assert(h.state.options.modules[1] == "time")
local events = h.events
previewJob.callback(previewJob.result)
assert(h.events == events)
h.state.create()
h.state.create()
assert(#h.jobs == 1)
local writeJob = h.run()
assert(h.writes == 1 and #h.completions == 1 and h.completions[1][2] == true)
writeJob.callback(writeJob.result)
assert(#h.completions == 1)

-- Editing or selecting another template requires a new inline review.
h = selected()
h.state.review(options(), false)
h.run()
assert(h.state.preview)
assert(h.state.edit())
assert(not h.state.preview)
h.state.create()
assert(#h.jobs == 0)
assert(h.state.back() and h.state.page == "templates")
assert(not h.state.back())
assert(h.state.select({ id = "webview" }))
assert(not h.state.preview)

-- Navigate away while preview runs; late delivery must not overwrite the new page.
h = selected()
h.state.review(options(), false)
assert(h.state.back())
assert(not h.state.busy and h.state.page == "templates")
h.state.select({ id = "blank" })
events = h.events
h.run()
assert(h.events == events and h.state.template.id == "blank" and not h.state.preview)

-- Finishing/destroyed hosts suppress UI effects while the write still completes.
for _, detached in ipairs({ "destroyed", "finishing" }) do
  h = selected()
  h.state.review(options(), false)
  h.run()
  h.state.create()
  assert(not h.state.back(), "Back exits a running writer without cancelling it")
  if detached == "destroyed" then h.state.dispose() else h.alive = false end
  events = h.events
  h.run()
  assert(h.writes == 1 and #h.completions == 0 and events == h.events)
end

-- Errors recover on the same page, including worker launch failures and cleanup details.
h = selected()
h.previewFailure = true
h.state.review(options(), false)
h.run()
assert(not h.state.busy and h.state.error.phase == "validate" and not h.state.preview)
h.previewFailure = false
h.state.review(options(), false)
h.run()
h.generateFailure = true
h.state.create()
h.run()
assert(not h.state.busy and h.state.error.cleanupError == "cleanup" and not h.state.preview)
h.generateFailure = false
h.state.review(options(), false)
h.run()
h.throwGenerate = true
h.state.create()
h.run()
assert(not h.state.busy and tostring(h.state.error):find("write failed"))
h.launchFailure = true
h.state.review(options(), false)
assert(not h.state.busy and tostring(h.state.error):find("cannot launch"))

-- Default-name lookup has the same lifecycle guard.
h = harness()
local applied = false
h.state.initialize(function() return "demo2" end, function() applied = true end)
h.state.dispose()
h.run()
assert(not applied)
h = selected()
h.state.review(options(), false)
h.run()
h.state.create()
h.run()
assert(h.completions[1][2] == false)

-- Legacy callers keep show(deps), but no function crosses the Activity boundary.
local route, arguments
package.loaded["mods.utils.ActivityUtil"] = { open = function(name, ...)
  route, arguments = name, select("#", ...)
  return true
end }
assert(require("activities.main.CreateProject").show({ openProject = function() error("local callback") end }))
assert(route == "project_create" and arguments == 0)

-- Assemble the real Activity and shared layout with host doubles, then drive
-- selection -> review -> edit -> review -> creation through actual UI handlers.
local views, jobs, returned, finished, tree = {}, {}, nil, false, nil
local reviewed
local function field(node)
  local view = { text = node.text or "", checked = node.checked == true, visibility = node.visibility }
  function view.setText(text)
    view.text = text
    if view.watcher then view.watcher.afterTextChanged(text) end
  end
  function view.setChecked(value)
    if view.checked == value then return end
    view.checked = value
    if view.listener then view.listener(view, value) end
  end
  function view.isChecked() return view.checked end
  function view.setVisibility(value) view.visibility = value end
  function view.setEnabled(value) view.enabled = value end
  function view.setOnCheckedChangeListener(fn) view.listener = fn end
  function view.setAdapter(adapter) view.adapter = adapter end
  function view.setSelection(position)
    view.position = position
    if view.selectionListener then view.selectionListener.onItemSelected(view, nil, position, position) end
  end
  function view.getSelectedItemPosition() return view.position or -1 end
  function view.setOnItemSelectedListener(listener) view.selectionListener = listener end
  function view.addTextChangedListener(watcher) view.watcher = watcher end
  function view.post(fn) fn() end
  function view.fullScroll() view.scrolled = true end
  view.onClick = node.onClick
  return view
end
local ids = setmetatable({}, { __index = function(_, key) return key end })
local fakeR = { style = ids, attr = ids } -- Creator previews must not look up drawable resources.
luajava = { bindClass = function(name)
  if name:match("%.R$") then return fakeR end
  if name == "android.text.TextWatcher" or name == "android.graphics.drawable.ColorDrawable" then
    return function(value) return value end
  end
  if name == "java.io.File" then return function() return { exists = function() return false end } end end
  if name == "android.widget.Toast" then
    return { LENGTH_LONG = 1, makeText = function() return { show = function() end } end }
  end
  if name == "android.widget.ArrayAdapter" then
    return function(_, resource)
      assert(resource == "simple_spinner_item")
      local adapter = { items = {} }
      function adapter.add(text) adapter.items[#adapter.items + 1] = text end
      function adapter.setDropDownViewResource(value)
        assert(value == "simple_spinner_dropdown_item")
        adapter.dropdownResource = value
      end
      return adapter
    end
  end
  return name
end }
_G["import"] = function(name) _G[name:match("([^%.]+)$")] = name end
for _, name in ipairs({ "android.widget.LinearLayout", "android.widget.ScrollView", "android.widget.Spinner",
    "com.google.android.material.textview.MaterialTextView", "com.google.android.material.chip.Chip",
    "com.google.android.material.chip.ChipGroup", "com.google.android.material.materialswitch.MaterialSwitch" }) do
  local class = name
  package.preload[class] = function() return class end
end
local colors = setmetatable({}, { __index = function() return function() return 1 end end })
activity = { themeUtil = colors,
  isFinishing = function() return finished end, isDestroyed = function() return false end,
  setTheme = function() end, dynamicColor = function() end,
  setTitle = function(value) assert(value == "create_project") end,
  setContentView = function() end,
  getSupportActionBar = function()
    return { setElevation = function() end, setBackgroundDrawable = function() end,
      setDisplayShowTitleEnabled = function() end, setDisplayHomeAsUpEnabled = function() end }
  end,
  finish = function() finished = true end,
  getWindow = function() return { setSoftInputMode = function() end } end,
}
this, Bean = activity, { Path = { app_root_pro_dir = "/Projects" } }
android = { R = { id = { home = 1 }, layout = ids } }
res = { string = ids, layout = {} }
package.loaded["mods.bootstrap"] = true
package.loaded["mods.utils.SystemBars"] = { apply = function() end }
package.loaded["mods.utils.ActivityUtil"] = { finishWith = function(action, path) returned = { action, path } end }
package.loaded["mods.project.templates.Generator"] = {
  preview = function(options)
    reviewed = options
    return { ok = true, config = options, projectPath = "/Projects/" .. options.appName,
      files = { { path = "main.lua" } }, permissions = {} }
  end,
  generate = function(options)
    return { ok = true, config = options, projectPath = "/Projects/" .. options.appName }
  end,
}
res.layout.new_project = assert(loadfile(assets .. "res/layout/new_project.lua"))()
loadlayout = function(layout, binding)
  tree = layout
  local function walk(node)
    if node.id then binding[node.id] = field(node) end
    for _, child in ipairs(node) do if type(child) == "table" then walk(child) end end
  end
  walk(layout)
  views = binding
  return {}
end
xTask = function(work, callback, dispatcher)
  assert(dispatcher == "io")
  jobs[#jobs + 1] = function() callback(work()) end
end
assert(loadfile(assets .. "activities/projectcreate/CreateProjectActivity.lua"))()
assert(#jobs == 1)
table.remove(jobs, 1)()
assert(views.templates.visibility == 0 and views.footer.visibility == 8)
local choices = {}
local function findChoices(node)
  assert(node[1] ~= "android.widget.ImageView", "Use actual View previews, not illustrations")
  if node.contentDescription and node.onClick then choices[#choices + 1] = node end
  for _, child in ipairs(node) do if type(child) == "table" then findChoices(child) end end
end
findChoices(tree)
assert(#choices == 6)
local ProjectTheme = require "mods.utils.ProjectTheme"
for _, option in ipairs(ProjectTheme.CREATE_CHIPS) do assert(not views[option.chip]) end
assert(views.module_time and views.module_vconsole, "Module Chips remain available")
assert(#views.project_theme_family.adapter.items == 4 and #views.project_titlebar.adapter.items == 2)
for _, choice in ipairs(choices) do
  local panel
  for _, child in ipairs(choice[2]) do
    if type(child) == "table" and child.importantForAccessibility == 4 then
      assert(not panel, "Each template has one preview")
      panel = child
    end
  end
  assert(panel and panel[1] == "android.widget.LinearLayout" and #panel >= 2)
  assert(panel.layout_width == "match" and panel.layout_height == "wrap")
  assert(panel.clickable == false and panel.focusable == false and panel.importantForAccessibility == 4)
  for _, child in ipairs(panel) do
    if type(child) == "table" then
      assert(not child.onClick and not child.focusable and not child.clickable)
      if child[1]:find("CheckBox") or child[1]:find("SwitchCompat") then
        assert(child.clickable == false and child.focusable == false)
      end
    end
  end
end
-- Exercise every dropdown combination on the blank template: exact legacy
-- theme values and generator flags must survive the new presentation.
choices[1].onClick()
assert(views.project_template_summary.text == "template_blank_title")
assert(views.project_template_description.text == "template_blank_description")
for family = 0, 3 do
  for titlebar = 0, 1 do
    views.project_theme_family.setSelection(family)
    views.project_titlebar.setSelection(titlebar)
    assert(views.review.visibility == 8, "Changing either dropdown invalidates the review")
    views.primary.onClick()
    assert(#jobs == 1 and not views.project_theme_family.enabled and not views.project_titlebar.enabled)
    table.remove(jobs, 1)()
    assert(reviewed.themeName == ProjectTheme.CREATE_CHIPS[family * 2 + titlebar + 1].value)
    assert(ProjectTheme.hasSystemActionBar(reviewed.themeName) == (titlebar == 1))
    assert(ProjectTheme.isDynamic(reviewed.themeName) == (family == 1))
    assert(ProjectTheme.isMaterialComponent(reviewed.themeName) == (family == 2))
    assert(ProjectTheme.isCompat(reviewed.themeName) == (family == 3))
    -- Android may deliver the initial/same-position callback after setup.
    views.project_theme_family.setSelection(family)
    views.project_titlebar.setSelection(titlebar)
    assert(views.review.visibility == 0, "Repeated selection callbacks must preserve the review")
  end
end
views.project_change_template.onClick()
choices[2].onClick()
assert(views.configuration.visibility == 0 and views.templates.visibility == 8)
assert(views.project_theme_family.getSelectedItemPosition() == 3)
views.primary.onClick()
assert(#jobs == 0 and views.project_error.text == "project_theme_incompatible")
assert(views.project_titlebar.getSelectedItemPosition() == 1, "Unsupported choice must be preserved")
views.project_theme_family.setSelection(0)
assert(views.project_error.visibility == 8)
views.primary.onClick()
assert(not views.primary.enabled and views.progress.visibility == 0)
table.remove(jobs, 1)()
assert(views.review.visibility == 0 and views.configuration.scrolled)
assert(views.primary.text == "create_project")
views.project_appName.setText("edited")
assert(views.review.visibility == 8 and views.primary.text == "project_review")
views.primary.onClick()
table.remove(jobs, 1)()
views.primary.onClick()
table.remove(jobs, 1)()
assert(finished and returned[1] == "open_project" and returned[2] == "/Projects/edited")
print("ALL-PASS TestCreateProject")
