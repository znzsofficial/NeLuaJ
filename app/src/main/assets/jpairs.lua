local function iter(a, i)
  if i ~= #a then
    return i + 1, a[i]
  end
end
 
local function jpairs(a)
  return iter, a, 0
end

return jpairs