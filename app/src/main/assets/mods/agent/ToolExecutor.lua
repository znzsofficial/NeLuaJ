--- Agent 工具执行边界。
--- 具体文件算法通过 configure 注入，避免执行层依赖 AgentChat 的全局状态。
local _M = {}
local config

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
}

function _M.configure(options)
  config = options or {}
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
    elseif args.pattern then name = "search_in_files"
    elseif args.paths then name = "read_files"
    elseif args.path and args.new_path then name = "rename_file"
    elseif args.content then name = "create_file"
    elseif args.path then name = "read_file" end
  end
  return name
end

function _M.executeTool(name, args)
  name = _M.normalizeToolName(name, args)
  if name:match("^mcp::") or name:match("^mcp__") then
    local route = requireConfig().resolveMcpTool and requireConfig().resolveMcpTool(name)
    local ns, tool = name:sub(6):match("^([^:]+)::(.+)$")
    if route then tool = route.tool end
    if not tool or (not route and not ns) then return "MCP 工具名格式错误: " .. name end
    local server = route and route.server or requireConfig().findMcpServer(ns)
    if not server then return "找不到 MCP 服务器: " .. ns end
    local text, err = requireConfig().callMcpTool(server, tool, args)
    return text or ("MCP 工具调用失败: " .. tostring(err or "未知错误"))
  end
  local platformExecute = requireConfig().platformExecute
  if not platformExecute then return "工具平台执行器未配置: " .. tostring(name) end
  local changes = requireConfig().changeSet
  if args and args.__agent_scope and requireConfig().getProjectScope
      and args.__agent_scope ~= requireConfig().getProjectScope() then
    return "项目已切换，文件操作未执行"
  end
  local transaction, snapshotErr
  if changes then transaction, snapshotErr = changes.begin(name, args or {}) end
  if snapshotErr then return "变更快照失败，操作未执行: " .. tostring(snapshotErr) end
  local executeArgs = transaction and transaction.args or (args or {})
  local result = platformExecute(name, executeArgs)
  if changes then
    local recorded, recordErr = changes.finish(transaction, result)
    if recorded == false or recordErr then result = tostring(result) .. "\n警告: " .. tostring(recordErr) end
  end
  return result
end

function _M.executeToolAsync(name, args, onResult)
  name = _M.normalizeToolName(name, args)
  if name:match("^mcp::") or name:match("^mcp__") then
    local route = requireConfig().resolveMcpTool and requireConfig().resolveMcpTool(name)
    local ns, tool = name:sub(6):match("^([^:]+)::(.+)$")
    if route then tool = route.tool end
    if not tool or (not route and not ns) then
      if onResult then onResult("MCP 工具名格式错误: " .. name) end
      return
    end
    local server = route and route.server or requireConfig().findMcpServer(ns)
    if not server then
      if onResult then onResult("找不到 MCP 服务器: " .. ns) end
      return
    end
    requireConfig().callMcpToolAsync(server, tool, args, function(ok, text)
      if not onResult then return end
      if ok then onResult(text)
      else onResult("MCP 工具调用失败: " .. tostring(text or "未知错误")) end
    end)
    return
  end
  if not onResult then return end
  args = freezeFileArgs(name, args)
  -- 文件和沙盒工具也必须离开 UI 线程；xTask 的完成回调回到主线程。
  local okLaunch = pcall(function()
    xTask(
      function()
        local ok, result = pcall(_M.executeTool, name, args)
        if ok then return { ok = true, result = result } end
        return { ok = false, result = tostring(result) }
      end,
      function(result)
        if type(result) == "table" then
          onResult(result.ok and result.result or "工具执行异常: " .. tostring(result.result))
        else
          onResult("后台任务异常: " .. tostring(result))
        end
      end
      , "io"
    )
  end)
  if not okLaunch then onResult("无法启动后台工具任务") end
end

function _M.isDestructiveTool(name)
  name = _M.normalizeToolName(name)
  if name:match("^mcp::") or name:match("^mcp__") then return true end
  return name == "create_file" or name == "create_folder"
    or name == "delete_file" or name == "delete_folder"
    or name == "apply_patch" or name == "replace_in_file"
    or name == "append_file" or name == "rename_file" or name == "run_lua"
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
  if name == "read_files" then
    local paths = args.paths
    if type(paths) == "string" then paths = { paths } end
    if type(paths) ~= "table" or #paths == 0 then return false end
    for _, path in ipairs(paths) do if not _M.isInProjectDir(path) then return false end end
    return true
  end
  return _M.isInProjectDir(args.path or "")
end

function _M.requiresConfirmation(name, args)
  name = _M.normalizeToolName(name, args)
  if name:match("^mcp::") or name:match("^mcp__") then return true end
  if _M.isDestructiveTool(name) then return true end
  if name == "read_file" or name == "read_files" or name == "list_dir" or name == "search_in_files" then
    return not allPathsInProject(name, args)
  end
  return false
end

function _M.shouldAutoApprove(name, args)
  name = _M.normalizeToolName(name, args)
  if name:match("^mcp::") or name:match("^mcp__") then return false end
  if name == "get_env_info" then return true end
  if name == "read_file" or name == "read_files" or name == "list_dir" or name == "search_in_files" then
    return allPathsInProject(name, args)
  end
  if name == "run_lua" or not _M.isDestructiveTool(name) then return false end
  if requireConfig().getSharedData("ai_auto_approve", "0") ~= "1" then return false end
  local path = args and args.path or ""
  if name == "rename_file" then
    return _M.isInProjectDir(path) and _M.isInProjectDir(args.new_path or "")
  end
  return _M.isInProjectDir(path)
end

return _M
