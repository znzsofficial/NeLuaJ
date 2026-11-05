local bindClass = luajava.bindClass
local JSONArray = bindClass "org.json.JSONArray"
local JSONObject = bindClass "org.json.JSONObject"
local preferences = activity.getSharedPreferences({{packageNameLua}} .. ".checklist", 0)
local M = {}

local function validTitle(title)
  if type(title) ~= "string" or not title:find("%S") then return false end
  local length = utf8.len(title)
  return length ~= nil and length <= 120
end

function M.load()
  local ok, result = pcall(function()
    local raw = preferences.getString("tasks", "[]")
    local array = JSONArray(raw)
    local count = array.length()
    assert(count <= 100, "Too many stored tasks")
    local tasks = {}
    for i = 0, count - 1 do
      local item = array.getJSONObject(i)
      local title = tostring(item.getString("title"))
      assert(validTitle(title), "Invalid task title")
      tasks[#tasks + 1] = { title = title, done = item.getBoolean("done") }
    end
    return tasks
  end)
  if not ok then return nil, result end
  return result
end

function M.save(tasks)
  local ok, result = pcall(function()
    assert(type(tasks) == "table", "Invalid tasks")
    local count = #tasks
    assert(count <= 100, "Too many tasks")
    -- Reject sparse/associative tables rather than silently dropping entries.
    for key in pairs(tasks) do
      assert(type(key) == "number" and key % 1 == 0 and key >= 1 and key <= count,
        "Invalid task index")
    end
    local array = JSONArray()
    for i = 1, count do
      local task = tasks[i]
      assert(type(task) == "table" and validTitle(task.title) and type(task.done) == "boolean",
        "Invalid task")
      local item = JSONObject()
      item.put("title", task.title)
      item.put("done", task.done)
      array.put(item)
    end
    local editor = preferences.edit()
    editor.putString("tasks", tostring(array.toString()))
    return editor.commit()
  end)
  return ok and result == true
end

return M
