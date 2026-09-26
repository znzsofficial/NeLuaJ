local _M = {}

-- 不要在模块加载时缓存 Bean：environment.lua 可能先 require 本模块，后才初始化 Bean
_M.updateFile = function(path)
  Bean.Path.this_file = path
end

_M.updateDir = function(path)
    -- 切换工程前保存当前工程工作区（打开的文件标签/活动文件/光标）
    pcall(function()
        require("activities.main.Workspace").saveFor(Bean and Bean.Path and Bean.Path.this_dir)
    end)
    pcall(function()
        local ChatUI = require "mods.agent.ChatUI"
        if ChatUI.onBeforeProjectChange then ChatUI.onBeforeProjectChange() end
    end)
    Bean.Path.this_dir = path
    pcall(function()
        local AgentChat = require "mods.agent.AgentChat"
        if AgentChat.syncAgentProjectScope then AgentChat.syncAgentProjectScope() end
    end)
    pcall(function()
        local ChatUI = require "mods.agent.ChatUI"
        if ChatUI.refreshProjectContext then ChatUI.refreshProjectContext() end
    end)
end

return _M
