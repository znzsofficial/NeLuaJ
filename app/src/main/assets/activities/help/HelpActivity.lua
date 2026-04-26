require "environment"
import "com.androlua.adapter.LuaAdapter"
import "android.view.KeyEvent"
import "android.view.WindowManager"
import "android.view.View"
import "android.graphics.drawable.ColorDrawable"
local LuaFileUtil = luajava.bindClass "com.nekolaska.io.LuaFileUtil".INSTANCE
local ColorUtil = this.themeUtil
local res = res
this.dynamicColor()
activity.setTitle("NeLuaJ+" .. res.string.help)
    .setContentView(res.layout.help_layout)
    .getSupportActionBar() {
    Elevation = 0,
    BackgroundDrawable = ColorDrawable(ColorUtil.getColorBackground()),
    DisplayShowTitleEnabled = true,
    DisplayHomeAsUpEnabled = true
}

local window = activity.getWindow()
    .setNavigationBarColor(0)
    .setStatusBarColor(ColorUtil.getColorBackground())
    .addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
    .clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
if this.isNightMode() then
    window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_VISIBLE)
else
    window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR)
end

function onOptionsItemSelected(m)
    if m.getItemId() == android.R.id.home then
        if vpg.getCurrentItem() ~= 0 then
            vpg.setCurrentItem(0)
            activity.setTitle("NeLuaJ+" .. res.string.help)
        else
            activity.finish()
        end
    end
end

local MaterialTextView = luajava.bindClass "com.google.android.material.textview.MaterialTextView"
local LinearLayout = luajava.bindClass "android.widget.LinearLayout"
local item = {
    LinearLayout,
    layout_height = "-2",
    layout_width = "-1",
    paddingLeft = "16dp",
    paddingRight = "16dp",
    paddingTop = "12dp",
    paddingBottom = "12dp",
    {
        MaterialTextView,
        id = "text",
        layout_height = "-2",
        layout_width = "-1",
        textColor = ColorUtil.getColorPrimary(),
        textSize = "16sp",
    },
}

local docLanguage = res.language:find("zh") and "zh" or "en"
local data = {
    -- 入门指南
    { text = res.string.migration_guide,      file = "migration_" .. docLanguage .. ".md" },
    { text = res.string.md3_design,           file = "md3_design.md" },
    { text = res.string.layout_reference,     file = "layout_reference.md" },
    { text = res.string.utility_api,          file = "utility_api.md" },
    { text = "Color API",                     file = "color_api.md" },
    -- 基础文档
    { text = "init.lua",                      file = "init_lua_" .. docLanguage .. ".md" },
    { text = res.string.global,               file = "global_env.md" },
    { text = "LuaJ++",                        file = "LuaJ++.md" },
    { text = res.string.backup_crash,         file = "backup_crash.md" },
    -- 模块
    { text = "res " .. res.string._module,    file = "module_res.md" },
    { text = "okhttp " .. res.string._module, file = "module_okhttp.md" },
    { text = "loadlayout",                    file = "module_loadlayout.md" },
    { text = "file " .. res.string._module,   file = "module_file.md" },
    { text = "saf " .. res.string._module,    file = "module_saf.md" },
    { text = "ext " .. res.string._module,    file = "module_ext.md" },
    { text = "lazy",                          file = "lazy.md" },
    { text = "xTask",                         file = "xTask.md" },
    -- 组件
    { text = "LuaActivity",                   file = "LuaActivity.md" },
    { text = "LuaCustRecyclerAdapter",        file = "LuaCustRecyclerAdapter.md" },
    { text = "LuaFragment",                   file = "LuaFragment.md" },
    { text = "LuaFragmentAdapter",            file = "LuaFragmentAdapter.md" },
    { text = "LuaPagerAdapter",               file = "LuaPagerAdapter.md" },
    { text = "LuaPreferenceFragment",         file = "LuaPreferenceFragment.md" },
    { text = "LuaRecyclerAdapter",            file = "LuaRecyclerAdapter.md" },
    { text = "LuaThemeUtil",                  file = "LuaThemeUtil.md" },
    { text = "MaterialTextField",             file = "MaterialTextField.md" },
    { text = "Coil",                          file = "Coil.md" },
    -- 其他
    { text = "FileObserver",                  file = "other_FileObserver.md" },
    { text = "FastScrollerBuilder",           file = "other_FastScrollerBuilder.md" },
}

local adp = LuaAdapter(activity, data, item)
lv.setAdapter(adp)

lv.onItemClick = function(l, v, p, i)
    activity.setTitle(data[i].text)
    vpg.setCurrentItem(1)
    local md = LuaFileUtil.read(activity.getLuaDir() .. "/res/doc/" .. data[i].file)
    webView.loadFromText(md)
end

this.addOnBackPressedCallback(function()
    if vpg.getCurrentItem() ~= 0 then
        vpg.setCurrentItem(0)
        activity.setTitle("NeLuaJ+" .. res.string.help)
    else
        activity.finish()
    end
end)
