--- 工程目录长按菜单。编辑器在 Projects 根下长按工程时用它，首页项目列表也用它。
--- 文件操作两边相同；打开、进设置、编辑 init、运行由 host 覆盖，
--- 因为首页和编辑器不是同一个 Lua 状态。
local File = luajava.bindClass("java.io.File")
local MaterialAlertDialogBuilder = luajava.bindClass("com.google.android.material.dialog.MaterialAlertDialogBuilder")
local BottomSheetDialog = luajava.bindClass("com.google.android.material.bottomsheet.BottomSheetDialog")
local BottomSheetBehavior = luajava.bindClass("com.google.android.material.bottomsheet.BottomSheetBehavior")
local InitReader = require "mods.project.InitReader"

local _M = {}
local res = res

local function resolveSheetContainer(dialog, content)
  local sheet
  pcall(function()
    local mid = activity.getResources().getIdentifier(
      "design_bottom_sheet", "id", activity.getPackageName())
    if mid == 0 then
      mid = activity.getResources().getIdentifier(
        "design_bottom_sheet", "id", "com.google.android.material")
    end
    if mid ~= 0 then sheet = dialog.findViewById(mid) end
  end)
  if not sheet and content then
    pcall(function() sheet = content.getParent() end)
  end
  return sheet
end

local function expandBottomSheet(dialog, content)
  if not dialog then return end
  local sheet = resolveSheetContainer(dialog, content)
  if not sheet then return end

  local lp = sheet.getLayoutParams()
  if lp then
    lp.height = -2
    sheet.setLayoutParams(lp)
  end

  local behavior
  pcall(function() behavior = dialog.getBehavior() end)
  if not behavior then
    behavior = BottomSheetBehavior.from(sheet)
  end
  if not behavior then return end

  pcall(function() behavior.setFitToContents(true) end)
  pcall(function() behavior.setSkipCollapsed(true) end)
  pcall(function() behavior.setDraggable(true) end)
  pcall(function() behavior.setHalfExpandedRatio(0.92) end)
  pcall(function() behavior.setExpandedOffset(0) end)

  local h = content and content.getMeasuredHeight() or 0
  if (not h or h <= 0) and sheet.getMeasuredHeight then
    h = sheet.getMeasuredHeight()
  end
  if not h or h <= 0 then
    local dm = activity.getResources().getDisplayMetrics()
    h = math.floor(dm.heightPixels * 0.7)
  end
  pcall(function() behavior.setPeekHeight(h) end)
  behavior.setState(BottomSheetBehavior.STATE_EXPANDED)
end

local function showBottomSheet(dialog, content)
  pcall(function() dialog.dismissWithAnimation = true end)
  dialog.setContentView(content)
  dialog.setOnShowListener(function()
    expandBottomSheet(dialog, content)
    if content then
      content.post(function()
        expandBottomSheet(dialog, content)
      end)
    end
  end)
  dialog.show()
  expandBottomSheet(dialog, content)
  return dialog
end

local function formatPermissions(init)
  if not init then return nil end
  local ok, perms = pcall(function() return init.user_permission end)
  if not ok or type(perms) ~= "table" then return nil end
  local list = {}
  for k, v in pairs(perms) do
    if type(k) == "number" then
      list[#list + 1] = tostring(v)
    elseif type(v) == "string" then
      list[#list + 1] = v
    elseif type(k) == "string" then
      list[#list + 1] = k
    end
  end
  table.sort(list)
  if #list == 0 then return nil end
  return table.concat(list, " · ")
end

local function isProjectRoot(path)
  local root = tostring(Bean.Path.app_root_pro_dir or ""):gsub("[/\\]+$", "")
  path = tostring(path or ""):gsub("[/\\]+$", "")
  if root == "" or path == "" or path == root then return false end
  local prefix = root .. "/"
  if path:sub(1, #prefix) ~= prefix then return false end
  local name = path:sub(#prefix + 1)
  return name ~= "" and not name:find("/", 1, true) and not name:find("\\", 1, true)
end

--- @param host table|nil snack/open/openSettings/openInit/run/beforeRename/afterRename/delete/refresh/parentDir
function _M.show(path, name, host)
  host = host or {}
  path = tostring(path or "")
  name = tostring(name or "")
  if path == "" then return end

  local function snack(msg)
    if host.snack then
      pcall(function() host.snack(msg) end)
    end
  end

  local function applyCreate(result)
    result = tostring(result or "failed")
    if result == "exists" then
      snack(res.string.have_same_name)
      return false
    end
    if result ~= "ok" then
      snack(res.string.rename_fail)
      return false
    end
    snack(res.string.create_success)
    return true
  end

  local function notifyChanged()
    if host.afterRename then
      host.afterRename()
    elseif host.refresh then
      host.refresh()
    end
  end

  local layout = {}
  local sublayout = {}
  local dialog = BottomSheetDialog(activity)
  local projectContent = loadlayout(res.layout.project_menu, layout)
  showBottomSheet(dialog, projectContent)

  local init = InitReader.load(path)
  local appName = InitReader.field(init, "app_name", InitReader.field(init, "appname", name))
  local packageName = InitReader.field(init, "package_name", "—")
  local verName = InitReader.field(init, "ver_name", InitReader.field(init, "version_name", "—"))
  local verCode = InitReader.field(init, "ver_code", InitReader.field(init, "version_code", "—"))
  local minSdk = InitReader.field(init, "min_sdk", "—")
  local targetSdk = InitReader.field(init, "target_sdk", "—")
  local theme = InitReader.field(init, "NeLuaJ_Theme", nil)
  if not theme or theme == "" then
    local t = InitReader.field(init, "theme", "—")
    if type(t) == "string" and t:find("^Theme_NeLuaJ_") then
      theme = t
    else
      theme = t or "—"
    end
  end
  local debugMode = InitReader.field(init, "debug_mode", InitReader.field(init, "debugmode", "—"))
  local perms = formatPermissions(init)

  layout.nameText.setText(appName)
  layout.packageText.setText(packageName)
  layout.versionText.setText(string.format("%s  v%s (%s)", res.string.project_version, verName, verCode))
  layout.pathText.setText(path)
  layout.metaText.setText(string.format(
    "minSdk %s  ·  targetSdk %s\n%s  ·  debug %s",
    minSdk, targetSdk, theme, debugMode
  ))
  if perms and layout.permLabel and layout.permText then
    layout.permLabel.setVisibility(0)
    layout.permText.setText(perms)
  end

  pcall(function()
    local size = this.dpToPx(56)
    local iconFile = File(path .. "/icon.png")
    if iconFile.isFile() then
      local BitmapFactory = luajava.bindClass("android.graphics.BitmapFactory")
      local bmp = BitmapFactory.decodeFile(iconFile.getAbsolutePath())
      if bmp then
        layout.projectIcon.setImageBitmap(bmp)
        return
      end
    end
    local d = res.drawable("android_studio", this.themeUtil.getColorSecondary())
    if d then
      d.setBounds(0, 0, size, size)
      layout.projectIcon.setImageDrawable(d)
    end
  end)

  layout.button_open.onClick = function()
    dialog.dismiss()
    if host.open then
      host.open(path)
    else
      require("mods.utils.ActivityUtil").open("editor", path)
    end
  end

  layout.button_settings.onClick = function()
    dialog.dismiss()
    if host.openSettings then
      host.openSettings(path)
    else
      require("mods.utils.ActivityUtil").open("project_settings", path)
    end
  end

  layout.button_open_init.onClick = function()
    dialog.dismiss()
    local initPath = path .. "/init.lua"
    if not File(initPath).isFile() then
      snack(res.string.project_no_init)
      return
    end
    if host.openInit then
      host.openInit(initPath)
    else
      local ActivityUtil = require "mods.utils.ActivityUtil"
      ActivityUtil.setPending("open_init", initPath)
      ActivityUtil.open("editor", path)
    end
  end

  layout.button_run.onClick = function()
    dialog.dismiss()
    local mainPath = path .. "/main.lua"
    if not File(mainPath).isFile() then
      snack(res.string.project_no_main)
      return
    end
    if host.run then
      host.run(path, name)
    else
      require("mods.project.RunLauncher").launchScript(activity, mainPath, { snack = snack })
    end
  end

  layout.button_backup.onClick = function()
    dialog.dismiss()
    local zipName = (InitReader.field(init, "app_name", name)) .. "-" .. os.date("%Y-%m-%d-%H-%M-%S") .. ".zip"
    pcall(function()
      LuaFileUtil.compress(path, Bean.Path.app_root_dir .. "/Backup", zipName)
      snack(res.string.backup .. ": " .. zipName)
    end)
  end

  layout.button_rename.onClick = function()
    dialog.dismiss()
    MaterialAlertDialogBuilder(activity)
      .setTitle(res.string.dir_name)
      .setView(loadlayout(res.layout.dialog_fileinput, sublayout))
      .setPositiveButton(android.R.string.ok, function()
        local text = sublayout.file_name.getText()
        local new_path = LuaFileUtil.child(tostring(File(path).getParent() or ""), text)
        if not new_path or not isProjectRoot(new_path) then
          snack(res.string.rename_fail)
          return
        end
        local result = tostring(LuaFileUtil.renameWithin(path, text) or "failed")
        if result == "same" then return end
        if result == "exists" then
          snack(res.string.have_same_name)
          return
        end
        if result ~= "ok" then
          snack(res.string.rename_fail)
          if host.renameFailed then host.renameFailed() end
          return
        end
        if host.beforeRename then host.beforeRename() end
        notifyChanged()
      end)
      .setNegativeButton(android.R.string.cancel, nil)
      .show()
    sublayout.file_name.setHint(res.string.rename)
    sublayout.file_name.setText(name)
  end

  layout.button_cdir.onClick = function()
    dialog.dismiss()
    MaterialAlertDialogBuilder(activity)
      .setTitle(res.string.new_dir)
      .setView(loadlayout(res.layout.dialog_fileinput, sublayout))
      .setPositiveButton(android.R.string.ok, function()
        applyCreate(LuaFileUtil.mkdirChild(path, sublayout.file_name.getText()))
      end)
      .setNegativeButton(android.R.string.cancel, nil)
      .show()
    sublayout.file_name.setHint(res.string.new_dir)
  end

  layout.button_cfile.onClick = function()
    dialog.dismiss()
    MaterialAlertDialogBuilder(activity)
      .setTitle(res.string.new_file)
      .setView(loadlayout(res.layout.dialog_fileinput, sublayout))
      .setPositiveButton(android.R.string.ok, function()
        applyCreate(LuaFileUtil.createChild(path, sublayout.file_name.getText(), ""))
      end)
      .setNegativeButton(android.R.string.cancel, nil)
      .show()
    sublayout.file_name.setHint(res.string.new_file)
  end

  layout.button_delete.onClick = function()
    dialog.dismiss()
    MaterialAlertDialogBuilder(activity)
      .setTitle(appName)
      .setMessage(res.string.sure_to_delete)
      .setPositiveButton(android.R.string.ok, function()
        if host.delete then
          host.delete(path)
          return
        end
        if not isProjectRoot(path) then return end
        local called, removed = pcall(function() return LuaFileUtil.removeTree(path) end)
        if not called or removed ~= true or File(path).exists() then
          snack(res.string.ai_delete_failed)
          return
        end
        snack(res.string.ai_deleted)
        if host.refresh then host.refresh() end
      end)
      .setNegativeButton(android.R.string.cancel, nil)
      .show()
  end
end

return _M
