-- Filesystem boundary. Constructors bind Java lazily so preview/tests need no Activity.
-- fs methods use dot calls and throw on failure. publish must never replace a target.
local M = {}
local assetClasses
local function assetIO()
  if not assetClasses then
    assetClasses = {
      Array = luajava.bindClass("java.lang.reflect.Array"),
      Byte = luajava.bindClass("java.lang.Byte"),
      Output = luajava.bindClass("java.io.ByteArrayOutputStream"),
    }
  end
  return assetClasses
end

-- LuaJ++ can throw from read/write as well as return nil. Always close before
-- propagating either kind of failure so rollback can remove the owned files.
local function withFile(path, mode, operation)
  local stream, openError = io.open(path, mode)
  assert(stream, openError)
  local ok, value, reason = pcall(operation, stream)
  local closed, closeResult, closeError = pcall(stream.close, stream)
  if not ok then error(value, 0) end
  assert(value, reason)
  if not closed then error(closeResult, 0) end
  assert(closeResult, closeError)
  return value
end

function M.readAsset(path)
  -- The Android host loads bundled modules through its ResourceFinder; they
  -- need not exist as disk files at any package.path location.
  local host = activity or service
  if host then
    local assets = host.getAssets()
    local input = assets.open(path)
    local ok, content = pcall(function()
      local classes = assetIO()
      local buffer, output = classes.Array.newInstance(classes.Byte.TYPE, 8192), classes.Output()
      while true do
        local count = input.read(buffer)
        if count == -1 then break end
        output.write(buffer, 0, count)
      end
      return tostring(output.toString("UTF-8"))
    end)
    local closed, closeError = pcall(function() input.close() end)
    if not ok then error(content, 0) end
    if not closed then error(closeError, 0) end
    return content
  end
  for pattern in package.path:gmatch("[^;]+") do
    local modulePath = pattern:gsub("%?", "mods/project/templates/FileWriter")
    local root = modulePath:match("^(.*)mods[/\\]project[/\\]templates[/\\]FileWriter%.lua$")
    if root then
      -- LuaJ++ may throw for a missing file instead of returning nil like PUC Lua.
      local opened, file = pcall(io.open, root .. path, "rb")
      if opened and file then
        local ok, content, readError = pcall(file.read, file, "*a")
        local closed, closeResult, closeError = pcall(file.close, file)
        if not ok then error(content, 0) end
        assert(content, readError)
        if not closed then error(closeResult, 0) end
        assert(closeResult, closeError)
        return content
      end
    end
  end
  error("cannot read bundled asset: " .. path)
end

function M.new()
  local File = luajava.bindClass("java.io.File")
  local UUID = luajava.bindClass("java.util.UUID")
  local Files = luajava.bindClass("java.nio.file.Files")
  local fs = {}
  local function exists(path)
    local file = File(path)
    return file.exists() or Files.isSymbolicLink(file.toPath())
  end
  fs.exists = exists
  fs.checkRoot = function(path)
    local root = File(path)
    assert(root.isDirectory() and root.canWrite(), "project root is not a writable directory: " .. path)
    return true
  end
  fs.createStage = function(root)
    for _ = 1, 10 do
      local id = UUID.randomUUID()
      local path = root .. "/.neluaj-stage-" .. tostring(id)
      if File(path).mkdir() then return path end
    end
    error("cannot create exclusive staging directory")
  end
  fs.write = function(stage, relative, content)
    local file = File(stage .. "/" .. relative)
    local parent = file.getParentFile()
    assert(parent.isDirectory() or parent.mkdirs(), "cannot create parent directory")
    assert(file.createNewFile(), "output already exists")
    withFile(tostring(file.getPath()), "wb", function(stream) return stream:write(content) end)
    return true
  end
  local function remove(file)
    if file.isDirectory() and not Files.isSymbolicLink(file.toPath()) then
      local children = file.listFiles()
      assert(children, "cannot list staging directory")
      for i = 0, #children - 1 do remove(children[i]) end
    end
    assert(file.delete(), "cannot remove " .. tostring(file.getPath()))
  end
  fs.cleanup = function(stage)
    if exists(stage) then remove(File(stage)) end
    return true
  end
  fs.publish = function(stage, target, files)
    -- mkdir is the exclusive reservation. File.renameTo alone may replace an empty
    -- directory on Android/Linux. Never use that as a no-clobber publication API.
    assert(File(target).mkdir(), "target already exists or cannot be created")
    local written, directories, currentFile = {}, {}, nil
    local ok, err = pcall(function()
      for _, entry in ipairs(files) do
        currentFile = entry.path
        local prefix = target
        local components = {}
        for part in entry.path:gmatch("[^/]+") do components[#components + 1] = part end
        for i = 1, #components - 1 do
          prefix = prefix .. "/" .. components[i]
          if not directories[prefix] then
            assert(File(prefix).mkdir(), "publication directory conflict: " .. prefix)
            directories[prefix] = true
          end
        end
        local destination = target .. "/" .. entry.path
        local output = File(destination)
        assert(output.createNewFile(), "publication file conflict: " .. destination)
        written[#written + 1] = destination
        local body = withFile(stage .. "/" .. entry.path, "rb", function(input) return input:read("*a") end)
        withFile(destination, "wb", function(stream) return stream:write(body) end)
      end
    end)
    if not ok then
      -- Delete only paths we created; a concurrent foreign entry is never removed.
      local cleanupOK = true
      for i = #written, 1, -1 do if not File(written[i]).delete() then cleanupOK = false end end
      local sorted = {}
      for path in pairs(directories) do sorted[#sorted + 1] = path end
      table.sort(sorted, function(a, b) return #a > #b end)
      for _, path in ipairs(sorted) do if not File(path).delete() then cleanupOK = false end end
      if not File(target).delete() then cleanupOK = false end
      error({ message = tostring(err), file = currentFile,
        partialPath = not cleanupOK and target or nil })
    end
    return true
  end
  return fs
end

return M
