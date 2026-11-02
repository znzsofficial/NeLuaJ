--- Project identity is not the file-browser directory or the open editor file.
--- No Android dependencies; Bean is read lazily (including legacy direct writes).
local function normalize(path)
    local value = tostring(path or "")
    if value == "" then return "" end
    local absolute, parts = value:sub(1, 1) == "/", {}
    for part in value:gmatch("[^/]+") do
        if part == ".." then
            if #parts > 0 and parts[#parts] ~= ".." then
                parts[#parts] = nil
            elseif not absolute then
                parts[#parts + 1] = part
            end
        elseif part ~= "." then
            parts[#parts + 1] = part
        end
    end
    local result = (absolute and "/" or "") .. table.concat(parts, "/")
    return result ~= "" and result or "."
end

local function contains(path, root)
    path, root = normalize(path), normalize(root)
    if path == "" or root == "" then return false end
    if path == root then return true end
    local prefix = root == "/" and root or root .. "/"
    return path:sub(1, #prefix) == prefix
end

local function projectKey(path, root)
    path, root = normalize(path), normalize(root)
    if root:sub(1, 1) ~= "/" or path == root or not contains(path, root) then return nil end
    local prefix = root == "/" and root or root .. "/"
    local name = path:sub(#prefix + 1):match("^([^/]+)")
    return name and prefix .. name or nil
end

local function new(getBean)
    getBean = getBean or function() return Bean end
    local api, owner = {}, {}
    local previous, generation, projectGeneration = nil, 0, 0

    api.normalize = normalize
    api.contains = contains

    function api.projectKeyOf(path, root)
        local bean = getBean()
        local paths = bean and bean.Path
        return projectKey(path, root or (paths and paths.app_root_pro_dir))
    end

    --- Detached value snapshot. scopePath is the project root, or the directory
    --- outside Projects; editorProjectRoot describes the independently open file.
    function api.snapshot()
        local bean = getBean()
        local paths = bean and bean.Path
        local current = {
            projectsRoot = normalize(paths and paths.app_root_pro_dir),
            directory = normalize(paths and paths.this_dir),
            file = normalize(paths and paths.this_file),
            agentRoot = normalize(paths and paths.agent_root_dir),
        }
        current.projectRoot = projectKey(current.directory, current.projectsRoot)
        current.projectName = current.projectRoot and current.projectRoot:match("([^/]+)$") or ""
        current.editorProjectRoot = projectKey(current.file, current.projectsRoot)
        current.scopePath = current.projectRoot or current.directory
        local changed = not previous or previous.paths ~= paths
            or previous.projectsRoot ~= current.projectsRoot
            or previous.directory ~= current.directory or previous.file ~= current.file
            or previous.agentRoot ~= current.agentRoot
        if changed then
            generation = generation + 1
            if not previous or previous.paths ~= paths
                or previous.projectsRoot ~= current.projectsRoot
                or previous.scopePath ~= current.scopePath
                or previous.agentRoot ~= current.agentRoot then
                projectGeneration = projectGeneration + 1
            end
            previous = {
                paths = paths, projectsRoot = current.projectsRoot,
                directory = current.directory, file = current.file,
                scopePath = current.scopePath, agentRoot = current.agentRoot,
            }
        end
        current.generation, current.projectGeneration = generation, projectGeneration
        current.owner = owner
        return current
    end

    --- Project ownership survives navigation inside that project. Exact editor /
    --- directory callbacks can request the stricter full-generation check.
    function api.isCurrent(snapshot, scope)
        if type(snapshot) ~= "table" or snapshot.owner ~= owner then return false end
        local current = api.snapshot()
        if scope == "project" or scope == nil then
            return snapshot.projectGeneration == current.projectGeneration
                and snapshot.scopePath == current.scopePath
        end
        return snapshot.generation == current.generation
    end

    local function pathsOrError()
        local bean = getBean()
        if not bean or not bean.Path then error("ProjectContext: Bean.Path is not initialized", 3) end
        return bean.Path
    end

    function api.setDirectory(path)
        local normalized = normalize(path)
        if normalized:sub(1, 1) ~= "/" then
            error("ProjectContext: directory must be an absolute path: " .. normalized, 2)
        end
        local paths = pathsOrError()
        api.snapshot() -- observe intervening legacy Bean writes before replacing them
        paths.this_dir = normalized
        return api.snapshot()
    end

    function api.setFile(path)
        local paths = pathsOrError()
        api.snapshot()
        paths.this_file = normalize(path)
        return api.snapshot()
    end

    return api
end

local context = new()
context.new = new
return context
