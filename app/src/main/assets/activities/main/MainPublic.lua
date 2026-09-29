import "java.io.File"
import "android.content.Intent"
import "android.webkit.MimeTypeMap"
import "android.net.Uri"
import "com.google.android.material.snackbar.Snackbar"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"
local BottomSheetDialog = bindClass "com.google.android.material.bottomsheet.BottomSheetDialog"
local BottomSheetBehavior = bindClass "com.google.android.material.bottomsheet.BottomSheetBehavior"
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
  local sheet = resolveSheetContainer(dialog, content)
  if not sheet then return end

  -- wrap_content：按内容高度撑开，避免固定半屏
  local lp = sheet.getLayoutParams()
  if lp then
    lp.height = -2 -- WRAP_CONTENT
    sheet.setLayoutParams(lp)
  end

  local behavior
  pcall(function() behavior = dialog.getBehavior() end)
  if not behavior then
    behavior = BottomSheetBehavior.from(sheet)
  end
  if not behavior then return end

  -- 这些 setter 随 Material 版本才有。缺一个就跳过，不能让弹层因此打不开。
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
  -- show 之后系统可能把 state 改回 collapsed/half；用 OnShow 再强制一次
  dialog.setOnShowListener(function()
    expandBottomSheet(dialog, content)
    if content then
      content.post(function()
        expandBottomSheet(dialog, content)
      end)
    end
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
    LuaFileUtil.removeTree(path)
    -- Rebuild on the normal refresh path so a pending directory scan cannot
    -- interleave an item-range update with a complete dataset replacement.
    MainActivity.RecyclerView.update()
end

local function nameResult(result)
    return tostring(result or "failed")
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
            local text = sublayout.file_name.getText()
            local new_path = LuaFileUtil.child(Bean.Path.this_dir, text)
            if not new_path then
                _M.snack(res.string.rename_fail)
                return
            end
            local wasCurrent = EditorUtil.currentFile() == path
            if wasCurrent then
                local ok, saved = pcall(EditorUtil.save)
                if not ok or (saved ~= true and saved ~= "same") then
                    _M.snack(res.string.save_fail)
                    return
                end
            end
            local result = nameResult(LuaFileUtil.renameWithin(path, text))
            if result == "same" then return end
            if result == "exists" then
                _M.snack(res.string.have_same_name)
                return
            end
            if result ~= "ok" then
                _M.snack(res.string.rename_fail)
                return
            end
            swipeRefresh.setRefreshing(true)
            if wasCurrent then
                EditorUtil.rebindPath(new_path)
                TabUtil.add(new_path, { select = false })
            end
            TabUtil.remove(path)
            if wasCurrent then
                local entry = TabUtil.Table[new_path]
                if entry and entry.obj then entry.obj.select() end
            end
            MainActivity.RecyclerView.update()
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
            local result = nameResult(LuaFileUtil.mkdirChild(Bean.Path.this_dir, sublayout.file_name.getText()))
            if result == "exists" then
                _M.snack(res.string.have_same_name)
            elseif result == "ok" then
                swipeRefresh.setRefreshing(true)
                MainActivity.RecyclerView.update()
                _M.snack(res.string.create_success)
            else
                _M.snack(res.string.rename_fail)
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
            local result = nameResult(LuaFileUtil.createChild(Bean.Path.this_dir, sublayout.file_name.getText(), ""))
            if result == "exists" then
                _M.snack(res.string.have_same_name)
            elseif result == "ok" then
                swipeRefresh.setRefreshing(true)
                _M.snack(res.string.create_success)
                MainActivity.RecyclerView.update()
            else
                _M.snack(res.string.rename_fail)
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

function _M.projectMenu(path, name)
    require("mods.project.ProjectMenu").show(path, name, {
        snack = function(msg) _M.snack(msg) end,
        parentDir = Bean.Path.this_dir,
        open = function(projectPath)
            PathManager.updateDir(projectPath)
            filetab.setPath(projectPath)
            MainActivity.RecyclerView.update()
        end,
        openSettings = function(projectPath)
            pcall(function()
                local Init = require "activities.main.Init"
                if Init.Actions and Init.Actions.openProjectSettings then
                    Init.Actions.openProjectSettings(projectPath)
                else
                    require("mods.utils.ActivityUtil").open("project_settings", projectPath)
                end
            end)
        end,
        openInit = function(initPath)
            EditorUtil.fromRecy = true
            EditorUtil.load(initPath)
            pcall(function()
                local Init = require "activities.main.Init"
                if not (Init.isTabletMode and Init.isTabletMode()) then
                    drawer.closeDrawer(luajava.bindClass("androidx.core.view.GravityCompat").START)
                end
            end)
        end,
        run = function(projectPath, projectName)
            pcall(function()
                local Init = require "activities.main.Init"
                if Init.Actions and Init.Actions.runProject then
                    Bean.Project.this_project = projectName
                    Init.Actions.runProject()
                else
                    activity.newActivity(projectPath .. "/main.lua")
                end
            end)
        end,
        beforeRename = function()
            swipeRefresh.setRefreshing(true)
        end,
        renameFailed = function()
            swipeRefresh.setRefreshing(false)
        end,
        afterRename = function()
            MainActivity.RecyclerView.update()
            TabUtil.checkAll()
        end,
        delete = function(projectPath)
            _M.deleteFile(projectPath)
            TabUtil.checkAll()
        end,
    })
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
            local text = sublayout.file_name.getText()
            local result = nameResult(LuaFileUtil.renameWithin(path, text))
            if result == "same" then return end
            if result == "exists" then
                _M.snack(res.string.have_same_name)
                return
            end
            if result ~= "ok" then
                _M.snack(res.string.rename_fail)
                return
            end
            swipeRefresh.setRefreshing(true)
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
            local result = nameResult(LuaFileUtil.mkdirChild(path, sublayout.file_name.getText()))
            if result == "exists" then
                _M.snack(res.string.have_same_name)
            elseif result == "ok" then
                _M.snack(res.string.create_success)
                if Bean.Path.this_dir == path then
                    MainActivity.RecyclerView.update()
                end
            else
                _M.snack(res.string.rename_fail)
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
            local result = nameResult(LuaFileUtil.createChild(path, sublayout.file_name.getText(), ""))
            if result == "exists" then
                _M.snack(res.string.have_same_name)
            elseif result == "ok" then
                _M.snack(res.string.create_success)
                if Bean.Path.this_dir == path then
                    MainActivity.RecyclerView.update()
                end
            else
                _M.snack(res.string.rename_fail)
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
        -- 路由锚定脚本根：编辑器环境的 getLuaPath 会锚到 activities/main
        local ActivityUtil = require "mods.utils.ActivityUtil"
        activity.newActivity(
            ActivityUtil.path("api"),
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
