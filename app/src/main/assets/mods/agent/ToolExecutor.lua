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

function _M.normalizeToolName(name, args)
  name = tostring(name or ""):match("^%s*(.-)%s*$")
  if name:match("^mcp::") then return name end
  name = name:gsub("^tools[%.:]", "")
    :gsub("^function[%.:]", "")
    :gsub("^functions[%.:]", "")
    :gsub("^tool[%.:]", "")
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
  if name:match("^mcp::") then
    local ns, tool = name:sub(6):match("^([^:]+)::(.+)$")
    if not ns or not tool then return "MCP 工具名格式错误: " .. name end
    local server = requireConfig().findMcpServer(ns)
    if not server then return "找不到 MCP 服务器: " .. ns end
    local text, err = requireConfig().callMcpTool(server, tool, args)
    return text or ("MCP 工具调用失败: " .. tostring(err or "未知错误"))
  end
  local platformExecute = requireConfig().platformExecute
  if not platformExecute then return "工具平台执行器未配置: " .. tostring(name) end
  local changes = requireConfig().changeSet
  local transaction = changes and changes.begin(name, args or {})
  local result = platformExecute(name, args or {})
  if changes then changes.finish(transaction, result) end
  return result
end

function _M.executeToolAsync(name, args, onResult)
  name = _M.normalizeToolName(name, args)
  if name:match("^mcp::") then
    local ns, tool = name:sub(6):match("^([^:]+)::(.+)$")
    if not ns or not tool then
      if onResult then onResult("MCP 工具名格式错误: " .. name) end
      return
    end
    local server = requireConfig().findMcpServer(ns)
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
  if name:match("^mcp::") then return true end
  return name == "create_file" or name == "create_folder"
    or name == "delete_file" or name == "delete_folder"
    or name == "apply_patch" or name == "replace_in_file"
    or name == "append_file" or name == "rename_file" or name == "run_lua"
end

function _M.isInProjectDir(path)
  if not path or path == "" then return true end
  local projectDir = requireConfig().getProjectDir()
  if not projectDir or projectDir == "" then return false end
  local resolved = requireConfig().normalizePath(path)
  local projectNorm = requireConfig().normalizePath(projectDir)
  if not projectNorm or projectNorm == "" then return false end
  if resolved:sub(1, #projectNorm) ~= projectNorm then return false end
  return #resolved == #projectNorm or resolved:sub(#projectNorm + 1, #projectNorm + 1) == "/"
end

function _M.shouldAutoApprove(name, args)
  name = _M.normalizeToolName(name, args)
  if name:match("^mcp::") then return false end
  if name == "read_file" or name == "read_files" or name == "list_dir"
    or name == "search_in_files" or name == "get_env_info" then return true end
  if name == "run_lua" or not _M.isDestructiveTool(name) then return false end
  if requireConfig().getSharedData("ai_auto_approve", "0") ~= "1" then return false end
  local path = args and args.path or ""
  if name == "rename_file" then
    return _M.isInProjectDir(path) and _M.isInProjectDir(args.new_path or "")
  end
  return _M.isInProjectDir(path)
end

return _M
