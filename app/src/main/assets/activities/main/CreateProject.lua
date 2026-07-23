--[[
  创建工程对话框与脚手架生成。
  由 MainPublic.createProject 调用；依赖全局 this / res / Bean / MainActivity 等主界面环境。
]]
import "java.io.File"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"
local LuaUtil = bindClass "com.androlua.LuaUtil"
local ProjectTheme = require "mods.utils.ProjectTheme"
local PathManager = require "mods.utils.PathManager"
local EditorUtil = require "mods.utils.EditorUtil"
local res = res

local _M = {}

local function sanitizePackageSegment(s)
  s = tostring(s or ""):lower()
  s = s:gsub("[^%w_]", "")
  if s == "" then s = "app" end
  if s:match("^%d") then s = "a" .. s end
  return s
end

local function refreshProjectPathPreview(binding, appname)
  pcall(function()
    local name = tostring(appname or "")
    if name == "" then name = "…" end
    binding.project_path_preview.setText(
      res.string.project_path_label .. "\n" .. Bean.Path.app_root_pro_dir .. "/" .. name
    )
  end)
end

local function luaQuote(s)
  s = tostring(s or "")
  s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r")
  return '"' .. s .. '"'
end

local function isValidPackageName(pkg)
  if type(pkg) ~= "string" or pkg == "" then return false end
  if pkg:find("%.%.") or pkg:match("^%.") or pkg:match("%.$") then return false end
  for seg in (pkg .. "."):gmatch("([^%.]+)%.") do
    if seg == "" or seg:match("^%d") or not seg:match("^[%a_][%w_]*$") then
      return false
    end
  end
  return pkg:find(".", 1, true) ~= nil
end

local function setupSingleSelectChips(binding, chipIds, defaultId)
  local chips = {}
  for _, id in ipairs(chipIds) do
    local c = binding[id]
    if c then chips[#chips + 1] = c end
  end
  local selecting = false
  local function select(selected)
    selecting = true
    for _, chip in ipairs(chips) do
      pcall(function()
        chip.setChecked(chip == selected)
      end)
    end
    selecting = false
  end
  for _, chip in ipairs(chips) do
    pcall(function()
      chip.setOnCheckedChangeListener(function(btn, isChecked)
        if selecting then return end
        if isChecked then
          select(btn)
        else
          local any = false
          for _, c in ipairs(chips) do
            local ok, ck = pcall(function() return c.isChecked() end)
            if ok and ck then any = true break end
          end
          if not any then
            selecting = true
            pcall(function() btn.setChecked(true) end)
            selecting = false
          end
        end
      end)
    end)
  end
  local def = binding[defaultId] or chips[1]
  if def then select(def) end
end

local function selectedTheme(binding)
  for _, opt in ipairs(ProjectTheme.CREATE_CHIPS) do
    local chip = binding[opt.chip]
    local ok, checked = pcall(function() return chip and chip.isChecked() end)
    if ok and checked then
      return opt.value
    end
  end
  return ProjectTheme.DEFAULT
end

local function buildInitLua(appname, packagename, themeName, useInternet, debugMode)
  local perms = useInternet and '  "INTERNET",\n' or ""
  local debugVal = debugMode and "true" or "false"
  return table.concat({
    "app_name = " .. luaQuote(appname),
    "package_name = " .. luaQuote(packagename),
    'ver_name = "1.0"',
    'ver_code = "1"',
    'min_sdk = "26"',
    'target_sdk = "33"',
    "debug_mode = " .. debugVal,
    "NeLuaJ_Theme = " .. luaQuote(themeName),
    "user_permission = {",
    perms .. "}",
    "",
  }, "\n")
end

-- 写入 mods/ 的模块（vConsole 在工程根目录）
local MODS_CHIPS = {
  { id = "module_time", file = "TimeMeter.lua", codeKey = "code_time" },
  { id = "module_array", file = "Array.lua", codeKey = "code_array" },
  { id = "module_strings", file = "Strings.lua", codeKey = "code_strings" },
  { id = "module_anim", file = "ObjectAnimator.lua", codeKey = "code_anim" },
  { id = "module_rxlua", file = "rx.lua", fromLuaDir = true },
}

local function chipChecked(binding, id)
  local ok, checked = pcall(function() return binding[id].isChecked() end)
  return ok and checked
end

local function anyModsChip(binding)
  for _, m in ipairs(MODS_CHIPS) do
    if chipChecked(binding, m.id) then return true end
  end
  return false
end

local function copySelectedModules(binding, base_path, mainTpl)
  if chipChecked(binding, "module_vconsole") then
    local body = tostring(mainTpl or "")
    if body ~= "" and not body:find("\n$") then body = body .. "\n" end
    mainTpl = body .. 'require "vConsole"\n'
    pcall(function()
      LuaUtil.copyFile(this.getLuaDir("vConsole.lua"), base_path .. "/vConsole.lua")
    end)
  end

  local needMods = anyModsChip(binding)
  if needMods then
    File(base_path .. "/mods").mkdirs()
  end
  for _, m in ipairs(MODS_CHIPS) do
    if chipChecked(binding, m.id) then
      local dest = base_path .. "/mods/" .. m.file
      if m.fromLuaDir then
        LuaUtil.copyFile(this.getLuaDir(m.file), dest)
      else
        LuaFileUtil.create(dest, res.string[m.codeKey])
      end
    end
  end
  return mainTpl
end

local function writeScaffold(base_path, appname, packagename, themeName, useSample, useInternet, debugMode, binding)
  local dirs = {
    "/libs",
    "/res/raw", "/res/font", "/res/string", "/res/dimen",
    "/res/drawable", "/res/layout", "/res/color", "/res/plurals",
  }
  for _, d in ipairs(dirs) do
    File(base_path .. d).mkdirs()
  end

  local mainKey, layoutKey = ProjectTheme.templateKeys(themeName, useSample)
  local mainTpl = res.string[mainKey]
  local layoutTpl = res.string[layoutKey]
  if not mainTpl or mainTpl == "" then
    mainTpl = res.string.mcode_minimal or res.string.mcode or ""
  end
  if not layoutTpl or layoutTpl == "" then
    layoutTpl = res.string.lcode_minimal or res.string.lcode or ""
  end

  local initBody = buildInitLua(appname, packagename, themeName, useInternet, debugMode)
  mainTpl = copySelectedModules(binding, base_path, mainTpl)

  local stringInit = table.concat({
    "app_title = " .. luaQuote(appname),
    "",
  }, "\n")
  local stringZh = table.concat({
    "-- Chinese",
    'about = "关于"',
    "",
  }, "\n")
  local stringEn = table.concat({
    "-- English",
    'about = "About"',
    "",
  }, "\n")

  LuaFileUtil
    .create(base_path .. "/main.lua", mainTpl)
    .create(base_path .. "/init.lua", initBody)
    .create(base_path .. "/res/string/init.lua", stringInit)
    .create(base_path .. "/res/string/en.lua", stringEn)
    .create(base_path .. "/res/string/zh.lua", stringZh)
    .create(base_path .. "/res/string/default.lua", 'return "zh"\n')
    .create(base_path .. "/res/plurals/init.lua", "-- plurals\n")
    .create(base_path .. "/res/plurals/en.lua", "-- English\n")
    .create(base_path .. "/res/plurals/zh.lua", "-- Chinese\n")
    .create(base_path .. "/res/dimen/init.lua", "-- dimensions\n")
    .create(base_path .. "/res/dimen/land.lua", "-- landscape\n")
    .create(base_path .. "/res/dimen/port.lua", "-- portrait\n")
    .create(base_path .. "/res/color/init.lua", "-- colors\n")
    .create(base_path .. "/res/color/day.lua", "-- day\n")
    .create(base_path .. "/res/color/night.lua", "-- night\n")
    .create(base_path .. "/res/layout/main.lua", layoutTpl)
end

--- @param deps { snack: function } 主界面 snack 等
function _M.show(deps)
  deps = deps or {}
  local snack = deps.snack or function(msg) print(msg) end

  local binding = {}
  local dialog = MaterialAlertDialogBuilder(this)
    .setTitle(res.string.create_project)
    .setView(loadlayout(res.layout.new_project, binding))
    .setPositiveButton(android.R.string.ok, nil)
    .setNegativeButton(android.R.string.cancel, nil)
    .create()

  local defaultName, defaultPkg = "demo1", "com.neluaj.demo1"
  for i = 1, 1000 do
    if not File(Bean.Path.app_root_pro_dir .. "/demo" .. i).exists() then
      defaultName = "demo" .. i
      defaultPkg = "com.neluaj.demo" .. i
      break
    end
  end
  binding.project_appName.setText(defaultName)
  binding.project_packageName.setText(defaultPkg)
  refreshProjectPathPreview(binding, defaultName)
  do
    local chipIds = {}
    for _, c in ipairs(ProjectTheme.CREATE_CHIPS) do
      chipIds[#chipIds + 1] = c.chip
    end
    setupSingleSelectChips(binding, chipIds, ProjectTheme.CREATE_CHIPS[1].chip)
  end

  pcall(function()
    local TextWatcher = luajava.bindClass "android.text.TextWatcher"
    local lastAutoPkg = defaultPkg
    binding.project_appName.addTextChangedListener(TextWatcher({
      beforeTextChanged = function() end,
      onTextChanged = function() end,
      afterTextChanged = function(s)
        local appname = tostring(s or "")
        refreshProjectPathPreview(binding, appname)
        local curPkg = tostring(binding.project_packageName.getText() or "")
        if curPkg == lastAutoPkg or curPkg == "" then
          local seg = sanitizePackageSegment(appname)
          lastAutoPkg = "com.neluaj." .. seg
          binding.project_packageName.setText(lastAutoPkg)
        end
      end,
    }))
  end)

  dialog.setOnShowListener(function()
    local btn = dialog.getButton(luajava.bindClass("android.content.DialogInterface").BUTTON_POSITIVE)
    if not btn then return end
    btn.onClick = function()
      local appname = tostring(binding.project_appName.getText() or ""):match("^%s*(.-)%s*$") or ""
      local packagename = tostring(binding.project_packageName.getText() or ""):match("^%s*(.-)%s*$") or ""
      if appname == "" then
        snack(res.string.project_name_empty)
        return
      end
      if appname:find("[/\\]") or appname:find("%.%.") then
        snack(res.string.project_name_invalid)
        return
      end
      if not isValidPackageName(packagename) then
        snack(res.string.project_package_invalid)
        return
      end

      local base_path = Bean.Path.app_root_pro_dir .. "/" .. appname
      if File(base_path).exists() then
        snack(res.string.project_exists)
        return
      end

      local useSample, openAfter, useInternet, debugMode = true, true, true, true
      pcall(function() useSample = binding.project_sample_ui.isChecked() end)
      pcall(function() openAfter = binding.project_open_after.isChecked() end)
      pcall(function() useInternet = binding.project_internet.isChecked() end)
      pcall(function() debugMode = binding.project_debug_mode.isChecked() end)
      local themeName = selectedTheme(binding)

      writeScaffold(base_path, appname, packagename, themeName, useSample, useInternet, debugMode, binding)

      dialog.dismiss()
      snack(res.string.create_success .. ": " .. appname)
      pcall(function() MainActivity.RecyclerView.update() end)

      if openAfter then
        pcall(function()
          PathManager.updateDir(base_path)
          filetab.setPath(base_path)
          MainActivity.RecyclerView.update()
          if File(base_path .. "/main.lua").isFile() then
            EditorUtil.fromRecy = true
            EditorUtil.load(base_path .. "/main.lua")
          end
        end)
      end
    end
  end)

  dialog.show()
  return dialog
end

return _M
