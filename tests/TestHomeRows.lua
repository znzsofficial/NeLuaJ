local assets = ASSETS or "app/src/main/assets/"
local Rows = assert(loadfile(assets .. "activities/home/HomeRows.lua"))()
local data, visible, events, builds = {}, {}, {}, 0
local function label(item) return item.id .. ":" .. item.value end
local adapter = {}
adapter.notifyItemRangeChanged = function(start, count)
  events[#events + 1] = { "change", start, count }
  for i = start + 1, start + count do visible[i] = data[i] end
end
adapter.notifyItemRangeRemoved = function(start, count)
  events[#events + 1] = { "remove", start, count }
  for _ = 1, count do table.remove(visible, start + 1) end
end
adapter.notifyItemRangeInserted = function(start, count)
  events[#events + 1] = { "insert", start, count }
  for i = 1, count do table.insert(visible, start + i, data[start + i]) end
end
local fields = { "id", "value" }
local controller = Rows.new(data, adapter, function(row) return row.id end,
  function(a, b) return Rows.same(a, b, fields) end,
  function(row)
    builds = builds + 1
    return { id = row.id, value = row.value, action = function() return label(row) end }
  end)
local function submit(source)
  -- Submissions are detached snapshots, not caller-mutated prior lists.
  local copy = {}
  for i, item in ipairs(source) do copy[i] = { id = item.id, value = item.value } end
  local changed = controller.submit(copy)
  assert(#data == #source and #visible == #source)
  for i, item in ipairs(source) do
    assert(label(data[i]) == label(item) and visible[i] == data[i], "range operations diverged at " .. i)
    assert(data[i].action() == label(item), "cached action refers to old content")
  end
  return changed
end
assert(not submit({}) and #events == 0)
local source = {}
for i = 1, 2000 do source[i] = { id = tostring(i), value = "original" } end
assert(submit(source) and builds == 2000 and #events == 1)
local kept = data[500]
for _ = 1, 20 do assert(not submit(source)) end
assert(builds == 2000 and #events == 1 and data[500] == kept)
source[1000].value = "changed"
assert(submit(source) and builds == 2001 and #events == 2)
assert(events[2][1] == "change" and events[2][2] == 999 and events[2][3] == 1)
assert(data[500] == kept)
table.insert(source, 1, { id = "new", value = "head" }); submit(source)
assert(events[#events][1] == "insert" and events[#events][2] == 0)
table.remove(source, 1); submit(source)
assert(events[#events][1] == "remove" and events[#events][2] == 0)
source[2], source[1999] = source[1999], source[2]; submit(source)
print("PERF HomeRows: 2000 rows x 20 unchanged snapshots -> 0 new bindings / notifications; one edit -> 1 binding / one-row change")

-- Mixed edits, reorders and unequal replacements must still produce valid ranges.
submit({})
source = {}
math.randomseed(714)
local serial = 0
for _ = 1, 500 do
  local op = math.random(4)
  if op == 1 or #source == 0 then
    serial = serial + 1
    table.insert(source, math.random(#source + 1), { id = "random" .. serial, value = "v" })
  elseif op == 2 then table.remove(source, math.random(#source))
  elseif op == 3 then source[math.random(#source)].value = tostring(math.random(100))
  else
    local a, b = math.random(#source), math.random(#source)
    source[a], source[b] = source[b], source[a]
  end
  submit(source)
end
print("ALL-PASS HomeRows deterministic range replay and binding reuse")
