local _M={}

_M.getDimen=function(v)
  return activity.getResources().getDimension(R.dimen[v])
end

return _M