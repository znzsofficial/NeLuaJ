local _M = {}
local Bean = Bean

_M.update_this_file=function(path)
  Bean.Path.this_file = path
end

_M.update_this_dir=function(path)
  Bean.Path.this_dir = path
end

return _M