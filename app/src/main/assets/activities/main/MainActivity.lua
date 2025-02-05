require "environment"
import "java.io.File"
import "android.view.View"
import "android.view.WindowManager"
import "android.animation.ObjectAnimator"
import "android.animation.AnimatorSet"
import "androidx.core.view.GravityCompat"
import "androidx.appcompat.widget.PopupMenu"
-- Material
import "com.google.android.material.snackbar.Snackbar"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"

-- private class
local Init = require "activities.main.Init"
-- public class
import "mods.utils.ActivityUtil"
import "mods.utils.EditorUtil"
-- local number
local _exit = 0;

local ColorUtil = this.globalData.ColorUtil
local DecelerateInterpolator = luajava.newInstance "android.view.animation.DecelerateInterpolator"
local res = res

--[[
 ToDo：
 保存上次打开的文件路径
 设置:(0%)
 高亮颜色
 放大镜开关
]]

function onCreate()
    --申请权限
    require "permissions"()
    --设置主题
    activity.setTheme(R.style.Theme_NeLuaJ_Material3_NoActionBar)
    bindClass "com.google.android.material.color.DynamicColors".applyToActivityIfAvailable(this)
    activity.setContentView(res.layout.main_layout)
            .setSupportActionBar(mToolBar)
            .getSupportActionBar() {
        DisplayHomeAsUpEnabled = true,
        Elevation = 0,
        Subtitle = res.string.no_file
    }
    local window = activity.getWindow() {
        SoftInputMode = 0x10,
        StatusBarColor = ColorUtil.getColorBackground()
    }
            .addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
            .clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
    if this.isNightMode() then
        window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_VISIBLE)
    else
        window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR)
    end
    Bean.Path.this_dir = Bean.Path.app_root_pro_dir
    Init.initView().initBar().initCheck()
end

function onRequestPermissionsResult(r, p, g)
    LuaFileUtil.checkDirectory(Bean.Path.app_root_pro_dir)
    checkBackup()
    mRecycler.post(function()
        MainActivity.RecyclerView
                    .init()
                    .update();
    end)
    collectgarbage("collect")

    -- 恢复上次打开的文件
    mLuaEditor.post(function()
        local lastPath = this.getSharedData("lastFile")
        local lastSelect = this.getSharedData("lastSelect")
        if lastPath and File(lastPath).exists() then
            EditorUtil.load(lastPath)
            EditorUtil.setSelection(lastSelect or 0)
        end
    end)
end

--使用home来添加menu按钮
function onOptionsItemSelected(item)
    local id = item.getItemId();
    if id == android.R.id.home then
        if not drawer.isDrawerOpen(GravityCompat.START) then
            EditorUtil.save()
            drawer.openDrawer(GravityCompat.START)
        else
            drawer.closeDrawer(GravityCompat.START)
        end
    end
end

--ActionBar栏Menu
function onCreateOptionsMenu(menu)
    local ColorTitle = ColorUtil.getColorOnBackground();
    local menu_show = 2; --MenuItem.SHOW_AS_ACTION_ALWAYS;
    menu.add(res.string.run_code)
        .setShowAsAction(menu_show)
        .setIcon(this.getResDrawable("play", ColorTitle))
        .onMenuItemClick = function(a)
        -- 如果Editor未显示
        if mLuaEditor.getVisibility() == 4 then
            MainActivity.Public.snack(res.string.no_file)
            return
        end
        EditorUtil.save()
        -- 如果在工程目录内，显示PopupMenu
        if Bean.Project.this_project ~= "" then
            local pop = PopupMenu(activity, mToolBar.getChildAt(3))
            local _menu = pop.Menu
            _menu.add(res.string.run_code .. " " .. File(Bean.Path.this_file).getName())
                 .onMenuItemClick = function(a)
                activity.newActivity(Bean.Path.this_file)
            end
            _menu.add(res.string.run_project)
                 .onMenuItemClick = function(a)
                activity.newActivity(Bean.Path.app_root_pro_dir .. "/" .. Bean.Project.this_project .. "/main.lua")
            end
            pop.show()
        else
            -- 不在工程目录内直接运行
            activity.newActivity(Bean.Path.this_file)
        end
    end
    menu.add(res.string.undo)
        .setShowAsAction(menu_show)
        .setIcon(this.getResDrawable("undo", ColorTitle))
        .onMenuItemClick = function(a)
        mLuaEditor.undo()
    end
    menu.add(res.string.redo)
        .setShowAsAction(menu_show)
        .setIcon(this.getResDrawable("redo", ColorTitle))
        .onMenuItemClick = function(a)
        mLuaEditor.redo()
    end
    -- 文件菜单
    local menu0 = menu.addSubMenu(res.string.file .. "…")
    menu0.add(res.string.save_file).onMenuItemClick = function(a)
        if mLuaEditor.getVisibility() == 4 then
            MainActivity.Public.snack(res.string.no_file)
            return
        end
        switch
        EditorUtil.save()
        -- 目前只有使用okio保存时才能触发这个
        case "same"
        MainActivity.Public.snack(res.string.save_same)
        case
        true
        MainActivity.Public.snack(res.string.save_success)
        default
        MainActivity.Public.snack(res.string.save_fail)
    end
    end
    menu0.add(res.string.compile).onMenuItemClick = function(a)
        local path = Bean.Path.this_file
        if mLuaEditor.getVisibility() == 4 then
            MainActivity.Public.snack(res.string.no_file)
        else
            this.dumpFile(path, path .. "c")
            MainActivity.RecyclerView.update();
        end
    end
    local menu1 = menu.addSubMenu(res.string.code .. "…")
    menu1.add(res.string.format).onMenuItemClick = function(a)
        mLuaEditor.format()
    end
    menu1.add(res.string.check_error).onMenuItemClick = function(a)
        print(mLuaEditor.getError() or res.string.no_error)
    end
    menu1.add(res.string.search).onMenuItemClick = function(a)
        mSearch.setVisibility(0)
        local Anim = AnimatorSet()
        local Y = ObjectAnimator.ofFloat(mSearch, "translationY", { -50, 0 })
        local A = ObjectAnimator.ofFloat(mSearch, "alpha", { 0, 1 })
        Anim.play(A).with(Y)
        Anim.setDuration(500)
            .setInterpolator(DecelerateInterpolator)
            .start()
    end
    menu1.add("Java" .. res.string.editor).onMenuItemClick = function(a)
        MaterialAlertDialogBuilder(this)
                .setTitle(res.string.file_to_open)
                .setView(loadlayout(res.layout.dialog_fileinput))
                .setPositiveButton(android.R.string.ok, function()
            ActivityUtil.new("java", file_name.getText())
        end)
                .setNegativeButton(android.R.string.cancel, nil)
                .show();
        file_name.setHint(res.string.path)
        file_name.setText(Bean.Path.this_file).setSingleLine(false)
    end
    menu1.add(res.string.analysis_import).onMenuItemClick = function(a)
        if mLuaEditor.getVisibility() == 4 then
            MainActivity.Public.snack(res.string.no_file)
            return
        end
        ActivityUtil.new("fix", Bean.Path.this_file)
    end
    local menu2 = menu.addSubMenu(res.string.project .. "…")
    menu2.add(res.string.build).onMenuItemClick = function(a)
        if not this.startPackage("com.nekolaska.Builder") then
            MainActivity.Public.snack(res.string.no_builder)
        end
    end
    menu2.add(res.string.create_project).onMenuItemClick = function(a)
        MainActivity.Public.createProject()
    end
    menu2.add(res.string.backup).onMenuItemClick = function(a)
        if mLuaEditor.getVisibility() == 4 then
            MainActivity.Public.snack(res.string.no_file)
            return
        elseif Bean.Project.this_project == "" then
            MainActivity.Public.snack(res.string.noProject)
            return
        end
        local project_dir = Bean.Path.app_root_pro_dir .. "/" .. Bean.Project.this_project
        local init = LuaFileUtil.loadLua(project_dir .. "/init.lua")
        LuaFileUtil.compress(project_dir, Bean.Path.app_root_dir .. "/Backup", init.app_name .. "-" .. os.date("%Y-%m-%d-%H-%M-%S") .. ".zip")
    end
    --[[
    menu2.add(res.string.migrate).onMenuItemClick = function(a)
        require("mods.utils.ProjectUpdater").moveIfNotExist()
    end
    ]]
    local menu3 = menu.addSubMenu(res.string.tools .. "…")
    menu3.add(res.string.logs).onMenuItemClick = function(a)
        ActivityUtil.showLog(activity)
    end
    menu3.add(res.string.api_title).onMenuItemClick = function(a)
        ActivityUtil.new("api")
    end
    menu3.add(res.string.layout_helper)
         .setShowAsAction(menu_show)
         .onMenuItemClick = function(a)
        -- 如果Editor未显示
        if mLuaEditor.getVisibility() == 4 then
            MainActivity.Public.snack(res.string.no_file)
            return
        end
        EditorUtil.save()
        activity.newActivity(ActivityUtil.lua_path .. "/activities/layouthelper/LayoutHelperActivity.lua", {
            Bean.Path.this_file,
            Bean.Path.app_root_pro_dir .. "/" .. mToolBar.getTitle()
        })
    end
    local menu4 = menu.addSubMenu(res.string.more .. "…")
    menu4.add("NeLuaJ+ " .. res.string.help).onMenuItemClick = function(a)
        ActivityUtil.new("help")
    end
    menu4.add(res.string.about).onMenuItemClick = function(a)
        local t = {}
        MaterialAlertDialogBuilder(this)
                .setTitle(res.string.about)
                .setMessage(res.string.about_this)
                .setView(loadlayout(res.layout.dialog_about, t))
                .setPositiveButton(android.R.string.ok, nil)
                .show()
        t.author.onClick = function()
            xpcall(function()
                import "android.content.Intent"
                import "android.net.Uri"
                local url = "mqqapi://card/show_pslcard?src_type=internal&source=sharecard&version=1&uin=1071723770"
                activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
            end, function()
                MainActivity.Public.snack(res.string.please_install_qq)
            end)
        end
    end
    menu4.add(res.string.setting).onMenuItemClick = function(a)
        ActivityUtil.new("setting")
    end
    menu.add(res.string.exit).onMenuItemClick = function(a)
        activity.finish(true)
    end
end

function onPause()
    if Bean.Path.this_file ~= "" then
        EditorUtil.save()
    end
end

this.addOnBackPressedCallback(function()
    if _exit + 2 > os.time() then
        activity.finish(true)
    else
        --返回先关闭侧滑栏
        if drawer.isDrawerOpen(GravityCompat.START) then
            drawer.closeDrawer(GravityCompat.START)
        elseif mSearch.getVisibility() == 0 then
            local Anim = AnimatorSet()
            local Y = ObjectAnimator.ofFloat(mSearch, "translationY", { 0, -50 })
            local A = ObjectAnimator.ofFloat(mSearch, "alpha", { 1, 0 })
            Anim.play(A).with(Y)
            Anim.setDuration(500)
                .setInterpolator(DecelerateInterpolator)
                .start()
            this.delay(500, function()
                mSearch.setVisibility(8)
            end)
        else
            EditorUtil.save()
            Snackbar.make(coordinatorLayout, res.string.confirm_exit, Snackbar.LENGTH_SHORT)
                    .setAnchorView(ps_bar)
                    .setAction(res.string.exit, function(v)
                activity.finish(true)
            end)    .show();
            _exit = os.time()
        end
    end
end)
