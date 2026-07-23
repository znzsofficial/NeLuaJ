import "java.io.File"
import "android.content.Intent"
import "android.webkit.MimeTypeMap"
import "android.net.Uri"
import "com.google.android.material.snackbar.Snackbar"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"
local BottomSheetDialog = bindClass "com.google.android.material.bottomsheet.BottomSheetDialog"
local BottomSheetBehavior = bindClass "com.google.android.material.bottomsheet.BottomSheetBehavior"
local LuaUtil = bindClass "com.androlua.LuaUtil"
local TabUtil = require "mods.utils.TabUtil"
import "mods.utils.EditorUtil"
import "mods.utils.PathManager"
local res = res

local _M = {}

-- 部分机型 BottomSheet 停在半展开，需手动上拉。
-- 在 OnShowListener 里拿 design_bottom_sheet 再设 Behavior，比 content.post 更稳。
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
  pcall(function()
    local sheet = resolveSheetContainer(dialog, content)
    if not sheet then return end

    -- wrap_content：按内容高度撑开，避免固定半屏
    pcall(function()
      local lp = sheet.getLayoutParams()
      if lp then
        lp.height = -2 -- WRAP_CONTENT
        sheet.setLayoutParams(lp)
      end
    end)

    local behavior
    pcall(function() behavior = dialog.getBehavior() end)
    if not behavior then
      behavior = BottomSheetBehavior.from(sheet)
    end
    if not behavior then return end

    pcall(function() behavior.setFitToContents(true) end)
    pcall(function() behavior.setSkipCollapsed(true) end)
    pcall(function() behavior.setDraggable(true) end)
    -- 提高半展开比例，减少停在中间档的概率（Material 1.x+）
    pcall(function() behavior.setHalfExpandedRatio(0.92) end)
    pcall(function() behavior.setExpandedOffset(0) end)

    local h = 0
    pcall(function()
      h = content and content.getMeasuredHeight() or 0
      if (not h or h <= 0) and sheet.getMeasuredHeight then
        h = sheet.getMeasuredHeight()
      end
    end)
    if h and h > 0 then
      pcall(function() behavior.setPeekHeight(h) end)
    else
      -- 尚未 measure 时给够高的 peek，避免只露一截
      pcall(function()
        local dm = activity.getResources().getDisplayMetrics()
        behavior.setPeekHeight(math.floor(dm.heightPixels * 0.7))
      end)
    end
    behavior.setState(BottomSheetBehavior.STATE_EXPANDED)
  end)
end

local function showBottomSheet(dialog, content)
  pcall(function() dialog.dismissWithAnimation = true end)
  dialog.setContentView(content)
  -- show 之后系统可能把 state 改回 collapsed/half；用 OnShow 再强制一次
  pcall(function()
    dialog.setOnShowListener(function()
      expandBottomSheet(dialog, content)
      if content then
        pcall(function()
          content.post(function()
            expandBottomSheet(dialog, content)
          end)
        end)
      end
    end)
  end)
  dialog.show()
  -- 无 OnShow 回调的兼容路径
  expandBottomSheet(dialog, content)
  return dialog
end

-- public method
function _M.snack(arg)
    if coordinatorLayout then
        return Snackbar.make(coordinatorLayout, tostring(arg), Snackbar.LENGTH_SHORT)
                       .setAnimationMode(Snackbar.ANIMATION_MODE_SIDE)
                       .setAnchorView(ps_bar)
                       .show();
    end
end

function _M.deleteFile(path)
    LuaUtil.rmDir(File(path))
    -- 通过 path 查找实际索引，避免对话框确认后 position 过时
    local pos = MainActivity.RecyclerView.delete(path)
    if pos then
        adapter_rv.notifyItemRemoved(pos - 1) -- Lua 1-based → adapter 0-based
    else
        adapter_rv.notifyDataSetChanged()
    end
end

function _M.newDir(path)
    swipeRefresh.setRefreshing(true)
    File(path).mkdirs()
    MainActivity.RecyclerView.update()
end

function _M.createProject(name)
    require("activities.main.CreateProject").show({
        snack = function(msg) _M.snack(msg) end,
    })
    return _M
end

function _M.fileMenu(path, name)
    local layout = {}
    local sublayout = {}
    -- 顺便把name传进来，省得再获取一次
    local fileDialog = BottomSheetDialog(activity)
    local fileContent = loadlayout(res.layout.file_menu, layout)
    showBottomSheet(fileDialog, fileContent)
    layout.pathText.setText(path)
    layout.nameText.setText(name)
    layout.button_copy.onClick = function()
        fileDialog.dismiss()
        MainActivity.RecyclerView.copyPaths({ path })
    end
    layout.button_cut.onClick = function()
        fileDialog.dismiss()
        MainActivity.RecyclerView.cutPaths({ path })
    end
    layout.button_delete.onClick = function(v)
        fileDialog.dismiss()
        MaterialAlertDialogBuilder(activity)
                .setTitle(name)
                .setMessage(res.string.sure_to_delete)
                .setPositiveButton(android.R.string.ok, function()
            TabUtil.remove(path)
            _M.deleteFile(path)
        end)
                .setNegativeButton(android.R.string.cancel, nil)
                .show();
    end
    layout.button_rename.onClick = function()
        fileDialog.dismiss()
        MaterialAlertDialogBuilder(activity)
                .setTitle(res.string.file_name)
                .setView(loadlayout(res.layout.dialog_fileinput, sublayout))
                .setPositiveButton(android.R.string.ok, function()
            local new_path = Bean.Path.this_dir .. "/" .. tostring(sublayout.file_name.getText())
            if File(new_path).exists() then
                _M.snack(res.string.have_same_name)
                return
            end
            swipeRefresh.setRefreshing(true)
            LuaFileUtil.rename(path, new_path)
            MainActivity.RecyclerView.update()
            TabUtil.remove(path)
        end)
                .setNegativeButton(android.R.string.cancel, nil)
                .show();
        sublayout.file_name.setHint(res.string.rename)
        sublayout.file_name.setText(name)
    end
    layout.button_cdir.onClick = function()
        fileDialog.dismiss()
        MaterialAlertDialogBuilder(activity)
                .setTitle(res.string.new_dir)
                .setView(loadlayout(res.layout.dialog_fileinput, sublayout))
                .setPositiveButton(android.R.string.ok, function()
            local new_path = Bean.Path.this_dir .. "/" .. tostring(sublayout.file_name.getText())
            if File(new_path).exists() then
                _M.snack(res.string.have_same_name)
            else
                _M.newDir(new_path)
                _M.snack(res.string.create_success)
            end
        end)
                .setNegativeButton(android.R.string.cancel, nil)
                .show();
        sublayout.file_name.setHint(res.string.new_dir)
    end
    layout.button_cfile.onClick = function()
        fileDialog.dismiss()
        MaterialAlertDialogBuilder(activity)
                .setTitle(res.string.new_file)
                .setView(loadlayout(res.layout.dialog_fileinput, sublayout))
                .setPositiveButton(android.R.string.ok, function()
            local new_path = Bean.Path.this_dir .. "/" .. tostring(sublayout.file_name.getText())
            if File(new_path).exists() then
                _M.snack(res.string.have_same_name)
            else
                swipeRefresh.setRefreshing(true)
                LuaFileUtil.create(new_path, "")
                _M.snack(res.string.create_success)
                MainActivity.RecyclerView.update()
            end
        end)
                .setNegativeButton(android.R.string.cancel, nil)
                .show();
        sublayout.file_name.setHint(res.string.new_file)
    end
end

local function isProjectFolder(path)
    local f = File(path)
    local parent = f.getParent()
    if not parent or parent ~= Bean.Path.app_root_pro_dir then
        return false
    end
    return File(path .. "/init.lua").isFile() or File(path .. "/main.lua").isFile()
end

local function readProjectInit(path)
    local initPath = path .. "/init.lua"
    if not File(initPath).isFile() then
        return nil
    end
    local ok, t = pcall(function()
        return LuaFileUtil.loadLua(initPath)
    end)
    if ok and type(t) == "table" then
        return t
    end
    return nil
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

function _M.projectMenu(path, name)
    local layout = {}
    local sublayout = {}
    local dialog = BottomSheetDialog(activity)
    local projectContent = loadlayout(res.layout.project_menu, layout)
    showBottomSheet(dialog, projectContent)

    local init = readProjectInit(path)
    local appName = initField(init, "app_name", initField(init, "appname", name))
    local packageName = initField(init, "package_name", "—")
    local verName = initField(init, "ver_name", initField(init, "version_name", "—"))
    local verCode = initField(init, "ver_code", initField(init, "version_code", "—"))
    local minSdk = initField(init, "min_sdk", "—")
    local targetSdk = initField(init, "target_sdk", "—")
    -- 与 initENV 一致：NeLuaJ_Theme 优先
    local theme = initField(init, "NeLuaJ_Theme", nil)
    if not theme or theme == "" then
      local t = initField(init, "theme", "—")
      if type(t) == "string" and t:find("^Theme_NeLuaJ_") then
        theme = t
      else
        theme = t or "—"
      end
    end
    local debugMode = initField(init, "debug_mode", initField(init, "debugmode", "—"))
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

    -- 图标：项目 icon.png / 默认 AS 圆规
    pcall(function()
        local size = this.dpToPx(56)
        local iconFile = File(path .. "/icon.png")
        if iconFile.isFile() then
            local BitmapFactory = luajava.bindClass "android.graphics.BitmapFactory"
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
        PathManager.updateDir(path)
        filetab.setPath(path)
        MainActivity.RecyclerView.update()
    end

    layout.button_settings.onClick = function()
        dialog.dismiss()
        pcall(function()
            local Init = require "activities.main.Init"
            if Init.Actions and Init.Actions.openProjectSettings then
                Init.Actions.openProjectSettings(path)
            else
                local ActivityUtil = require "mods.utils.ActivityUtil"
                ActivityUtil.open("project_settings", path)
            end
        end)
    end

    layout.button_open_init.onClick = function()
        dialog.dismiss()
        local initPath = path .. "/init.lua"
        if File(initPath).isFile() then
            EditorUtil.fromRecy = true
            EditorUtil.load(initPath)
            pcall(function()
                local Init = require "activities.main.Init"
                if not (Init.isTabletMode and Init.isTabletMode()) then
                    drawer.closeDrawer(luajava.bindClass("androidx.core.view.GravityCompat").START)
                end
            end)
        else
            _M.snack(res.string.project_no_init)
        end
    end

    layout.button_run.onClick = function()
        dialog.dismiss()
        local mainPath = path .. "/main.lua"
        if not File(mainPath).isFile() then
            _M.snack(res.string.project_no_main)
            return
        end
        pcall(function()
            local Init = require "activities.main.Init"
            if Init.Actions and Init.Actions.runProject then
                -- 临时切到该工程再运行
                Bean.Project.this_project = name
                Init.Actions.runProject()
            else
                activity.newActivity(mainPath)
            end
        end)
    end

    layout.button_backup.onClick = function()
        dialog.dismiss()
        local initTbl = init or {}
        local zipName = (initField(initTbl, "app_name", name)) .. "-" .. os.date("%Y-%m-%d-%H-%M-%S") .. ".zip"
        pcall(function()
            LuaFileUtil.compress(path, Bean.Path.app_root_dir .. "/Backup", zipName)
            _M.snack(res.string.backup .. ": " .. zipName)
        end)
    end

    layout.button_rename.onClick = function()
        dialog.dismiss()
        MaterialAlertDialogBuilder(activity)
                .setTitle(res.string.dir_name)
                .setView(loadlayout(res.layout.dialog_fileinput, sublayout))
                .setPositiveButton(android.R.string.ok, function()
            local new_path = Bean.Path.this_dir .. "/" .. tostring(sublayout.file_name.getText())
            if File(new_path).exists() then
                _M.snack(res.string.have_same_name)
                return
            end
            swipeRefresh.setRefreshing(true)
            LuaFileUtil.rename(path, new_path)
            MainActivity.RecyclerView.update()
            TabUtil.checkAll()
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
            local new_path = path .. "/" .. tostring(sublayout.file_name.getText())
            if File(new_path).exists() then
                _M.snack(res.string.have_same_name)
            else
                File(new_path).mkdirs()
                _M.snack(res.string.create_success)
            end
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
            local new_path = path .. "/" .. tostring(sublayout.file_name.getText())
            if File(new_path).exists() then
                _M.snack(res.string.have_same_name)
            else
                LuaFileUtil.create(new_path, "")
                _M.snack(res.string.create_success)
            end
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
            _M.deleteFile(path)
            TabUtil.checkAll()
        end)
                .setNegativeButton(android.R.string.cancel, nil)
                .show()
    end
end

function _M.dirMenu(path, name)
    if isProjectFolder(path) then
        return _M.projectMenu(path, name)
    end

    local layout = {}
    local sublayout = {}
    local dirDialog = BottomSheetDialog(activity)
    local dirContent = loadlayout(res.layout.dir_menu, layout)
    showBottomSheet(dirDialog, dirContent)
    layout.pathText.setText(path)
    layout.nameText.setText(name)
    layout.button_copy.onClick = function()
        dirDialog.dismiss()
        MainActivity.RecyclerView.copyPaths({ path })
    end
    layout.button_cut.onClick = function()
        dirDialog.dismiss()
        MainActivity.RecyclerView.cutPaths({ path })
    end
    layout.button_delete.onClick = function()
        dirDialog.dismiss()
        MaterialAlertDialogBuilder(activity)
                .setTitle(name)
                .setMessage(res.string.sure_to_delete)
                .setPositiveButton(android.R.string.ok, function()
            _M.deleteFile(path)
            TabUtil.checkAll()
        end)
                .setNegativeButton(android.R.string.cancel, nil)
                .show();
    end
    layout.button_rename.onClick = function()
        dirDialog.dismiss()
        MaterialAlertDialogBuilder(activity)
                .setTitle(res.string.dir_name)
                .setView(loadlayout(res.layout.dialog_fileinput, sublayout))
                .setPositiveButton(android.R.string.ok, function()
            local new_path = Bean.Path.this_dir .. "/" .. tostring(sublayout.file_name.getText())
            if File(new_path).exists() then
                _M.snack(res.string.have_same_name)
                return
            end
            swipeRefresh.setRefreshing(true)
            LuaFileUtil.rename(path, new_path)
            MainActivity.RecyclerView.update()
            TabUtil.checkAll()
        end)
                .setNegativeButton(android.R.string.cancel, nil)
                .show();
        sublayout.file_name.setHint(res.string.rename)
        sublayout.file_name.setText(name)
    end
    layout.button_cdir.onClick = function()
        dirDialog.dismiss()
        MaterialAlertDialogBuilder(activity)
                .setTitle(res.string.new_dir)
                .setView(loadlayout(res.layout.dialog_fileinput, sublayout))
                .setPositiveButton(android.R.string.ok, function()
            local new_path = path .. "/" .. tostring(sublayout.file_name.getText())
            if File(new_path).exists() then
                _M.snack(res.string.have_same_name)
            else
                File(new_path).mkdirs()
                _M.snack(res.string.create_success)
                if Bean.Path.this_dir == path then
                    MainActivity.RecyclerView.update()
                end
            end
        end)
                .setNegativeButton(android.R.string.cancel, nil)
                .show();
        sublayout.file_name.setHint(res.string.new_dir)
    end
    layout.button_cfile.onClick = function()
        dirDialog.dismiss()
        MaterialAlertDialogBuilder(activity)
                .setTitle(res.string.new_file)
                .setView(loadlayout(res.layout.dialog_fileinput, sublayout))
                .setPositiveButton(android.R.string.ok, function()
            local new_path = path .. "/" .. tostring(sublayout.file_name.getText())
            if File(new_path).exists() then
                _M.snack(res.string.have_same_name)
            else
                LuaFileUtil.create(new_path, "")
                _M.snack(res.string.create_success)
                if Bean.Path.this_dir == path then
                    MainActivity.RecyclerView.update()
                end
            end
        end)
                .setNegativeButton(android.R.string.cancel, nil)
                .show();
        sublayout.file_name.setHint(res.string.new_file)
    end
end

function _M.dexDialog(path)
    local file = File(path)
    local dialog = MaterialAlertDialogBuilder(activity)
            .setTitle(file.name)
            .setMessage(res.string.select_action)
    -- 分析类：跳转到 API 页面，传入 dex 路径
    dialog.setPositiveButton(res.string.api_title, function()
        activity.newActivity(
            activity.getLuaPath("activities/api/ApiActivity.lua"),
            { "dex:" .. path }
        )
    end)
    dialog.setNeutralButton(res.string.open, function()
        this.openFile(path, function()
            MainActivity.Public.snack(res.string.NoSupport)
        end)
    end)
    dialog.setNegativeButton(android.R.string.cancel, nil)
    dialog.show()
end

function _M.InstallApk(filePath)
    local intent = Intent(Intent.ACTION_VIEW)
    intent.addCategory("android.intent.category.DEFAULT")
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    local uri = activity.getUriForPath(filePath)
    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    intent.setDataAndType(uri, "application/vnd.android.package-archive")
    activity.startActivity(intent)
end

return _M