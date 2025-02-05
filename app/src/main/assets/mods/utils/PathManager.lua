local _M = {}
local Bean = Bean

_M.updateFile=function(path)
  Bean.Path.this_file = path
end

_M.updateDir=function(path)
  Bean.Path.this_dir = path
end

return _M