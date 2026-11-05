local bindClass = luajava.bindClass
local LinearLayout = bindClass "android.widget.LinearLayout"
local CheckBox = bindClass "com.google.android.material.checkbox.MaterialCheckBox"
local Button = bindClass "com.google.android.material.button.MaterialButton"
local Screen = require "app.screen"
local Tasks = require "app.tasks"
local views = Screen.show(require "res.layout.main", res.string.app_title)
local tasks = Tasks.load()

-- A corrupt store is never silently replaced with an empty checklist.
if not tasks then
  views.status.setText(res.string.load_failed)
  views.add.setEnabled(false)
  return
end

local function copyTasks()
  local copy = {}
  for i, task in ipairs(tasks) do
    copy[i] = { title = task.title, done = task.done }
  end
  return copy
end

local render
local function save(nextTasks)
  if not Tasks.save(nextTasks) then
    views.status.setText(res.string.save_failed)
    return false
  end
  tasks = nextTasks
  views.status.setText(res.string.saved)
  render()
  return true
end

render = function()
  views.rows.removeAllViews()
  views.empty.setVisibility(#tasks == 0 and 0 or 8)
  for index, task in ipairs(tasks) do
    local rowViews = {}
    local row = loadlayout({
      LinearLayout, orientation = "vertical", layout_width = "match", layout_height = "wrap",
      layout_marginTop = "12dp", padding = "16dp",
      BackgroundColor = "?attr/colorSurfaceContainerLow",
      { CheckBox, id = "check", text = task.title, checked = task.done,
        textSize = "16sp", textColor = "?attr/colorOnSurface",
        layout_width = "match", layout_height = "wrap", minHeight = "48dp" },
      { Button, id = "delete", text = res.string.delete_action,
        styleAttr = "?attr/borderlessButtonStyle", textSize = "14sp", minHeight = "48dp",
        contentDescription = res.string.delete_task .. task.title,
        layout_width = "wrap", layout_height = "wrap", layout_gravity = "end" },
    }, rowViews)
    views.rows.addView(row)
    local changing = false
    rowViews.check.setOnCheckedChangeListener(function(_, checked)
      if changing then return end
      local nextTasks = copyTasks()
      nextTasks[index].done = checked
      if not save(nextTasks) then
        changing = true
        rowViews.check.setChecked(task.done)
        changing = false
      end
    end)
    rowViews.delete.setOnClickListener(function()
      local nextTasks = copyTasks()
      table.remove(nextTasks, index)
      save(nextTasks)
    end)
  end
end

views.add.setOnClickListener(function()
  local editable = views.task.getText()
  local title = tostring(editable):match("^%s*(.-)%s*$")
  if title == "" then
    views.taskBox.setError(res.string.task_required)
    return
  end
  if utf8.len(title) > 120 then
    views.taskBox.setError(res.string.task_too_long)
    return
  end
  if #tasks >= 100 then
    views.status.setText(res.string.list_full)
    return
  end
  views.taskBox.setError(nil)
  local nextTasks = copyTasks()
  nextTasks[#nextTasks + 1] = { title = title, done = false }
  if save(nextTasks) then views.task.setText("") end
end)

render()
