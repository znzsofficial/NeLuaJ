---@diagnostic disable: undefined-global
require "mods.bootstrap"
import "java.io.File"
import "java.io.FileOutputStream"
import "android.view.View"
import "android.view.WindowManager"
import "android.content.Intent"
import "android.app.Activity"
import "android.graphics.Bitmap"
import "android.graphics.BitmapFactory"
import "android.graphics.drawable.ColorDrawable"
import "android.widget.LinearLayout"
import "android.Manifest"
import "android.content.pm.PermissionInfo"
import "com.google.android.material.snackbar.Snackbar"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"
import "vinx.material.textfield.MaterialTextField"

-- 必须用 INSTANCE；import 类会覆盖 environment 里的单例
local LuaFileUtil = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local InitLuaUtil = require "mods.project.InitLuaUtil"
local ActivityUtil = require "mods.utils.ActivityUtil"

this.dynamicColor()
local res = res
local ColorUtil = this.themeUtil
local barColor = ColorUtil.getColorBackground()
local MDC_R = luajava.bindClass "com.google.android.material.R"

local projectDir = tostring(... or "")
if projectDir == "" or not File(projectDir).isDirectory() then
  pcall(function()
    local name = Bean.Project.this_project
    if name and name ~= "" then
      projectDir = Bean.Path.app_root_pro_dir .. "/" .. name
    end
  end)
end

activity {
  title = res.string.project_settings,
  ContentView = res.layout.project_settings_layout,
}
  .supportActionBar {
    Elevation = 0,
    BackgroundDrawable = ColorDrawable(barColor),
    DisplayShowTitleEnabled = true,
    DisplayHomeAsUpEnabled = true,
  }

local window = activity.getWindow()
  .setStatusBarColor(barColor)
  .setNavigationBarColor(barColor)
  .addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
  .clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
if this.isNightMode() then
  window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_VISIBLE)
else
  window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR)
end

function onOptionsItemSelected(m)
  if m.getItemId() == android.R.id.home then
    this.finish()
  end
end

local function snack(msg)
  pcall(function()
    Snackbar.make(ps_save, tostring(msg), Snackbar.LENGTH_SHORT).show()
  end)
end

-- 与 themes.xml 中 Theme.NeLuaJ.* 对应（点号 → 下划线）
local THEME_OPTIONS = {
  { value = "Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay", labelKey = "project_theme_m3_noab_overlay" },
  { value = "Theme_NeLuaJ_Material3_NoActionBar", labelKey = "project_theme_m3_noab" },
  { value = "Theme_NeLuaJ_Material3_ActionOverlay", labelKey = "project_theme_m3_overlay" },
  { value = "Theme_NeLuaJ_Material3", labelKey = "project_theme_m3_ab" },
  { value = "Theme_NeLuaJ_Material3_DynamicColors_NoActionBar_ActionOverlay", labelKey = "project_theme_dyn_noab_overlay" },
  { value = "Theme_NeLuaJ_Material3_DynamicColors_NoActionBar", labelKey = "project_theme_dyn_noab" },
  { value = "Theme_NeLuaJ_Material3_DynamicColors_ActionOverlay", labelKey = "project_theme_dyn_overlay" },
  { value = "Theme_NeLuaJ_Material3_DynamicColors", labelKey = "project_theme_dyn_ab" },
  { value = "Theme_NeLuaJ_MaterialComponent_NoActionBar", labelKey = "project_theme_mc_noab" },
  { value = "Theme_NeLuaJ_MaterialComponent", labelKey = "project_theme_mc_ab" },
  { value = "Theme_NeLuaJ_MaterialComponent_Light_NoActionBar", labelKey = "project_theme_mc_light_noab" },
  { value = "Theme_NeLuaJ_MaterialComponent_Light", labelKey = "project_theme_mc_light_ab" },
  { value = "Theme_NeLuaJ_MaterialComponent_Dark_NoActionBar", labelKey = "project_theme_mc_dark_noab" },
  { value = "Theme_NeLuaJ_MaterialComponent_Dark", labelKey = "project_theme_mc_dark_ab" },
  { value = "Theme_NeLuaJ_Compat_NoActionBar", labelKey = "project_theme_compat_noab" },
  { value = "Theme_NeLuaJ_Compat", labelKey = "project_theme_compat_ab" },
}

local selectedThemeValue = THEME_OPTIONS[1].value
local permissions = {} -- ordered unique short names (e.g. INTERNET)
local permCatalogCache -- { { name=, full=, label= }, ... }

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

local function themeLabel(opt)
  if not opt then return "" end
  local t = res.string[opt.labelKey]
  if t and t ~= "" then return t end
  return opt.value
end

local function findThemeOpt(value)
  for _, opt in ipairs(THEME_OPTIONS) do
    if opt.value == value then return opt end
  end
  return nil
end

local function refreshThemeUi()
  local opt = findThemeOpt(selectedThemeValue)
  local label = opt and themeLabel(opt) or (res.string.project_theme_custom or "Custom")
  pcall(function()
    ps_theme_label.setText(label)
    ps_theme_value.setText(selectedThemeValue)
  end)
end

-- 规范为 init.lua 中的短名；自定义权限（含包名前缀）原样保留
local function normalizePerm(name)
  name = tostring(name or ""):match("^%s*(.-)%s*$") or ""
  if name == "" then return "" end
  if name:find("^android%.permission%.") then
    return name:gsub("^android%.permission%.", "")
  end
  -- 纯标识符统一大写，与 Manifest 字段一致
  if name:match("^[%a_][%w_]*$") then
    return name:upper()
  end
  return name
end

local function permKey(name)
  return normalizePerm(name):upper()
end

local function permListHas(name)
  local key = permKey(name)
  for _, p in ipairs(permissions) do
    if permKey(p) == key then return true end
  end
  return false
end

local function permListAdd(name)
  name = normalizePerm(name)
  if name == "" then return false end
  -- 允许 ANDROID 风格标识符，或带点的自定义权限
  if not (name:match("^[%a_][%w_]*$") or name:match("^[%w_.]+$")) then
    return false
  end
  if not permListHas(name) then
    permissions[#permissions + 1] = name
    return true
  end
  return false
end

-- 对齐 PermissionHelper.isSystemPermission：signature 级不展示
local function isSignaturePermission(fullName)
  local ok, result = pcall(function()
    local pm = activity.getPackageManager()
    local info = pm.getPermissionInfo(fullName, 0)
    local base
    local okGet = pcall(function()
      base = info.getProtection() -- API 28+
    end)
    if not okGet or base == nil then
      local level = tonumber(tostring(info.protectionLevel)) or 0
      base = level - math.floor(level / 16) * 16 -- 低 4 位
    end
    local SIG = PermissionInfo.PROTECTION_SIGNATURE or 2
    return base == SIG
  end)
  return ok and result == true
end

local function permissionDisplayName(fullName)
  local ok, label = pcall(function()
    local pm = activity.getPackageManager()
    local info = pm.getPermissionInfo(fullName, 0)
    return tostring(info.loadLabel(pm))
  end)
  if ok and label and label ~= "" then return label end
  return fullName
end

-- 对齐 PermissionHelper.getPermissions：反射 Manifest.permission + MANAGE_EXTERNAL_STORAGE
local function buildPermissionCatalog()
  if permCatalogCache then return permCatalogCache end
  local list = {}
  local seen = {}
  pcall(function()
    local clazz = luajava.bindClass("android.Manifest$permission")
    local fields = clazz.getDeclaredFields()
    local n = fields.length
    for i = 0, n - 1 do
      local field = fields[i]
      pcall(function()
        local shortName = tostring(field.getName())
        local full = tostring(field.get(nil))
        if type(full) ~= "string" or full == "" then return end
        if isSignaturePermission(full) then return end
        local key = shortName:upper()
        if seen[key] then return end
        seen[key] = true
        list[#list + 1] = {
          name = shortName,
          full = full,
          label = permissionDisplayName(full),
        }
      end)
    end
  end)
  -- 与 Helper 一致：额外加入 MANAGE_EXTERNAL_STORAGE（不一定在 Manifest.permission 字段里）
  if not seen["MANAGE_EXTERNAL_STORAGE"] then
    list[#list + 1] = {
      name = "MANAGE_EXTERNAL_STORAGE",
      full = "android.permission.MANAGE_EXTERNAL_STORAGE",
      label = permissionDisplayName("android.permission.MANAGE_EXTERNAL_STORAGE"),
    }
  end
  table.sort(list, function(a, b)
    return a.name < b.name
  end)
  -- 反射失败时的兜底常用列表
  if #list == 0 then
    local fallback = {
      "INTERNET", "ACCESS_NETWORK_STATE", "ACCESS_WIFI_STATE",
      "WRITE_EXTERNAL_STORAGE", "READ_EXTERNAL_STORAGE", "MANAGE_EXTERNAL_STORAGE",
      "CAMERA", "RECORD_AUDIO", "ACCESS_FINE_LOCATION", "ACCESS_COARSE_LOCATION",
      "VIBRATE", "READ_PHONE_STATE", "POST_NOTIFICATIONS", "FOREGROUND_SERVICE", "WAKE_LOCK",
    }
    for _, name in ipairs(fallback) do
      list[#list + 1] = {
        name = name,
        full = "android.permission." .. name,
        label = name,
      }
    end
  end
  permCatalogCache = list
  return list
end

local function refreshPermSummary()
  local text
  if #permissions == 0 then
    text = res.string.project_permissions_empty or "(none)"
  else
    text = table.concat(permissions, "\n")
  end
  pcall(function() ps_perm_summary.setText(text) end)
end

local function parsePermissions(init)
  local list = {}
  if not init then return list end
  local ok, perms = pcall(function() return init.user_permission end)
  if not ok or type(perms) ~= "table" then return list end
  local seen = {}
  for k, v in pairs(perms) do
    local s
    if type(k) == "number" then
      s = tostring(v)
    elseif type(v) == "string" then
      s = v
    elseif type(k) == "string" then
      s = k
    end
    if s then
      s = normalizePerm(s)
      local key = permKey(s)
      if s ~= "" and not seen[key] then
        seen[key] = true
        list[#list + 1] = s
      end
    end
  end
  table.sort(list, function(a, b) return permKey(a) < permKey(b) end)
  return list
end

local function initField(init, key, fallback)
  if not init then return fallback end
  local ok, v = pcall(function() return init[key] end)
  if ok and v ~= nil then
    local s = tostring(v)
    if s ~= "" and s ~= "nil" then return s end
  end
  return fallback
end

-- 多键回退（兼容 appname / app_name 等）
local function initFieldAny(init, keys, fallback)
  if type(keys) == "string" then keys = { keys } end
  for _, k in ipairs(keys) do
    local v = initField(init, k, nil)
    if v ~= nil then return v end
  end
  return fallback
end

local function isDebugMode(init)
  local s = initFieldAny(init, { "debug_mode", "debugmode" }, "true"):lower()
  return s == "true" or s == "1"
end

local function loadInit()
  local initPath = projectDir .. "/init.lua"
  if not File(initPath).isFile() then return nil end
  local ok, t = pcall(function() return LuaFileUtil.loadLua(initPath) end)
  if ok and type(t) == "table" then return t end
  return nil
end

local function refreshIcon()
  pcall(function()
    local size = this.dpToPx(56)
    local iconFile = File(projectDir .. "/icon.png")
    if iconFile.isFile() then
      local bmp = BitmapFactory.decodeFile(iconFile.getAbsolutePath())
      if bmp then
        ps_icon.setImageBitmap(bmp)
        return
      end
    end
    local d = res.drawable("android_studio", ColorUtil.getColorSecondary())
    if d then
      d.setBounds(0, 0, size, size)
      ps_icon.setImageDrawable(d)
    end
  end)
end

local function saveIconFromUri(uri)
  if not uri then return false end
  local ok = pcall(function()
    local input = activity.getContentResolver().openInputStream(uri)
    if not input then error("open stream failed") end
    local bmp = BitmapFactory.decodeStream(input)
    pcall(function() input.close() end)
    if not bmp then error("decode failed") end
    local out = FileOutputStream(projectDir .. "/icon.png")
    local compressed = bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
    out.flush()
    out.close()
    if not compressed then error("compress failed") end
  end)
  return ok
end

local function showThemePicker()
  local labels = {}
  local checked = 0
  for i, opt in ipairs(THEME_OPTIONS) do
    labels[i] = themeLabel(opt)
    if opt.value == selectedThemeValue then checked = i - 1 end
  end
  -- 自定义主题：若不在列表中，追加一项
  local customExtra = nil
  if not findThemeOpt(selectedThemeValue) and selectedThemeValue and selectedThemeValue ~= "" then
    customExtra = selectedThemeValue
    labels[#labels + 1] = (res.string.project_theme_custom or "Custom") .. ": " .. selectedThemeValue
    checked = #labels - 1
  end

  MaterialAlertDialogBuilder(this)
    .setTitle(res.string.project_theme)
    .setSingleChoiceItems(labels, checked, function(_, which)
      checked = which
    end)
    .setPositiveButton(android.R.string.ok, function()
      local idx = checked + 1
      if customExtra and idx == #labels then
        selectedThemeValue = customExtra
      else
        local opt = THEME_OPTIONS[idx]
        if opt then selectedThemeValue = opt.value end
      end
      refreshThemeUi()
    end)
    .setNegativeButton(android.R.string.cancel, nil)
    .show()
end

local showAddPermission -- forward decl

local function applyPermissionChecks(entries, checked)
  local nextList = {}
  local seen = {}
  for i, e in ipairs(entries) do
    if checked[i] then
      local n = normalizePerm(e.name)
      local key = permKey(n)
      if n ~= "" and not seen[key] then
        seen[key] = true
        nextList[#nextList + 1] = n
      end
    end
  end
  table.sort(nextList, function(a, b) return permKey(a) < permKey(b) end)
  permissions = nextList
  refreshPermSummary()
end

local function showPermissionEditor()
  local catalog = buildPermissionCatalog()
  -- entry: { name, display }
  local entries = {}
  local checked = {}
  local catalogKeys = {}

  for _, item in ipairs(catalog) do
    catalogKeys[permKey(item.name)] = true
    local display = item.name
    if item.label and item.label ~= "" and item.label ~= item.full and item.label ~= item.name then
      display = item.name .. "  ·  " .. item.label
    end
    entries[#entries + 1] = { name = item.name, display = display }
    checked[#entries] = permListHas(item.name)
  end

  -- 用户已有、但不在系统目录中的自定义权限：始终展示且默认勾选（取消勾选才会删除）
  for _, p in ipairs(permissions) do
    if not catalogKeys[permKey(p)] then
      local tag = res.string.project_theme_custom or "Custom"
      entries[#entries + 1] = {
        name = p,
        display = p .. "  (" .. tag .. ")",
      }
      checked[#entries] = true
    end
  end

  local labels = {}
  for i, e in ipairs(entries) do
    labels[i] = e.display
  end

  MaterialAlertDialogBuilder(this)
    .setTitle(res.string.project_permissions)
    .setMultiChoiceItems(labels, checked, function(_, which, isChecked)
      checked[which + 1] = isChecked
    end)
    .setPositiveButton(android.R.string.ok, function()
      applyPermissionChecks(entries, checked)
    end)
    .setNegativeButton(android.R.string.cancel, nil)
    .setNeutralButton(res.string.project_permissions_add, function()
      applyPermissionChecks(entries, checked)
      showAddPermission()
    end)
    .show()
end

showAddPermission = function()
  local binding = {}
  local dialogView = loadlayout({
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    paddingLeft = "20dp",
    paddingRight = "20dp",
    paddingTop = "8dp",
    paddingBottom = "4dp",
    {
      MaterialTextField,
      id = "perm_input",
      hint = res.string.project_permissions_add_hint,
      layout_width = "match",
      layout_height = "wrap",
      textSize = "14sp",
      TintColor = ColorUtil.getColorPrimary(),
      style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
      singleLine = true,
    },
  }, binding)
  MaterialAlertDialogBuilder(this)
    .setTitle(res.string.project_permissions_add)
    .setView(dialogView)
    .setPositiveButton(android.R.string.ok, function()
      local name = tostring(binding.perm_input.getText() or "")
      if permListAdd(name) then
        refreshPermSummary()
        snack(res.string.project_permissions_added or name)
      else
        if normalizePerm(name) == "" then
          snack(res.string.project_permissions_add_hint)
        elseif permListHas(name) then
          snack(res.string.project_permissions_exists or name)
        else
          snack(res.string.project_package_invalid)
        end
      end
    end)
    .setNegativeButton(android.R.string.cancel, nil)
    .show()
end

-- 校验工程路径
if projectDir == "" or not File(projectDir).isDirectory() then
  snack(res.string.noProject)
  this.finish()
  return
end

local folderName = File(projectDir).getName()
ps_path.setText(projectDir)

local function defaultPkgSeg(name)
  local seg = tostring(name or ""):lower():gsub("[^%w_]", "")
  if seg == "" then seg = "app" end
  if seg:match("^%d") then seg = "a" .. seg end
  return seg
end

local init = loadInit()
local appName = initFieldAny(init, { "app_name", "appname" }, folderName)
local packageName = initField(init, "package_name", "com.neluaj." .. defaultPkgSeg(folderName))
local verName = initFieldAny(init, { "ver_name", "version_name" }, "1.0")
local verCode = initFieldAny(init, { "ver_code", "version_code" }, "1")
local minSdk = initField(init, "min_sdk", "26")
local targetSdk = initField(init, "target_sdk", "33")
-- 与 LuaActivity.initENV 一致：NeLuaJ_Theme 优先，其次 theme（仅 Theme_NeLuaJ_*）
local theme = InitLuaUtil.resolveThemeName(init, THEME_OPTIONS[1].value)

ps_app_name.setText(appName)
ps_package.setText(packageName)
ps_ver_name.setText(verName)
ps_ver_code.setText(verCode)
ps_min_sdk.setText(minSdk)
ps_target_sdk.setText(targetSdk)

pcall(function() ps_debug.setChecked(isDebugMode(init)) end)

selectedThemeValue = theme
permissions = parsePermissions(init)
refreshThemeUi()
refreshPermSummary()
refreshIcon()

local pickLauncher
pcall(function()
  pickLauncher = this.resultLauncher(function(result)
    if not result then return end
    local resultCode
    pcall(function() resultCode = result.resultCode end)
    if resultCode == nil then pcall(function() resultCode = result.getResultCode() end) end
    if resultCode ~= Activity.RESULT_OK then return end
    local data
    pcall(function() data = result.data end)
    if data == nil then pcall(function() data = result.getData() end) end
    if not data then return end
    local uri
    pcall(function() uri = data.getData() end)
    if not uri then return end
    if saveIconFromUri(uri) then
      refreshIcon()
      snack(res.string.project_icon_updated)
    else
      snack(res.string.project_icon_fail)
    end
  end)
end)

ps_theme_pick.onClick = showThemePicker
ps_perm_edit.onClick = showPermissionEditor
ps_perm_add.onClick = showAddPermission

ps_pick_icon.onClick = function()
  if not pickLauncher then
    snack(res.string.not_supported)
    return
  end
  local intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
  intent.addCategory(Intent.CATEGORY_OPENABLE)
  intent.setType("image/*")
  pcall(function() intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION) end)
  pcall(function() pickLauncher.launch(intent) end)
end

ps_clear_icon.onClick = function()
  local f = File(projectDir .. "/icon.png")
  if f.isFile() then
    pcall(function() f.delete() end)
    refreshIcon()
    snack(res.string.project_icon_cleared)
  end
end

ps_open_init.onClick = function()
  local initPath = projectDir .. "/init.lua"
  if not File(initPath).isFile() then
    snack(res.string.project_no_init)
    return
  end
  -- result 回传 + SharedData 兜底，主界面 onResult / onResume 均可消费
  ActivityUtil.finishWith("open_file", initPath)
end

ps_save.onClick = function()
  local appname = tostring(ps_app_name.getText() or ""):match("^%s*(.-)%s*$") or ""
  local packagename = tostring(ps_package.getText() or ""):match("^%s*(.-)%s*$") or ""
  local vName = tostring(ps_ver_name.getText() or ""):match("^%s*(.-)%s*$") or "1.0"
  local vCode = tostring(ps_ver_code.getText() or ""):match("^%s*(.-)%s*$") or "1"
  local minS = tostring(ps_min_sdk.getText() or ""):match("^%s*(.-)%s*$") or "26"
  local tgtS = tostring(ps_target_sdk.getText() or ""):match("^%s*(.-)%s*$") or "33"

  if appname == "" then
    snack(res.string.project_name_empty)
    return
  end
  if not isValidPackageName(packagename) then
    snack(res.string.project_package_invalid)
    return
  end

  local debugMode = true
  pcall(function() debugMode = ps_debug.isChecked() end)

  local initPath = projectDir .. "/init.lua"
  -- 写 NeLuaJ_Theme；若文件里已有 Theme_NeLuaJ_* 的 theme= 会一并同步
  -- android.R.style 风格的 theme / 数字 theme 保留不动（initENV 里 NeLuaJ_Theme 会覆盖）
  local fields = {
    app_name = appname,
    package_name = packagename,
    ver_name = vName,
    ver_code = vCode,
    min_sdk = minS,
    target_sdk = tgtS,
    debug_mode = debugMode,
    NeLuaJ_Theme = selectedThemeValue,
    user_permission = permissions,
  }
  local ok = false
  pcall(function()
    ok = InitLuaUtil.save(initPath, fields, LuaFileUtil)
  end)
  if ok then
    snack(res.string.save_success)
  else
    snack(res.string.save_fail)
  end
end
