local _M = {}

-- 不要在模块加载时缓存 Bean：environment.lua 可能先 require 本模块，后才初始化 Bean
_M.updateFile = function(path)
  Bean.Path.this_file = path
end

_M.updateDir = function(path)
  Bean.Path.this_dir = path
  pcall(function()
    local ChatUI = require "mods.agent.ChatUI"
    if ChatUI.refreshProjectContext then ChatUI.refreshProjectContext() end
  end)
  pcall(function()
    local AgentChat = require "mods.agent.AgentChat"
    if AgentChat.syncAgentProjectScope then AgentChat.syncAgentProjectScope() end
  end)
end

return _M
