--- UI-thread submissions for small/medium home lists. Sources are detached,
--- immutable snapshots; keys must be unique. No Views, timers, disk or Android IO.
local M = {}

function M.same(left, right, fields)
  for _, field in ipairs(fields) do
    if left[field] ~= right[field] then return false end
  end
  return true
end

function M.new(data, adapter, keyOf, same, make)
  local previous, cache = {}, {}
  return { submit = function(rows)
    local equal = #previous == #rows
    if equal then
      for i, row in ipairs(rows) do
        if keyOf(previous[i]) ~= keyOf(row) or not same(previous[i], row) then equal = false break end
      end
    end
    if equal then previous = rows return false end

    local nextData, nextCache = {}, {}
    for i, row in ipairs(rows) do
      local key = keyOf(row)
      local old = cache[key]
      local item = old and same(old.source, row) and old.item or make(row)
      nextData[i], nextCache[key] = item, { source = row, item = item }
    end
    -- Keep unchanged edges, and update one contiguous middle. Reorders are
    -- replacements, not animated moves; this deliberately is not a full DiffUtil.
    local oldCount, newCount, prefix, suffix = #data, #nextData, 0, 0
    while prefix < math.min(oldCount, newCount) and data[prefix + 1] == nextData[prefix + 1] do prefix = prefix + 1 end
    while suffix < math.min(oldCount, newCount) - prefix and
      data[oldCount - suffix] == nextData[newCount - suffix] do suffix = suffix + 1 end
    local removed, inserted = oldCount - prefix - suffix, newCount - prefix - suffix
    for i = oldCount, 1, -1 do data[i] = nil end
    for i, item in ipairs(nextData) do data[i] = item end
    previous, cache = rows, nextCache
    if removed == inserted then
      if inserted > 0 then adapter.notifyItemRangeChanged(prefix, inserted) end
    else
      if removed > 0 then adapter.notifyItemRangeRemoved(prefix, removed) end
      if inserted > 0 then adapter.notifyItemRangeInserted(prefix, inserted) end
    end
    return true
  end }
end

return M
