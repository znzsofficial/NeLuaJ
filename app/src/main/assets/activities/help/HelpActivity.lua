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
    { text = res.string.migration_guide,      file = "migration_" .. docLanguage .. ".html" },
    { text = res.string.md3_design,           file = "md3_design.html" },
    { text = res.string.layout_reference,     file = "layout_reference.html" },
    { text = res.string.utility_api,          file = "utility_api.html" },
    { text = "Color API",                     file = "color_api.html" },
    -- 基础文档
    { text = "init.lua",                      file = "init_lua_" .. docLanguage .. ".html" },
    { text = res.string.global,               file = "global_env.html" },
    { text = "LuaJ++",                        file = "LuaJ++.html" },
    { text = res.string.backup_crash,         file = "backup_crash.html" },
    -- 模块
    { text = "res " .. res.string._module,    file = "module_res.html" },
    { text = "okhttp " .. res.string._module, file = "module_okhttp.html" },
    { text = "loadlayout",                    file = "module_loadlayout.html" },
    { text = "file " .. res.string._module,   file = "module_file.html" },
    { text = "saf " .. res.string._module,    file = "module_saf.html" },
    { text = "ext " .. res.string._module,    file = "module_ext.html" },
    { text = "lazy",                          file = "lazy.html" },
    { text = "xTask",                         file = "xTask.html" },
    -- 组件
    { text = "LuaActivity",                   file = "LuaActivity.html" },
    { text = "LuaCustRecyclerAdapter",        file = "LuaCustRecyclerAdapter.html" },
    { text = "LuaFragment",                   file = "LuaFragment.html" },
    { text = "LuaFragmentAdapter",            file = "LuaFragmentAdapter.html" },
    { text = "LuaPagerAdapter",               file = "LuaPagerAdapter.html" },
    { text = "LuaPreferenceFragment",         file = "LuaPreferenceFragment.html" },
    { text = "LuaRecyclerAdapter",            file = "LuaRecyclerAdapter.html" },
    { text = "LuaThemeUtil",                  file = "LuaThemeUtil.html" },
    { text = "MaterialTextField",             file = "MaterialTextField.html" },
    { text = "Coil",                          file = "Coil.html" },
    -- 其他
    { text = "FileObserver",                  file = "other_FileObserver.html" },
    { text = "FastScrollerBuilder",           file = "other_FastScrollerBuilder.html" },
}

local adp = LuaAdapter(activity, data, item)
lv.setAdapter(adp)

local docCss = LuaFileUtil.read(activity.getLuaPath("res/doc", "doc.css"))

local function loadHtmlDocument(fileName)
    local docDir = activity.getLuaPath("res/doc")
    local html = LuaFileUtil.read(activity.getLuaPath("res/doc", fileName))
    if docCss and #docCss > 0 then
        html = html:gsub('<link rel="stylesheet" href="doc%.css" />', function()
            return '<style>\n' .. docCss .. '\n</style>'
        end)
    end
    webView.loadDataWithBaseURL("file://" .. docDir .. "/", html, "text/html", "UTF-8", nil)
end

lv.onItemClick = function(l, v, p, i)
    activity.setTitle(data[i].text)
    vpg.setCurrentItem(1)
    loadHtmlDocument(data[i].file)
end

this.addOnBackPressedCallback(function()
    if vpg.getCurrentItem() ~= 0 then
        vpg.setCurrentItem(0)
        activity.setTitle("NeLuaJ+" .. res.string.help)
    else
        activity.finish()
    end
end)
