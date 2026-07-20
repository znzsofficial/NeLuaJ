require "environment"
import "android.view.WindowManager"
import "android.view.View"
import "android.graphics.drawable.ColorDrawable"
import "android.widget.LinearLayout"
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.card.MaterialCardView"
import "com.google.android.material.divider.MaterialDivider"

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

local ui = __helpUi
local docLanguage = tostring(res.language or ""):find("zh") and "zh" or "en"

local catalog = {
  {
    title = "入门指南",
    subtitle = "从迁移、主题到常用 API",
    items = {
      { title = res.string.migration_guide, desc = "从旧版 AndroLua / NeLuaJ 迁移到当前版本", file = "migration_" .. docLanguage .. ".html" },
      { title = res.string.md3_design, desc = "Material 3 配色、组件与布局约定", file = "md3_design.html" },
      { title = res.string.layout_reference, desc = "loadlayout 属性、单位与常用控件", file = "layout_reference.html" },
      { title = res.string.utility_api, desc = "常用工具 API 速查", file = "utility_api.html" },
      { title = "Color API", desc = "动态取色、主题色与颜色工具", file = "color_api.html" },
    },
  },
  {
    title = "语言与环境",
    subtitle = "运行时、全局对象与语法扩展",
    items = {
      { title = "init.lua", desc = "工程配置：包名、SDK、主题与权限", file = "init_lua_" .. docLanguage .. ".html" },
      { title = res.string.global, desc = "this / activity / 全局模块与函数一览", file = "global_env.html" },
      { title = "LuaJ++", desc = "扩展语法：switch、lambda、import、try 等", file = "LuaJ++.html" },
      { title = "Java 互操作", desc = "bindClass、proxy、override、属性与监听器语法糖", file = "java_interop.html" },
      { title = res.string.backup_crash, desc = "崩溃日志路径与自动代码备份", file = "backup_crash.html" },
    },
  },
  {
    title = "核心模块",
    subtitle = "文件、网络、布局与异步能力",
    items = {
      { title = "res", desc = "字符串、布局、字体与资源加载", file = "module_res.html" },
      { title = "loadlayout", desc = "表驱动布局加载器", file = "module_loadlayout.html" },
      { title = "file", desc = "读写、目录、路径与文件信息", file = "module_file.html" },
      { title = "okhttp", desc = "同步 / 异步网络请求", file = "module_okhttp.html" },
      { title = "saf", desc = "存储访问框架与持久化目录授权", file = "module_saf.html" },
      { title = "ext", desc = "二进制 pack / unpack", file = "module_ext.html" },
      { title = "lazy", desc = "延迟求值，首次访问才执行", file = "lazy.html" },
      { title = "xTask", desc = "基于协程的异步任务", file = "xTask.html" },
    },
  },
  {
    title = "组件",
    subtitle = "Activity、Fragment、列表与主题",
    items = {
      { title = "LuaActivity", desc = "宿主 Activity：生命周期、结果回调、权限", file = "LuaActivity.html" },
      { title = "LuaFragment", desc = "Lua 驱动的 Fragment", file = "LuaFragment.html" },
      { title = "LuaFragmentAdapter", desc = "ViewPager2 Fragment 适配器", file = "LuaFragmentAdapter.html" },
      { title = "LuaPagerAdapter", desc = "ViewPager / 页面适配器", file = "LuaPagerAdapter.html" },
      { title = "LuaRecyclerAdapter", desc = "数据表驱动的 RecyclerView 适配器", file = "LuaRecyclerAdapter.html" },
      { title = "LuaCustRecyclerAdapter", desc = "贴近原生的自定义 RecyclerView 适配器", file = "LuaCustRecyclerAdapter.html" },
      { title = "LuaPreferenceFragment", desc = "设置页 Preference 封装", file = "LuaPreferenceFragment.html" },
      { title = "LuaThemeUtil", desc = "主题色与 Material 颜色读取", file = "LuaThemeUtil.html" },
      { title = "MaterialTextField", desc = "Material 文本输入框封装", file = "MaterialTextField.html" },
      { title = "Coil", desc = "图片加载：网络、本地与变换", file = "Coil.html" },
    },
  },
  {
    title = "工具与其它",
    subtitle = "系统能力与第三方集成示例",
    items = {
      { title = "FileObserver", desc = "监听目录文件创建 / 修改 / 删除", file = "other_FileObserver.html" },
      { title = "FastScrollerBuilder", desc = "RecyclerView 快速滚动条", file = "other_FastScrollerBuilder.html" },
    },
  },
}

local function openDoc(item)
  activity.setTitle(item.title)
  vpg.setCurrentItem(1)
  webView.loadUrl("file://" .. activity.getLuaPath("res/doc", item.file))
end

local function buildHome()
  docHome.removeAllViews()

  docHome.addView(loadlayout {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    paddingBottom = "4dp",
    {
      MaterialTextView,
      text = "文档中心",
      textSize = "28sp",
      textStyle = "bold",
      textColor = ui.onSurface,
      letterSpacing = -0.01,
    },
    {
      MaterialTextView,
      text = "按场景分类浏览 API、模块与组件说明",
      textSize = "14sp",
      textColor = ui.onSurfaceVar,
      paddingTop = "4dp",
      paddingBottom = "4dp",
    },
  })

  for _, section in ipairs(catalog) do
    docHome.addView(loadlayout {
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      paddingTop = "16dp",
      paddingBottom = "8dp",
      {
        MaterialTextView,
        text = section.title,
        textSize = "13sp",
        textStyle = "bold",
        textColor = ui.primary,
        letterSpacing = 0.02,
      },
      {
        MaterialTextView,
        text = section.subtitle or "",
        textSize = "12sp",
        textColor = ui.onSurfaceVar,
        paddingTop = "2dp",
        Visibility = section.subtitle and 0 or 8,
      },
    })

    local rows = {
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
    }

    for i, item in ipairs(section.items) do
      local row = {
        LinearLayout,
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        clickable = true,
        focusable = true,
        backgroundResource = ui.rippleRes,
        paddingLeft = "16dp",
        paddingRight = "16dp",
        paddingTop = "14dp",
        paddingBottom = "14dp",
        onClick = function()
          openDoc(item)
        end,
        {
          MaterialTextView,
          text = item.title,
          textSize = "16sp",
          textColor = ui.onSurface,
          textStyle = "bold",
        },
        {
          MaterialTextView,
          text = item.desc or "",
          textSize = "13sp",
          textColor = ui.onSurfaceVar,
          paddingTop = "4dp",
          Visibility = item.desc and 0 or 8,
        },
      }
      if i < #section.items then
        table.insert(row, {
          MaterialDivider,
          layout_marginTop = "12dp",
        })
      end
      table.insert(rows, row)
    end

    docHome.addView(loadlayout {
      MaterialCardView,
      layout_width = "match",
      layout_height = "wrap",
      layout_marginBottom = "4dp",
      radius = "20dp",
      CardElevation = 0,
      strokeWidth = "1dp",
      strokeColor = ui.outline,
      CardBackgroundColor = ui.surfaceContainer,
      rows,
    })
  end
end

buildHome()

webView.getSettings().setJavaScriptEnabled(true)
webView.getSettings().setDomStorageEnabled(true)
webView.getSettings().setAllowFileAccess(true)

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

this.addOnBackPressedCallback(function()
  if vpg.getCurrentItem() ~= 0 then
    vpg.setCurrentItem(0)
    activity.setTitle("NeLuaJ+" .. res.string.help)
  else
    activity.finish()
  end
end)
