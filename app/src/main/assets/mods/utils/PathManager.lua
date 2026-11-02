local _M = {}
local ProjectContext = require "mods.project.ProjectContext"

-- 不要在模块加载时缓存 Bean：environment.lua 可能先 require 本模块，后才初始化 Bean
_M.updateFile = function(path)
  return ProjectContext.setFile(path)
end

_M.updateDir = function(path)
    -- Validate before optional hooks: invalid input must not cancel a live turn.
    local normalized = ProjectContext.normalize(path)
    if normalized:sub(1, 1) ~= "/" then
        error("PathManager.updateDir: directory must be an absolute path: " .. normalized, 2)
    end
    if not (Bean and Bean.Path) then error("PathManager.updateDir: Bean.Path is not initialized", 2) end
    local previous = ProjectContext.snapshot()
    local diagnostics = {}
    local function attempt(stage, callback, allowSkip)
        local ok, result, detail = pcall(callback)
        if not ok or (result == false and (not allowSkip or detail ~= nil)) then
            local message = tostring(not ok and result or detail or "hook returned false")
            diagnostics[#diagnostics + 1] = { stage = stage, message = message }
            print("[PathManager.updateDir] " .. stage .. ": " .. message)
        end
    end
    -- 切换工程前保存当前工程工作区（打开的文件标签/活动文件/光标）
    attempt("workspace.save", function()
        return require("activities.main.Workspace").saveFor(previous.directory)
    end, true)
    attempt("agent.beforeChange", function()
        local ChatUI = require "mods.agent.ChatUI"
        if ChatUI.onBeforeProjectChange then return ChatUI.onBeforeProjectChange() end
    end)
    local current = ProjectContext.setDirectory(normalized)
    attempt("agent.rebind", function()
        local AgentChat = require "mods.agent.AgentChat"
        if AgentChat.syncAgentProjectScope then return AgentChat.syncAgentProjectScope() end
    end)
    attempt("agent.refresh", function()
        local ChatUI = require "mods.agent.ChatUI"
        if ChatUI.refreshProjectContext then return ChatUI.refreshProjectContext() end
    end)
    -- Optional hook failures remain best-effort, but are no longer invisible.
    return current, diagnostics
end

return _M
