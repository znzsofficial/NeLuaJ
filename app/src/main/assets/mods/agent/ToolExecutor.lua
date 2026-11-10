--- Agent 工具执行边界。
--- 具体文件算法通过 configure 注入，避免执行层依赖 AgentChat 的全局状态。
local _M = {}
local ToolRegistry = require("mods.agent.ToolRegistry")
local FileMutationService = require("mods.files.FileMutationService")
local config
local tasks = require('mods.agent.TaskRegistry').new()
local activeJobs = {} -- Only live jobs; callbacks capture their own cancellation state.
local AgentJobRegistry = nil
pcall(function()
  AgentJobRegistry = luajava.bindClass("com.nekolaska.agent.AgentJobRegistry")
end)
-- 进程级标记：模型是否已读过沙盒文档（run_lua 自动运行的前置条件）
local sandboxDocRead = false

local aliases = {
  read = "read_file", readfile = "read_file", file_read = "read_file",
  read_many = "read_files", read_multiple = "read_files",
  list = "list_dir", list_files = "list_dir", list_directory = "list_dir",
  read_directory = "list_dir", list_tree = "list_dir", tree = "list_dir",
  mkdir = "create_folder", create_directory = "create_folder",
  delete = "delete_file", remove_file = "delete_file", delete_directory = "delete_folder",
  write_file = "create_file", edit_file = "apply_patch", modify_file = "apply_patch", patch = "apply_patch",
  replace = "replace_in_file", replace_text = "replace_in_file", string_replace = "replace_in_file",
  append = "append_file", append_text = "append_file", append_to_file = "append_file",
  rename = "rename_file", move = "rename_file", move_file = "rename_file",
  env = "get_env_info", environment = "get_env_info", env_info = "get_env_info", system_info = "get_env_info",
  run = "run_lua", execute = "run_lua", eval = "run_lua", run_lua_code = "run_lua",
  execute_code = "run_lua", run_code = "run_lua",
  check_syntax = "check_lua_syntax", syntax_check = "check_lua_syntax",
  fetch = "fetch_url", web_fetch = "fetch_url", read_url = "fetch_url", http_get = "fetch_url",
  todo = "update_todos", todos = "update_todos", todo_write = "update_todos",
  update_todo = "update_todos", write_todos = "update_todos",
  build = "build_project", build_apk = "build_project", package = "build_project", package_project = "build_project",
  subtask = "run_subtask", delegate = "run_subtask", dispatch_task = "run_subtask",
  run_agent = "run_subtask", spawn_agent = "run_subtask",
}

function _M.configure(options)
  config = options or {}
  tasks.configure(config)
end

local function requireConfig()
  if not config then error("ToolExecutor 未配置") end
  return config
end

local function freezeFileArgs(name, args)
  local frozen = {}
  for key, value in pairs(args or {}) do frozen[key] = value end
  local resolve = requireConfig().resolvePath
  if not resolve or name:match("^mcp::") or name:match("^mcp__") then return frozen end
  frozen.__agent_scope = requireConfig().getProjectScope and requireConfig().getProjectScope()
  if frozen.path and frozen.path ~= "" then
    if name == "read_file" and requireConfig().resolveReadPath then
      frozen.path = requireConfig().resolveReadPath(frozen.path)
    else
      frozen.path = resolve(frozen.path)
    end
  end
  if frozen.new_path and frozen.new_path ~= "" then frozen.new_path = resolve(frozen.new_path) end
  if name == "read_files" then
    local paths = frozen.paths
    if type(paths) == "string" then paths = { paths } end
    if type(paths) == "table" then
      frozen.paths = {}
      for _, path in ipairs(paths) do
        local resolved = requireConfig().resolveReadPath and requireConfig().resolveReadPath(path) or resolve(path)
        frozen.paths[#frozen.paths + 1] = resolved
      end
    end
  end
  -- 沙盒文档前置读取的执行器侧记录：模型读过 res/doc 下的 sandbox_*.html
  -- 后才允许 run_lua 自动运行（见 requiresConfirmation/shouldAutoApprove）
  if not sandboxDocRead and (name == "read_file" or name == "read_files") then
    local isSandboxDocPath = requireConfig().isSandboxDocPath
    if isSandboxDocPath then
      pcall(function()
        if name == "read_file" then
          sandboxDocRead = sandboxDocRead or isSandboxDocPath(frozen.path)
        else
          for _, path in ipairs(frozen.paths or {}) do
            sandboxDocRead = sandboxDocRead or isSandboxDocPath(path)
          end
        end
      end)
    end
  end
  return frozen
end

function _M.normalizeToolName(name, args)
  name = tostring(name or ""):match("^%s*(.-)%s*$")
  name = name:gsub("^tools[%.:]", "")
    :gsub("^function[%.:]", "")
    :gsub("^functions[%.:]", "")
    :gsub("^tool[%.:]", "")
  if name:match("^mcp::") or name:match("^mcp__") then return name end
  name = name:gsub("^.*__", "")
    :gsub("([a-z0-9])([A-Z])", "%1_%2"):lower()
  name = aliases[name] or name
  if name == "" and type(args) == "table" then
    if args.patch then name = "apply_patch"
    elseif args.old and args.path then name = "replace_in_file"
    elseif args.code then name = "run_lua"
    elseif args.url then name = "fetch_url"
    elseif args.pattern then name = "search_in_files"
    elseif args.paths then name = "read_files"
    elseif args.path and args.new_path then name = "rename_file"
    elseif args.content then name = "create_file"
    elseif args.todos then name = "update_todos"
    elseif args.task then name = "run_subtask"
    elseif args.path then name = "read_file" end
  end
  return name
end

function _M.executeTool(name, args)
  name = _M.normalizeToolName(name, args)
  local definition = ToolRegistry.get(name)
  if definition and definition.fileMutation then return FileMutationService.execute(name, args) end
  if name:match("^mcp::") or name:match("^mcp__") then
    local route = requireConfig().resolveMcpTool and requireConfig().resolveMcpTool(name)
    local ns, tool = name:sub(6):match("^([^:]+)::(.+)$")
    if route then tool = route.tool end
    if not tool or (not route and not ns) then return "MCP 工具名格式错误: " .. name, false end
    local server = route and route.server or requireConfig().findMcpServer(ns)
    if not server then return "找不到 MCP 服务器: " .. ns, false end
    local text, err = requireConfig().callMcpTool(server, tool, args)
    if text then return text, true end
    return "MCP 工具调用失败: " .. tostring(err or "未知错误"), false
  end
  local platformExecute = requireConfig().platformExecute
  if not platformExecute then return "工具平台执行器未配置: " .. tostring(name), false end
  if args and args.__agent_scope and requireConfig().getProjectScope
      and args.__agent_scope ~= requireConfig().getProjectScope() then
    return "项目已切换，文件操作未执行", false
  end
  local executeArgs = args or {}
  -- 平台执行器约定：第二个返回值 ok ∈ {true, false, nil}，nil 表示旧式工具未提供结构化状态，
  -- 此时调用方回退到文本嗅探。
  local called, result, ok, effects = pcall(platformExecute, name, executeArgs)
  if not called then result, ok = "工具执行异常: " .. tostring(result), false end
  return result, ok, effects
end

-- All lifecycle callbacks, cancellation and timer callbacks run on the owner
-- (Android main) thread. scheduleTimeout must post to that same thread.
function _M.executeToolAsync(name, args, onResult, options)
  local ownerConfig=config or {}
  local function onOwner(fn)
    if ownerConfig.isOwnerThread and not ownerConfig.isOwnerThread() then
      assert(ownerConfig.postToOwner,'postToOwner 未配置')
      ownerConfig.postToOwner(fn)
    else fn() end
  end
  assert(not ownerConfig.isOwnerThread or ownerConfig.isOwnerThread(),'ToolExecutor requires owner thread')
  options = options or {}
  name = _M.normalizeToolName(name, args)
  local definition = ToolRegistry.get(name)
  local file = not not (definition and definition.fileMutation)
  local id = tasks.create(name, options, file)
  -- Retain metadata only, so a late child file event can still identify its
  -- parent after bounded registry history evicts that parent.
  local parentInfo = name=='run_subtask' and tasks.snapshot(id) or nil
  local function parentSnapshot()
    parentInfo=tasks.snapshot(id) or parentInfo
    local out={}
    for key,value in pairs(parentInfo or {}) do
      if type(value)=='table' then
        out[key]={}; for k,v in pairs(value) do out[key][k]=v end
      else out[key]=value end
    end
    return out
  end
  local handle = {taskId=id}
  local job, timer, timerCleared, completed, stopped, cancelledUnderlying, registered
  local function clearTimer()
    timerCleared=true
    if timer then local cancel=timer; timer=nil; pcall(cancel) end
  end
  local function unregister()
    if registered then
      registered=false
      pcall(function() AgentJobRegistry.unregister(job) end)
    end
  end
  local function cancelUnderlying()
    if not job or cancelledUnderlying then return end
    cancelledUnderlying=true
    unregister()
    if file then pcall(FileMutationService.cancel,job)
    else pcall(function() if job.cancel then job.cancel() end end) end
  end
  local function finish(text, ok, effects)
    if completed then return end
    completed=true
    if file and type(effects)=='table' then tasks.transaction(id,effects.transactionId) end
    clearTimer(); unregister(); activeJobs[handle]=nil
    tasks.settle(id,ok)
    if parentInfo then parentSnapshot() end
    if onResult and (file or not stopped) then pcall(onResult,text,ok,effects,tasks.snapshot(id)) end
  end
  local function stop(state,reason)
    if completed or stopped then return false end
    stopped=true
    tasks.endWait(id,state,reason)
    clearTimer()
    local info=tasks.snapshot(id)
    if parentInfo then parentSnapshot() end
    if not file then activeJobs[handle]=nil; tasks.retire(id) end
    -- Mark first: cancel may synchronously invoke the final callback.
    if name=='run_subtask' and ownerConfig.cancelSubtask then pcall(ownerConfig.cancelSubtask,id) end
    cancelUnderlying()
    if state=='timed_out' then
      if options.onWaitEnd then pcall(options.onWaitEnd,info)
      elseif not file and onResult then pcall(onResult,'工具等待超时；执行结果未确认',false,nil,info) end
    end
    return true
  end
  handle.cancel=function(reason)
    assert(not ownerConfig.isOwnerThread or ownerConfig.isOwnerThread(),'cancel requires owner thread')
    return stop('cancelled',reason or 'cancelled')
  end
  handle.getSnapshot=function() return tasks.snapshot(id) end
  activeJobs[handle]=true
  local launched,err=pcall(function()
    local cfg=requireConfig()
    local timeout=options.timeoutMs or
      (name=='run_subtask' and 190000 or name=='build_project' and 300000 or cfg.defaultTimeoutMs or 120000)
    assert(type(timeout)=='number' and timeout>0,'invalid timeoutMs')
    assert(type(cfg.scheduleTimeout)=='function','scheduleTimeout 未配置')
    local cancel=cfg.scheduleTimeout(timeout,function() onOwner(function() stop('timed_out','timeout') end) end)
    assert(type(cancel)=='function','scheduleTimeout 必须返回 cancelFn')
    timer=cancel
    if timerCleared then clearTimer() end
    if stopped then return end
    tasks.running(id)
    if file then
      job=FileMutationService.submit(name,args,function(text,ok,effects)
        onOwner(function() finish(text,ok,effects) end)
      end)
      if job then tasks.transaction(id,(job.result and job.result.transactionId) or job.id) end
    elseif name:match('^mcp::') or name:match('^mcp__') then
      local route=cfg.resolveMcpTool and cfg.resolveMcpTool(name)
      local ns,tool=name:sub(6):match('^([^:]+)::(.+)$')
      if route then tool=route.tool end
      assert(tool and (route or ns),'MCP 工具名格式错误')
      local server=route and route.server or cfg.findMcpServer(ns)
      assert(server,'找不到 MCP 服务器')
      job=cfg.callMcpToolAsync(server,tool,args,function(ok,text)
        onOwner(function() finish(ok and text or ('MCP 工具调用失败: '..tostring(text or '未知错误')),ok) end)
      end)
    else
      local frozen=freezeFileArgs(name,args)
      if name=='run_subtask' then
        frozen.__task_context={taskId=id,scope=parentSnapshot().scope,
          onLateFileResult=function(text,ok,fileResult,childTaskInfo)
            onOwner(function()
              if options.onLateFileResult then
                pcall(options.onLateFileResult,text,ok,fileResult,childTaskInfo,parentSnapshot())
              end
            end)
          end}
      end
      job=xTask(function()
        -- No registry/entry reads or writes from the worker.
        local ok,result,flag,effects=pcall(_M.executeTool,name,frozen)
        return {ok=ok,result=result,toolOk=flag,effects=effects}
      end,function(result)
        onOwner(function()
          if type(result)~='table' then finish('后台任务异常: '..tostring(result),false)
          elseif result.ok then finish(result.result,result.toolOk,result.effects)
          else finish('工具执行异常: '..tostring(result.result),false) end
        end)
      end,'io')
    end
    if stopped then cancelUnderlying() end
    if not completed and not stopped then
      assert(job,'工具启动未返回 handle')
      if AgentJobRegistry and not file then
        local ok=pcall(function() AgentJobRegistry.register(job,name) end)
        registered=ok
      end
    end
  end)
  if not launched then finish('无法启动后台工具任务: '..tostring(err),false) end
  return handle
end

function _M.getTaskSnapshot(id) return tasks.snapshot(id) end
function _M.getTaskDiagnostics() return tasks.diagnostics() end
function _M.cancelJob(handle,reason)
  if not handle or not activeJobs[handle] then return false end
  return handle.cancel(reason)
end
local function cancelMatching(scope,reason)
  local batch={}
  for handle in pairs(activeJobs) do
    local match=true
    if scope then
      local info=tasks.snapshot(handle.taskId)
      for _,key in ipairs({'projectPath','conversationId','generation'}) do
        if scope[key]~=nil and (not info or info.scope[key]~=scope[key]) then match=false end
      end
    end
    if match then batch[#batch+1]=handle end
  end
  local count=0
  for _,handle in ipairs(batch) do if _M.cancelJob(handle,reason) then count=count+1 end end
  return count
end
function _M.cancelScope(scope,reason) return cancelMatching(scope or {},reason or 'scope') end
function _M.cancelPending() return cancelMatching(nil,'cancelled')>0 end

function _M.isDestructiveTool(name)
  name = _M.normalizeToolName(name)
  if name:match("^mcp::") or name:match("^mcp__") then return true end
  local entry = ToolRegistry.get(name)
  return entry ~= nil and entry.destructive == true
end

function _M.isInProjectDir(path)
  if not path or path == "" then return true end
  local original = tostring(path)
  local projectDir = requireConfig().getProjectDir()
  if not projectDir or projectDir == "" then return false end
  local canonicalize = requireConfig().canonicalPath or requireConfig().normalizePath
  local resolved = canonicalize(path)
  local projectNorm = canonicalize(projectDir)
  if not projectNorm or projectNorm == "" then return false end
  -- A missing relative path may be resolved by the legacy reader from the IDE
  -- asset directory, so it must not receive project-local auto approval.
  if original:sub(1, 1) ~= "/" and requireConfig().getPathType
      and not requireConfig().getPathType(resolved) then return false end
  if resolved:sub(1, #projectNorm) ~= projectNorm then return false end
  return #resolved == #projectNorm or resolved:sub(#projectNorm + 1, #projectNorm + 1) == "/"
end

local function allPathsInProject(name, args)
  args = args or {}
  local entry = ToolRegistry.get(name)
  local function readPathAllowed(path)
    if _M.isInProjectDir(path) then return true end
    local trusted = requireConfig().isTrustedReadPath
    return entry and entry.trustedDocs and trusted and trusted(path) == true or false
  end
  if name == "read_files" then
    local paths = args.paths
    if type(paths) == "string" then paths = { paths } end
    if type(paths) ~= "table" or #paths == 0 then return false end
    for _, path in ipairs(paths) do if not readPathAllowed(path) then return false end end
    return true
  end
  if name == "read_file" then return readPathAllowed(args.path or "") end
  return _M.isInProjectDir(args.path or "")
end

function _M.normalizeNetworkHosts(value)
  if value == nil then return {} end
  if type(value) == "string" then
    local host = value:match("^%s*(.-)%s*$")
    return host ~= "" and { host } or {}
  end
  if type(value) ~= "table" then return nil, "network_hosts 必须是字符串数组" end
  local count = 0
  for key, host in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or type(host) ~= "string" then
      return nil, "network_hosts 必须是连续的字符串数组"
    end
    count = count + 1
  end
  local hosts = {}
  for index = 1, count do
    local host = value[index]
    if type(host) ~= "string" then return nil, "network_hosts 必须是连续的字符串数组" end
    host = host:match("^%s*(.-)%s*$")
    if host ~= "" then hosts[#hosts + 1] = host end
  end
  return hosts
end

local function isNetworkRequest(name, args)
  if name:match("^mcp::") or name:match("^mcp__") or name == "fetch_url" then return true end
  if name ~= "run_lua" then return false end
  local hosts = _M.normalizeNetworkHosts(args and (args.network_hosts or args.networkHosts))
  return hosts and #hosts > 0 or false
end

local function autoApprovesNetworkRequests()
  return requireConfig().getSharedData("ai_auto_approve_network", "1") == "1"
end

local function autoRunsSandbox()
  return requireConfig().getSharedData("ai_auto_run_sandbox", "1") == "1"
end

local function hostAllowedByPolicy(host, allow)
  host = tostring(host):lower()
  for _, pattern in ipairs(allow) do
    pattern = tostring(pattern):lower()
    if host == pattern then return true end
    local suffix = "." .. pattern
    if #host > #suffix and host:sub(-#suffix) == suffix then return true end
  end
  return false
end

-- 项目 allowlist（policy.networkHosts 非空时生效）：fetch_url 的目标主机与
-- run_lua 声明的每个 network_hosts 都必须命中名单（精确或子域）。
-- 未配置名单则完全沿用全局开关；项目策略只能收紧，不能放大全局授权。
local function networkAllowedByPolicy(name, args)
  local getPolicy = requireConfig().getProjectPolicy
  if not getPolicy then return true end
  local ok, policy = pcall(getPolicy)
  if not ok or type(policy) ~= "table" then return true end
  if type(policy.networkHosts) ~= "table" or #policy.networkHosts == 0 then return true end
  if name == "fetch_url" then
    local host = tostring((args or {}).url or ""):match("^https?://([^/:]+)")
    if not host then return false end
    return hostAllowedByPolicy(host, policy.networkHosts)
  end
  if name == "run_lua" then
    local hosts = _M.normalizeNetworkHosts(args and (args.network_hosts or args.networkHosts))
    if not hosts then return false end
    for _, host in ipairs(hosts) do
      if not hostAllowedByPolicy(host, policy.networkHosts) then return false end
    end
  end
  return true
end

local function projectAutoApproveBlocked()
  local getPolicy = requireConfig().getProjectPolicy
  if not getPolicy then return false end
  local ok, policy = pcall(getPolicy)
  return ok and type(policy) == "table" and policy.autoApprove == false or false
end

--- 沙盒文档是否已被读过（run_lua 自动运行的前置条件；进程级）
function _M.hasReadSandboxDoc()
  return sandboxDocRead
end

function _M.setSandboxDocRead(value)
  sandboxDocRead = (value == true)
end

function _M.requiresConfirmation(name, args)
  name = _M.normalizeToolName(name, args)
  local entry = ToolRegistry.get(name)
  local category = entry and entry.approval
  -- 用户配置：MCP 不需要任何确认，直接执行
  --（副作用未知由用户自担；项目 networkHosts 也不约束 MCP 服务器）
  if name:match("^mcp::") or name:match("^mcp__") then return false end
  if category == "always_confirm" then return true end
  if category == "sandbox" then
    if not autoRunsSandbox() then return true end
    if not sandboxDocRead then return true end
    if not isNetworkRequest(name, args) then return false end
    return not (autoApprovesNetworkRequests() and networkAllowedByPolicy(name, args))
  end
  if category == "network" then
    return not (autoApprovesNetworkRequests() and networkAllowedByPolicy(name, args))
  end
  if _M.isDestructiveTool(name) then return true end
  if category == "project_read" then
    return not allPathsInProject(name, args)
  end
  return false
end

function _M.shouldAutoApprove(name, args)
  name = _M.normalizeToolName(name, args)
  local entry = ToolRegistry.get(name)
  local category = entry and entry.approval
  -- 用户配置：MCP 不需要任何确认，无条件自动执行
  if name:match("^mcp::") or name:match("^mcp__") then return true end
  if category == "sandbox" then
    if not autoRunsSandbox() then return false end
    if not sandboxDocRead then return false end
    if not isNetworkRequest(name, args) then return true end
    return autoApprovesNetworkRequests() and networkAllowedByPolicy(name, args)
  end
  if category == "network" then
    return autoApprovesNetworkRequests() and networkAllowedByPolicy(name, args)
  end
  if category == "always_confirm" then return false end
  if category == "pure" then return true end
  if category == "project_read" then
    return allPathsInProject(name, args)
  end
  if category == "create_file" then
    -- 覆盖已存在文件等于静默数据丢失：即使开启文件自动批准也要求确认
    -- （系统提示词已引导模型对已有文件改用 apply_patch）
    local path = tostring((args or {}).path or "")
    local getPathType = requireConfig().getPathType
    if path ~= "" and getPathType then
      local ok, exists = pcall(function()
        local resolved = requireConfig().resolvePath and requireConfig().resolvePath(path) or path
        return getPathType(resolved) ~= nil
      end)
      if ok and exists then return false end
    end
  end
  if not _M.isDestructiveTool(name) then return false end
  if requireConfig().getSharedData("ai_auto_approve", "0") ~= "1" then return false end
  if projectAutoApproveBlocked() then return false end
  local path = args and args.path or ""
  if name == "rename_file" then
    return _M.isInProjectDir(path) and _M.isInProjectDir(args.new_path or "")
  end
  return _M.isInProjectDir(path)
end

-- ─── 并行工具批次 ──
-- 只有只读、免确认、无全局状态副作用的工具允许并行：并发执行不会互相干扰，
-- 也不会堆叠确认对话框。run_lua（沙盒全局槽位）与 fetch_url（取消注册表）
-- 各自有全局单例语义，明确排除。

function _M.isParallelSafe(name, args)
  local entry = ToolRegistry.get(_M.normalizeToolName(name, args))
  return entry ~= nil and entry.parallelSafe == true
end

--- 判断一批 tool_calls 是否可整体并行执行。满足才返回逐调用描述表：
--- 全部 ≥2 个、均为白名单只读工具、免确认、参数 JSON 可解析，
--- 且不含“曾失败的同参调用”（重复失败短路必须走串行路径正确处理）。
--- deps: { failedToolCalls = 回合层失败去重表（可省略） }
function _M.classifyParallelBatch(toolCalls, deps)
  if type(toolCalls) ~= "table" or #toolCalls < 2 then return nil end
  local failedCalls = deps and deps.failedToolCalls
  local calls = {}
  for i, tc in ipairs(toolCalls) do
    local args = {}
    local decodeOk = pcall(function() args = json.decode(tc.arguments) end)
    if not decodeOk or type(args) ~= "table" then return nil end
    local name = _M.normalizeToolName(tc.name, args)
    if not _M.isParallelSafe(name, args) then return nil end
    if _M.requiresConfirmation(name, args) then return nil end
    if failedCalls then
      local argsEncoded, encodedArgs = pcall(json.encode, args)
      local key = name .. "\n"
        .. (argsEncoded and tostring(encodedArgs) or tostring(tc.arguments or ""))
      if failedCalls[key] then return nil end
    end
    calls[i] = { name = name, args = args, id = tc.id }
  end
  return calls
end

return _M
