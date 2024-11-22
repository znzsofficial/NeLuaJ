import "java.io.File"
import "android.content.Intent"
import "android.webkit.MimeTypeMap"
import "android.net.Uri"
import "com.google.android.material.snackbar.Snackbar"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"
local BottomSheetDialog = bindClass "com.google.android.material.bottomsheet.BottomSheetDialog"
local LuaUtil = bindClass "com.androlua.LuaUtil"
local TabUtil = require "mods.utils.TabUtil"
local res = res

local _M = {}

-- public method
function _M.snack(arg)
    if coordinatorLayout then
        return Snackbar.make(coordinatorLayout, tostring(arg), Snackbar.LENGTH_SHORT)
                       .setAnimationMode(Snackbar.ANIMATION_MODE_SIDE)
                       .setAnchorView(ps_bar)
                       .show();
    end
end

function _M.deleteFile(path, position)
    LuaUtil.rmDir(File(path))
    MainActivity.RecyclerView.delete(path)
    adapter_rv.notifyItemRemoved(position)
end

function _M.newDir(path)
    swipeRefresh.setRefreshing(true)
    File(path).mkdirs()
    MainActivity.RecyclerView.update()
end

function _M.createProject(name)
    local binding = {}
    local project_dlg = MaterialAlertDialogBuilder(this)
            .setTitle(res.string.create_project)
            .setView(loadlayout(res.layout.new_project, binding))
    for i = 1, 1000 do
        if File(Bean.Path.app_root_pro_dir .. "/demo" .. i).exists() then
            continue
        else
            binding.project_appName.setText("demo" .. i)
            binding.project_packageName.setText("com.neluaj.demo" .. i)
            break
        end
    end
    project_dlg.setPositiveButton(android.R.string.ok, function()
        local appname = binding.project_appName.getText().toString()
        local packagename = binding.project_packageName.getText().toString()
        local base_path = Bean.Path.app_root_pro_dir .. "/" .. appname
        local f = File(base_path)
        if f.exists() then
            _M.snack("工程已存在")
            return
        end
        File(base_path .. "/libs").mkdirs()
        File(base_path .. "/mods").mkdirs()
        File(base_path .. "/res/font").mkdirs()
        File(base_path .. "/res/string").mkdirs()
        File(base_path .. "/res/dimen").mkdirs()
        File(base_path .. "/res/drawable").mkdirs()
        File(base_path .. "/res/layout").mkdirs()
        File(base_path .. "/res/color").mkdirs()
        LuaFileUtil
                .create(base_path .. "/main.lua", res.string.mcode)
                .create(base_path .. "/init.lua", 'app_name = "' .. appname .. '"\npackage_name = "' .. packagename .. '"\n' .. res.string.icode)
                .create(base_path .. "/res/string/init.lua", 'app_title="' .. appname .. '"')
                .create(base_path .. "/res/string/en.lua", '--English')
                .create(base_path .. "/res/string/zh.lua", '--Chinese')
                .create(base_path .. "/res/string/default.lua", 'return "en"')
                .create(base_path .. "/res/dimen/init.lua", '')
                .create(base_path .. "/res/dimen/land.lua", '')
                .create(base_path .. "/res/dimen/port.lua", '')
                .create(base_path .. "/res/color/init.lua", '')
                .create(base_path .. "/res/color/day.lua", '')
                .create(base_path .. "/res/color/night.lua", '')
                .create(base_path .. "/res/layout/main.lua", res.string.lcode)
        if binding.module_class.isChecked() then
            LuaFileUtil.create(base_path .. "/mods/class.lua", res.string.code_class)
        end
        if binding.module_array.isChecked() then
            LuaFileUtil.create(base_path .. "/mods/Array.lua", res.string.code_array)
        end
        if binding.module_strings.isChecked() then
            LuaFileUtil.create(base_path .. "/mods/Strings.lua", res.string.code_strings)
        end
        if binding.module_rxlua.isChecked() then
            LuaUtil.copyFile(this.getLuaDir("rx.lua"), base_path .. "/mods/rx.lua")
        end
        if binding.module_anim.isChecked() then
            LuaFileUtil.create(base_path .. "/mods/ObjectAnimator.lua", res.string.code_anim)
        end
        MainActivity.RecyclerView.update();
    end)
               .setNegativeButton(android.R.string.cancel, nil)
               .show();
    return _M
end

function _M.fileMenu(path, name, position)
    local layout = {}
    local sublayout = {}
    -- 顺便把name传进来，省得再获取一次
    local fileDialog = BottomSheetDialog(activity)
    fileDialog.setContentView(loadlayout(res.layout.file_menu, layout)).show()
    fileDialog.dismissWithAnimation = true
    layout.pathText.setText(path)
    layout.nameText.setText(name)
    layout.button_delete.onClick = function(v)
        fileDialog.dismiss()
        MaterialAlertDialogBuilder(activity)
                .setTitle(name)
                .setMessage(res.string.sure_to_delete)
                .setPositiveButton(android.R.string.ok, function()
            TabUtil.remove(path)
            _M.deleteFile(path, position)
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
                .setTitle("新建文件夹")
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
    end
    layout.button_cfile.onClick = function()
        fileDialog.dismiss()
        MaterialAlertDialogBuilder(activity)
                .setTitle("新建文件")
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
    end
end

function _M.dirMenu(path, name, position)
    local layout = {}
    local sublayout = {}
    local dirDialog = BottomSheetDialog(activity)
    dirDialog.setContentView(loadlayout(res.layout.dir_menu, layout)).show()
    dirDialog.dismissWithAnimation = true
    layout.pathText.setText(path)
    layout.nameText.setText(name)
    layout.button_delete.onClick = function()
        dirDialog.dismiss()
        MaterialAlertDialogBuilder(activity)
                .setTitle(name)
                .setMessage(res.string.sure_to_delete)
                .setPositiveButton(android.R.string.ok, function()
            _M.deleteFile(path, position)
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
                .setTitle("新建文件夹")
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
                .show();
    end
    layout.button_cfile.onClick = function()
        dirDialog.dismiss()
        MaterialAlertDialogBuilder(activity)
                .setTitle("新建文件")
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
                .show();
    end
end

--[[
function _M.build()
    local layout = {}
    MaterialAlertDialogBuilder(activity)
            .setTitle(res.string.build)
            .setView(loadlayout(res.layout.dialog_build, layout))
            .setPositiveButton(android.R.string.ok, function()
        local LuaBuildUtil = bindClass "github.znzsofficial.utils.LuaBuildUtil"
        local bins = LuaBuildUtil(activity)
        local path = layout.pro_path.getText()
        bins.startBin(path, Bean.Path.app_root_dir)
    end)
            .setNegativeButton(android.R.string.cancel, nil)
            .show();
    layout.pro_path.setText(Bean.Path.app_root_pro_dir .. "/" .. Bean.Project.this_project)
end
]]

function _M.dexDialog(path)
    local file = File(path)
    MaterialAlertDialogBuilder(activity)
            .setTitle(file.name)
            .setMessage(res.string.select_action)
            .setNeutralButton(res.string.read_only, function()
        file.setReadOnly()
    end)
            .setPositiveButton(res.string.open, function()
        this.openFile(path, function()
            MainActivity.Public.snack(res.string.NoSupport)
        end)
    end)
            .setNegativeButton(android.R.string.cancel, nil)
            .show();
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

--[[
function _M.openFile(path, FileName)
    try
    local ExtensionName = FileName:match("%.(.+)")
    local Mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ExtensionName)
    local intent = Intent();
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    intent.setAction(Intent.ACTION_VIEW);
    local uri = activity.getUriForPath(path)
    if Mime then
        intent.setDataAndType(uri, Mime);
    else
        intent.setDataAndType(uri, "text/*");
    end
    activity.startActivity(intent);
    catch(e)
    _M.snack("暂不支持打开此文件")
end
end


function _M.signApk()
MaterialAlertDialogBuilder(activity)
.setTitle("目标文件")
.setView(loadlayout(res.layout.dialog_fileinput))
.setPositiveButton(android.R.string.ok, function ()
import "apksigner.Signer"
local oldpath = tostring(file_name.getText())
local new = oldpath:gsub(".apk", "").."_signed.apk"
os.remove(new)
Signer.sign(oldpath, new)
os.remove(oldpath)
end )
.setNegativeButton(android.R.string.cancel, nil)
.show();
file_name.setText(Bean.Path.app_root_dir.."/bin/").setSingleLine(false)
end
]]

return _M