local Registry = require "mods.project.templates.Registry"
local Validator = require "mods.project.templates.Validator"
local Renderer = require "mods.project.templates.Renderer"
local FileWriter = require "mods.project.templates.FileWriter"
local M = {}

-- DI: readAsset(path)->string, registry.get(id)->manifest; fs.checkRoot/exists,
-- createStage(root)->exclusive path, write(stage,relative,content),
-- publish(stage,target,files), cleanup(stage). Mutations throw or return false.
function M.new(deps)
  deps = deps or {}
  local engine, fs = {}, deps.fs
  local function filesystem()
    if not fs then fs = FileWriter.new() end
    return fs
  end
  local function checked(fn, ...)
    local value, reason = fn(...)
    assert(value ~= false, reason or "filesystem operation failed")
    return value
  end
  local function run(options, write)
    local phase, currentFile, stage, result = "validate", nil, nil, nil
    local ok, failure = pcall(function()
      assert(type(options) == "table", "options must be a table")
      local manifest = (deps.registry or Registry).get(options.templateId or "blank")
      assert(manifest, "unknown template: " .. tostring(options.templateId))
      local config = Validator.validate(options, manifest)
      result = { ok = true, templateId = manifest.id, version = manifest.version,
        projectPath = config.projectPath, config = config, permissions = config.permissions }
      phase = "target"
      local disk = filesystem()
      checked(disk.checkRoot, config.rootPath)
      assert(not disk.exists(config.projectPath), "target already exists")
      phase = "render"
      result.files = Renderer.files(manifest, config, deps.readAsset or FileWriter.readAsset,
        function(path) currentFile = path end)
      currentFile = nil
      if not write then return end
      phase = "target"
      checked(disk.checkRoot, config.rootPath)
      assert(not disk.exists(config.projectPath), "target already exists")
      phase = "stage"
      local candidate = checked(disk.createStage, config.rootPath)
      assert(type(candidate) == "string" and candidate ~= config.rootPath and candidate ~= config.projectPath,
        "filesystem did not return an exclusive staging path")
      stage = candidate
      phase = "write"
      for _, file in ipairs(result.files) do
        currentFile = file.path
        checked(disk.write, stage, file.path, file.content)
      end
      currentFile = nil
      phase = "publish"
      assert(not disk.exists(config.projectPath), "target appeared during generation")
      checked(disk.publish, stage, config.projectPath, result.files)
      phase = "complete"
    end)
    if stage then
      local cleaned, cleanupError = pcall(function() checked(filesystem().cleanup, stage) end)
      if not cleaned then
        result = result or {}
        result.stagingPath, result.cleanupError = stage, tostring(cleanupError)
      end
    end
    result = result or { templateId = type(options) == "table" and options.templateId or nil }
    result.ok = ok
    result.phase = ok and (write and "complete" or "preview") or phase
    if not ok then
      local message = type(failure) == "table" and failure.message or tostring(failure)
      result.error, result.message, result.file = message, message, currentFile
      if type(failure) == "table" then
        result.file = failure.file or currentFile
        result.partialPath = failure.partialPath
      end
    end
    return result
  end
  engine.preview = function(options) return run(options, false) end
  engine.generate = function(options) return run(options, true) end
  return engine
end

function M.preview(options) return M.new().preview(options) end
function M.generate(options) return M.new().generate(options) end
return M
