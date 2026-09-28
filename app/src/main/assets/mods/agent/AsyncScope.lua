--- 异步结果的归属：工程、会话和回合必须同时匹配。
--- 停止任务不改变 generation，因此仍允许保存部分结果；
--- 切换会话或工程后，旧回调即使 generation 没变也不能写入。
local _M = {}

function _M.capture(projectPath, conversationId, generation)
  return {
    projectPath = projectPath,
    conversationId = conversationId,
    generation = generation,
  }
end

function _M.matches(scope, projectPath, conversationId, generation)
  return type(scope) == "table"
    and scope.projectPath == projectPath
    and scope.conversationId == conversationId
    and scope.generation == generation
end

return _M
