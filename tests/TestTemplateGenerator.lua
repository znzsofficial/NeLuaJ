local assets = ASSETS or "app/src/main/assets/"
package.path = assets .. "?.lua;" .. package.path
local Generator = require "mods.project.templates.Generator"
local Registry = require "mods.project.templates.Registry"
local Renderer = require "mods.project.templates.Renderer"
local Validator = require "mods.project.templates.Validator"
local Theme = require "mods.utils.ProjectTheme"
local FileWriter = require "mods.project.templates.FileWriter"

local function options(extra)
  local value = { templateId = "blank", appName = '测试 "quote" {{literal}}', packageName = "com.example.demo",
    rootPath = "/Projects", themeName = Theme.DEFAULT }
  for key, item in pairs(extra or {}) do value[key] = item end
  return value
end

local function memory()
  local fs = { targets = {}, stages = {}, writes = 0, publications = 0 }
  fs.checkRoot = function(root) assert(root == "/Projects"); return true end
  fs.exists = function(path) return fs.targets[path] ~= nil end
  fs.createStage = function(root)
    local path = root .. "/.stage"
    assert(not fs.stages[path])
    fs.stages[path] = {}
    return path
  end
  fs.write = function(stage, path, content)
    fs.writes = fs.writes + 1
    if fs.failWrite and fs.writes == fs.failWrite then return false, "injected write failure" end
    assert(not fs.stages[stage][path])
    fs.stages[stage][path] = content
    if fs.race then fs.targets[fs.race] = { user = "keep" } end
    return true
  end
  fs.publish = function(stage, target)
    fs.publications = fs.publications + 1
    assert(not fs.targets[target], "exclusive target collision")
    if fs.failPublish then error("injected publish failure") end
    fs.targets[target] = fs.stages[stage]
    return true
  end
  fs.cleanup = function(stage)
    if fs.failCleanup then return false, "injected cleanup failure" end
    fs.stages[stage] = nil
    return true
  end
  return fs
end

local sample = { id = "blank", version = 1, themeFamilies = { "m3", "dynamic", "mc", "compat" },
  optionalCapabilities = { "internet", "debug", "modules" },
  files = { { source = "main.lua.tpl", path = "main.lua" }, { source = "readme.tpl", path = "README.md" } } }
local source = {
  ["templates/blank/files/main.lua.tpl"] = 'local title = {{appNameLua}}\nlocal theme = {{themeNameLua}}\nreturn title\n',
  ["templates/blank/files/readme.tpl"] = '# {{appNameText}}\n',
}
local function engine(fs, manifest, texts)
  return Generator.new({ fs = fs, registry = { get = function(id) if id == "blank" then return manifest or sample end end },
    readAsset = function(path) return (texts or source)[path] end })
end
local function errorAt(result, phase)
  assert(not result.ok and result.phase == phase, tostring(result.phase) .. ": " .. tostring(result.error))
  assert(type(result.error) == "string" and result.error ~= "")
end
local fs = memory()
local gen = engine(fs)
local preview = gen.preview(options())
assert(preview.ok, preview.error)
assert(fs.writes == 0 and next(fs.stages) == nil, "preview must not write")
local generated = gen.generate(options())
assert(generated.ok and generated.phase == "complete", generated.error)
assert(generated.templateId == "blank" and generated.version == 1)
assert(next(fs.stages) == nil and fs.publications == 1)
for index, file in ipairs(preview.files) do
  assert(generated.files[index].path == file.path and generated.files[index].content == file.content)
  assert(fs.targets[generated.projectPath][file.path] == file.content)
end
assert(assert(load(generated.files[1].content))() == options().appName, "Lua literal must round-trip")
local init = fs.targets[generated.projectPath]["init.lua"]
local env = {}
assert(load(init, "generated init", "t", env))()
assert(env.min_sdk == "26" and env.debug_mode == true and #env.user_permission == 0)
assert(env.app_name == options().appName and env.package_name == "com.example.demo")
errorAt(gen.generate(options()), "target")
assert(fs.publications == 1)

for _, invalid in ipairs({ { appName = "../bad" }, { appName = "bad/name" }, { appName = "bad\\name" },
  { appName = "" }, { appName = "space " }, { appName = "\nname" }, { packageName = "com..app" },
  { appName = "NUL.txt" }, { appName = "COM1" },
  { packageName = "com.class" }, { packageName = "com.1app" }, { packageName = "app" },
  { rootPath = "relative" }, { rootPath = "/Projects/../escape" }, { themeName = "unknown" },
  { modules = { "unknown" } }, { modules = { "time", "time" } }, { useInternet = "true" },
  { debugMode = 1 }, { templateId = "unknown" } }) do
  errorAt(engine(memory()).preview(options(invalid)), "validate")
end
local sparseModules = { "time", "array", "strings", "anim" }
sparseModules[2] = nil
errorAt(engine(memory()).preview(options({ modules = sparseModules })), "validate")
local driveRoot = Validator.validate(options({ rootPath = "C:\\" }), sample)
assert(driveRoot.rootPath == "C:/" and driveRoot.projectPath == "C:/" .. options().appName)
assert(Validator.validate(options({ rootPath = "/" }), sample).projectPath == "/" .. options().appName)
for _, path in ipairs({ "../bad", "/bad", "a/../bad", "a\\bad", "a//bad", "a/", "a/.", "C:bad", "a\0b" }) do
  assert(not Validator.relativePath(path), path)
end
local incompatible = { id = "blank", version = 1, themeFamilies = { "m3" }, files = sample.files }
errorAt(engine(memory(), incompatible).preview(options({ themeName = "Theme_NeLuaJ_Compat" })), "validate")
errorAt(engine(memory(), incompatible).preview(options({ useInternet = true })), "validate")
local required = { id = "blank", version = 1, themeFamilies = { "m3" }, files = sample.files,
  requiredPermissions = { "INTERNET" }, defaults = { useInternet = true } }
assert(engine(memory(), required).preview(options()).ok)
errorAt(engine(memory(), required).preview(options({ useInternet = false })), "validate")

assert(Renderer.render("{{appNameLua}}", { appNameLua = '"{{notAToken}}"' }) == '"{{notAToken}}"')
for _, malformed in ipairs({ "{{missing}}", "{{ invalid }}", "{{missing", "oops}}" }) do
  assert(not pcall(Renderer.render, malformed, {}), malformed)
end
local literal = 'quote"\\\0\1\9\10\13\31\1279中文'
assert(assert(load("return " .. Renderer.luaQuote(literal)))() == literal)

local function badFiles(files, texts)
  local manifest = { id = "blank", version = 1, themeFamilies = sample.themeFamilies, files = files }
  local disk = memory()
  local result = engine(disk, manifest, texts).generate(options())
  errorAt(result, "render")
  assert(disk.writes == 0 and next(disk.stages) == nil)
  return result
end
badFiles({ { source = "main.lua.tpl", path = "../escape" } })
badFiles({ { source = "../escape", path = "main.lua" } })
badFiles({ { source = "main.lua.tpl", path = "main.lua" }, { source = "main.lua.tpl", path = "MAIN.lua" } })
badFiles({ { source = "main.lua.tpl", path = "main.lua" }, { source = "main.lua.tpl", path = "main.lua/child" } })
badFiles({ { source = "main.lua.tpl", path = "init.lua/nested" } })
badFiles({ { source = "missing", path = "main.lua" } })
badFiles({ { source = "main.lua.tpl", path = "MAIN.lua" } })
assert(badFiles(sample.files, { ["templates/blank/files/main.lua.tpl"] = "{{unknown}}" }).file == "main.lua")

fs = memory(); fs.failWrite = 2
errorAt(engine(fs).generate(options()), "write")
assert(next(fs.targets) == nil and next(fs.stages) == nil)
fs = memory(); fs.failWrite = 1; fs.failCleanup = true
local failed = engine(fs).generate(options())
errorAt(failed, "write")
assert(failed.stagingPath == "/Projects/.stage" and failed.cleanupError:find("cleanup", 1, true))
fs = memory(); fs.failPublish = true
errorAt(engine(fs).generate(options()), "publish")
assert(next(fs.targets) == nil and next(fs.stages) == nil)
fs = memory(); fs.race = "/Projects/" .. options().appName
errorAt(engine(fs).generate(options()), "publish")
assert(fs.targets[fs.race].user == "keep" and fs.publications == 0)
fs = memory(); fs.failCleanup = true
local complete = engine(fs).generate(options())
assert(complete.ok and complete.stagingPath and complete.cleanupError, "successful publication remains success with cleanup warning")
fs = memory(); fs.checkRoot = function() return false, "read-only root" end
errorAt(engine(fs).generate(options()), "target")
assert(fs.writes == 0)
fs = memory(); fs.createStage = function() return false, "cannot stage" end
errorAt(engine(fs).generate(options()), "stage")
assert(next(fs.targets) == nil)
fs = memory()
errorAt(engine(fs).generate(options({ modules = { "time" } })), "render")
assert(fs.writes == 0, "missing module must fail before writing")

-- Exercise the actual Java filesystem adapter (no Android classes or Activity).
local realFs = FileWriter.new()
local temp = os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"
local testRoot = realFs.createStage(temp:gsub("\\", "/"))
local diskOK, diskError = pcall(function()
  local nested = { id = sample.id, version = sample.version, themeFamilies = sample.themeFamilies,
    files = { sample.files[1], sample.files[2], { source = "main.lua.tpl", path = "res/string/init.lua" } } }
  local diskEngine = engine(realFs, nested)
  local request = options({ rootPath = testRoot, appName = "real-template-test" })
  local diskPreview = diskEngine.preview(request)
  assert(diskPreview.ok, diskPreview.error)
  local diskResult = diskEngine.generate(request)
  assert(diskResult.ok, diskResult.error)
  for _, file in ipairs(diskPreview.files) do
    local stream = assert(io.open(diskResult.projectPath .. "/" .. file.path, "rb"))
    local content = stream:read("*a")
    stream:close()
    assert(content == file.content)
  end
  errorAt(diskEngine.generate(request), "target")
  local collidingStage = realFs.createStage(testRoot)
  assert(not pcall(realFs.publish, collidingStage, diskResult.projectPath, {}))
  realFs.cleanup(collidingStage)
  local emptyTarget = realFs.createStage(testRoot)
  local secondStage = realFs.createStage(testRoot)
  assert(not pcall(realFs.publish, secondStage, emptyTarget, {}), "even an empty existing directory is never replaced")
  assert(realFs.exists(emptyTarget))
  realFs.cleanup(emptyTarget)
  local partialTarget = testRoot .. "/failed-publication"
  local published, failure = pcall(realFs.publish, secondStage, partialTarget,
    { { path = "nested/missing.lua" } })
  assert(not published and type(failure) == "table" and failure.file == "nested/missing.lua")
  assert(not realFs.exists(partialTarget), "failed publication rolls back owned files and directories")
  realFs.cleanup(secondStage)
  -- Inject throwing I/O into real publication; handles must close before rollback.
  for _, operation in ipairs({ "read", "write" }) do
    local faultStage = realFs.createStage(testRoot)
    realFs.write(faultStage, "main.lua", "return true")
    local target = testRoot .. "/throwing-" .. operation
    local originalOpen, closed = io.open, false
    io.open = function(path, mode)
      local stream = assert(originalOpen(path, mode))
      if (operation == "read" and path == faultStage .. "/main.lua") or
        (operation == "write" and path == target .. "/main.lua") then
        return {
          read = function() error("injected read exception") end,
          write = function() error("injected write exception") end,
          close = function() closed = true; return stream:close() end,
        }
      end
      return stream
    end
    local success, failure = pcall(realFs.publish, faultStage, target, { { path = "main.lua" } })
    io.open = originalOpen
    assert(not success and failure.file == "main.lua" and closed, "throwing " .. operation .. " must close stream")
    assert(not realFs.exists(target), "throwing I/O must roll back publication")
    realFs.cleanup(faultStage)
  end
  local originalOpen, stagedClosed = io.open, false
  io.open = function(path, mode)
    local stream = assert(originalOpen(path, mode))
    if mode == "wb" then
      return { write = function() error("injected staging exception") end,
        close = function() stagedClosed = true; return stream:close() end }
    end
    return stream
  end
  local stagedFailure = diskEngine.generate(options({ rootPath = testRoot, appName = "staging-failure" }))
  io.open = originalOpen
  errorAt(stagedFailure, "write")
  assert(stagedClosed and not stagedFailure.cleanupError and not realFs.exists(testRoot .. "/staging-failure"))
  local stream = assert(io.open(diskResult.projectPath .. "/main.lua", "rb"))
  assert(stream:read("*a") == diskPreview.files[1].content)
  stream:close()
end)
realFs.cleanup(testRoot)
assert(diskOK, diskError)

-- Runtime assets can be APK-backed, independent of package.path and extracted files.
-- A Java InputStream exercises the real byte-array bridge without Android classes.
local originalActivity, originalPath = activity, package.path
local assetClosed, assetRequested = false, nil
local Input = luajava.bindClass("java.io.FileInputStream")
activity = { getAssets = function() return { open = function(path)
  assetRequested = path
  local input = Input(assets .. path)
  return { read = function(buffer) return input.read(buffer) end,
    close = function() assetClosed = true; input.close() end }
end } end }
package.path = "/no-extracted-assets/?.lua"
local assetOK, assetContent = pcall(FileWriter.readAsset, "templates/shared/modules/README.md")
activity, package.path = originalActivity, originalPath
assert(assetOK, assetContent)
assert(assetClosed and assetRequested == "templates/shared/modules/README.md")
assert(assetContent == FileWriter.readAsset(assetRequested), "APK asset lookup must preserve UTF-8 bytes and newlines")
assetClosed = false
activity = { getAssets = function() return { open = function()
  return { read = function() error("injected asset read exception") end,
    close = function() assetClosed = true end }
end } end }
local failedAsset, assetError = pcall(FileWriter.readAsset, "templates/shared/modules/README.md")
activity = originalActivity
assert(not failedAsset and tostring(assetError):find("injected asset read exception", 1, true) and assetClosed)

-- Integration: bundled manifests, every supported theme, every generated Lua file.
local manifests = Registry.list()
assert(#manifests == 6)
local expectedIds = { blank = true, form = true, list = true, navigation = true, settings = true, webview = true }
local generatedCount, luaCount = 0, 0
for _, manifest in ipairs(manifests) do
  assert(expectedIds[manifest.id]); expectedIds[manifest.id] = nil
  for _, theme in ipairs(Theme.OPTIONS) do
    local family = Theme.isCompat(theme.value) and "compat" or (Theme.isMaterialComponent(theme.value) and "mc" or (Theme.isDynamic(theme.value) and "dynamic" or "m3"))
    local supported = false
    for _, candidate in ipairs(manifest.themeFamilies) do if family == candidate then supported = true end end
    local disk = memory()
    local bundled = Generator.new({ fs = disk, readAsset = FileWriter.readAsset })
    local config = options({ templateId = manifest.id, themeName = theme.value })
    local actual = bundled.generate(config)
    if supported then
      assert(actual.ok, manifest.id .. ": " .. tostring(actual.error))
      generatedCount = generatedCount + 1
      local paths = {}
      for _, file in ipairs(actual.files) do
        paths[file.path] = true
        assert(disk.targets[actual.projectPath][file.path] == file.content)
        if file.path:match("%.lua$") then
          local chunk, syntax = load(file.content, manifest.id .. "/" .. file.path)
          assert(chunk, syntax)
          luaCount = luaCount + 1
          assert(not file.content:find("mods.ui.Components", 1, true), "host-only UI dependency")
        end
      end
      assert(paths["main.lua"] and paths["init.lua"] and paths["README.md"] and paths["res/layout/main.lua"])
      local strings = {}
      assert(load(disk.targets[actual.projectPath]["res/string/init.lua"], "strings", "t", strings))()
      for _, file in ipairs(actual.files) do
        if file.path:match("%.lua$") then
          for dependency in file.content:gmatch([=[require%s*%(?%s*["']([^"']+)["']]=]) do
            assert(paths[dependency:gsub("%.", "/") .. ".lua"],
              manifest.id .. "/" .. file.path .. " missing dependency " .. dependency)
          end
          for key in file.content:gmatch("res%.string%.([A-Za-z_][A-Za-z_0-9]*)") do
            assert(strings[key] ~= nil, manifest.id .. "/" .. file.path .. " missing string " .. key)
          end
        end
      end
      local settings = {}
      assert(load(disk.targets[actual.projectPath]["init.lua"], "init", "t", settings))()
      assert(#settings.user_permission == 0)
    else
      errorAt(actual, "validate")
    end
  end
end
assert(next(expectedIds) == nil and generatedCount >= 6)

-- Optional modules are real assets, included in the same preview and write transaction.
fs = memory()
local moduleOptions = options({ modules = { "time", "array", "strings", "anim", "rxlua", "vconsole" }, useInternet = true, debugMode = false })
local moduleGenerator = Generator.new({ fs = fs })
local modulePreview = moduleGenerator.preview(moduleOptions)
assert(modulePreview.ok, modulePreview.error)
local allModules = moduleGenerator.generate(moduleOptions)
assert(allModules.ok, allModules.error)
for index, file in ipairs(allModules.files) do
  assert(modulePreview.files[index].path == file.path and modulePreview.files[index].content == file.content)
  if file.path:match("%.lua$") then assert(load(file.content, file.path)) end
end
for _, id in ipairs(moduleOptions.modules) do assert(fs.targets[allModules.projectPath][Registry.MODULES[id].path]) end
assert(fs.targets[allModules.projectPath]["MODULES.md"]:find('require "mods.Array"', 1, true),
  "optional modules must ship their standalone usage guide")
assert(fs.targets[allModules.projectPath]["main.lua"]:find('require "vConsole"', 1, true))
local settings = {}
assert(load(fs.targets[allModules.projectPath]["init.lua"], "init", "t", settings))()
assert(settings.debug_mode == false and settings.user_permission[1] == "INTERNET")

print("ALL-PASS TestTemplateGenerator (" .. generatedCount .. " theme/template combinations; " .. luaCount .. " Lua files parsed)")
