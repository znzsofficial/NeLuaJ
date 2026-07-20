require "environment"
import "android.view.WindowManager"
import "android.view.View"
import "android.graphics.drawable.ColorDrawable"
import "android.widget.LinearLayout"
import "android.widget.HorizontalScrollView"
import "androidx.appcompat.widget.AppCompatEditText"
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.card.MaterialCardView"
import "com.google.android.material.divider.MaterialDivider"
import "android.webkit.WebViewClient"
import "android.webkit.WebChromeClient"

local ColorUtil = this.themeUtil
local res = res
this.dynamicColor()

local barColor = ColorUtil.getColorBackground()
local homeTitle = "NeLuaJ+" .. res.string.help

activity.setTitle(homeTitle)
  .setContentView(res.layout.help_layout)
  .getSupportActionBar() {
    Elevation = 0,
    BackgroundDrawable = ColorDrawable(barColor),
    DisplayShowTitleEnabled = true,
    DisplayHomeAsUpEnabled = true
  }

local window = activity.getWindow()
  .setNavigationBarColor(barColor)
  .setStatusBarColor(barColor)
  .addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
  .clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
if this.isNightMode() then
  window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_VISIBLE)
else
  window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR)
end

local ui = __helpUi
local docLanguage = tostring(res.language or ""):find("zh") and "zh" or "en"
local searchQuery = ""

local catalog = {
  {
    title = "入门指南",
    subtitle = "从迁移、主题到常用 API",
    items = {
      { title = res.string.migration_guide, desc = "从旧版 AndroLua / NeLuaJ 迁移到当前版本", file = "migration_" .. docLanguage .. ".html", tags = "迁移 升级 兼容" },
      { title = res.string.md3_design, desc = "Material 3 配色、组件与布局约定", file = "md3_design.html", tags = "主题 颜色 MD3 Material" },
      { title = res.string.layout_reference, desc = "loadlayout 属性、单位与常用控件", file = "layout_reference.html", tags = "布局 控件 单位 dp" },
      { title = res.string.utility_api, desc = "常用工具 API 速查", file = "utility_api.html", tags = "工具 便捷 API" },
      { title = "Color API", desc = "动态取色、主题色与颜色工具", file = "color_api.html", tags = "颜色 动态取色 seed" },
    },
  },
  {
    title = "语言与环境",
    subtitle = "运行时、全局对象与语法扩展",
    items = {
      { title = "init.lua", desc = "工程配置：包名、SDK、主题与权限", file = "init_lua_" .. docLanguage .. ".html", tags = "配置 权限 SDK 主题" },
      { title = res.string.global, desc = "this / activity / 全局模块与函数一览", file = "global_env.html", tags = "全局 this activity" },
      { title = "LuaJ++", desc = "扩展语法：switch、lambda、import、try 等", file = "LuaJ++.html", tags = "语法 switch lambda import" },
      { title = "Java 互操作", desc = "bindClass、proxy、override、属性与监听器语法糖", file = "java_interop.html", tags = "java luajava proxy override" },
      { title = res.string.backup_crash, desc = "崩溃日志路径与自动代码备份", file = "backup_crash.html", tags = "崩溃 备份 日志" },
    },
  },
  {
    title = "核心模块",
    subtitle = "文件、网络、布局与异步能力",
    items = {
      { title = "res", desc = "字符串、布局、字体与资源加载", file = "module_res.html", tags = "资源 字符串 布局" },
      { title = "loadlayout", desc = "表驱动布局加载器", file = "module_loadlayout.html", tags = "布局 loadlayout" },
      { title = "file", desc = "读写、目录、路径与文件信息", file = "module_file.html", tags = "文件 读写" },
      { title = "okhttp", desc = "同步 / 异步网络请求", file = "module_okhttp.html", tags = "网络 http 请求" },
      { title = "saf", desc = "存储访问框架与持久化目录授权", file = "module_saf.html", tags = "存储 SAF 授权" },
      { title = "ext", desc = "二进制 pack / unpack", file = "module_ext.html", tags = "二进制 pack" },
      { title = "lazy", desc = "延迟求值，首次访问才执行", file = "lazy.html", tags = "延迟 lazy" },
      { title = "xTask", desc = "基于协程的异步任务", file = "xTask.html", tags = "异步 协程 任务" },
    },
  },
  {
    title = "组件",
    subtitle = "Activity、Fragment、列表与主题",
    items = {
      { title = "LuaActivity", desc = "宿主 Activity：生命周期、结果回调、权限", file = "LuaActivity.html", tags = "Activity 生命周期 权限" },
      { title = "LuaFragment", desc = "Lua 驱动的 Fragment", file = "LuaFragment.html", tags = "Fragment" },
      { title = "LuaFragmentAdapter", desc = "ViewPager2 Fragment 适配器", file = "LuaFragmentAdapter.html", tags = "ViewPager2 适配器" },
      { title = "LuaPagerAdapter", desc = "ViewPager / 页面适配器", file = "LuaPagerAdapter.html", tags = "ViewPager 适配器" },
      { title = "LuaRecyclerAdapter", desc = "数据表驱动的 RecyclerView 适配器", file = "LuaRecyclerAdapter.html", tags = "RecyclerView 列表" },
      { title = "LuaCustRecyclerAdapter", desc = "贴近原生的自定义 RecyclerView 适配器", file = "LuaCustRecyclerAdapter.html", tags = "RecyclerView 自定义" },
      { title = "LuaPreferenceFragment", desc = "设置页 Preference 封装", file = "LuaPreferenceFragment.html", tags = "设置 Preference" },
      { title = "LuaThemeUtil", desc = "主题色与 Material 颜色读取", file = "LuaThemeUtil.html", tags = "主题 颜色" },
      { title = "MaterialTextField", desc = "Material 文本输入框封装", file = "MaterialTextField.html", tags = "输入框 TextField" },
      { title = "Coil", desc = "图片加载：网络、本地与变换", file = "Coil.html", tags = "图片 加载 Coil" },
    },
  },
  {
    title = "工具与其它",
    subtitle = "系统能力与第三方集成示例",
    items = {
      { title = "FileObserver", desc = "监听目录文件创建 / 修改 / 删除", file = "other_FileObserver.html", tags = "监听 文件" },
      { title = "FastScrollerBuilder", desc = "RecyclerView 快速滚动条", file = "other_FastScrollerBuilder.html", tags = "滚动条 RecyclerView" },
    },
  },
}

local function countDocs(list)
  local n = 0
  for _, section in ipairs(list or catalog) do
    n = n + #section.items
  end
  return n
end

local function matchesQuery(item, section, q)
  if q == "" then return true end
  local hay = table.concat({
    tostring(item.title or ""),
    tostring(item.desc or ""),
    tostring(item.file or ""),
    tostring(item.tags or ""),
    tostring(section.title or ""),
  }, " "):lower()
  return hay:find(q, 1, true) ~= nil
end

local function filterCatalog(q)
  q = (q or ""):lower():match("^%s*(.-)%s*$") or ""
  if q == "" then return catalog, false end
  local out = {}
  for _, section in ipairs(catalog) do
    local items = {}
    for _, item in ipairs(section.items) do
      if matchesQuery(item, section, q) then
        items[#items + 1] = item
      end
    end
    if #items > 0 then
      out[#out + 1] = {
        title = section.title,
        subtitle = section.subtitle,
        items = items,
      }
    end
  end
  return out, true
end

local function setWebLoading(show)
  pcall(function()
    webLoading.setVisibility(show and View.VISIBLE or View.GONE)
  end)
end

local function openDoc(item)
  activity.setTitle(item.title)
  setWebLoading(true)
  vpg.setCurrentItem(1)
  webView.loadUrl("file://" .. activity.getLuaPath("res/doc", item.file))
end

local function backToHome()
  vpg.setCurrentItem(0)
  activity.setTitle(homeTitle)
  setWebLoading(false)
end

local function buildDocRow(item, showDivider)
  local row = {
    LinearLayout,
    orientation = "horizontal",
    layout_width = "match",
    layout_height = "wrap",
    gravity = "center_vertical",
    clickable = true,
    focusable = true,
    backgroundResource = ui.rippleRes,
    paddingLeft = "16dp",
    paddingRight = "12dp",
    paddingTop = "14dp",
    paddingBottom = "14dp",
    minHeight = "56dp",
    onClick = function()
      openDoc(item)
    end,
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "0dp",
      layout_height = "wrap",
      layout_weight = 1,
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
        paddingTop = "3dp",
        Visibility = item.desc and 0 or 8,
      },
    },
    {
      MaterialTextView,
      text = "›",
      textSize = "22sp",
      textColor = ui.onSurfaceVar,
      paddingLeft = "8dp",
      gravity = "center",
    },
  }
  if showDivider then
    return {
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      row,
      {
        MaterialDivider,
        layout_marginLeft = "16dp",
      },
    }
  end
  return row
end

local function buildList(filtered, isFiltered)
  docHome.removeAllViews()

  if #filtered == 0 then
    docHome.addView(loadlayout {
      MaterialCardView,
      layout_width = "match",
      layout_height = "wrap",
      layout_marginTop = "24dp",
      radius = "16dp",
      CardElevation = 0,
      strokeWidth = "1dp",
      strokeColor = ui.outline,
      CardBackgroundColor = ui.surfaceContainer,
      {
        LinearLayout,
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        padding = "28dp",
        gravity = "center",
        {
          MaterialTextView,
          text = "未找到相关文档",
          textSize = "16sp",
          textStyle = "bold",
          textColor = ui.onSurface,
          gravity = "center",
        },
        {
          MaterialTextView,
          text = "试试更短的关键词，例如 res、Activity、主题",
          textSize = "13sp",
          textColor = ui.onSurfaceVar,
          paddingTop = "8dp",
          gravity = "center",
        },
      },
    })
    return
  end

  for _, section in ipairs(filtered) do
    docHome.addView(loadlayout {
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      paddingTop = "14dp",
      paddingBottom = "8dp",
      paddingLeft = "4dp",
      paddingRight = "4dp",
      {
        LinearLayout,
        orientation = "horizontal",
        layout_width = "match",
        layout_height = "wrap",
        gravity = "center_vertical",
        {
          MaterialTextView,
          text = section.title,
          textSize = "14sp",
          textStyle = "bold",
          textColor = ui.primary,
          letterSpacing = 0.01,
          layout_width = "0dp",
          layout_weight = 1,
        },
        {
          MaterialTextView,
          text = tostring(#section.items),
          textSize = "12sp",
          textColor = ui.onSurfaceVar,
        },
      },
      {
        MaterialTextView,
        text = section.subtitle or "",
        textSize = "12sp",
        textColor = ui.onSurfaceVar,
        paddingTop = "2dp",
        Visibility = (not isFiltered and section.subtitle) and 0 or 8,
      },
    })

    local cardChildren = {
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
    }
    for i, item in ipairs(section.items) do
      table.insert(cardChildren, buildDocRow(item, i < #section.items))
    end

    docHome.addView(loadlayout {
      MaterialCardView,
      layout_width = "match",
      layout_height = "wrap",
      layout_marginBottom = "2dp",
      radius = "16dp",
      CardElevation = 0,
      strokeWidth = "1dp",
      strokeColor = ui.outline,
      CardBackgroundColor = ui.surfaceContainer,
      cardChildren,
    })
  end

  docHome.addView(loadlayout {
    MaterialTextView,
    text = isFiltered
      and string.format("已筛选 %d 篇文档", countDocs(filtered))
      or "提示：阅读文档时点左上角返回可回到分类首页",
    textSize = "12sp",
    textColor = ui.onSurfaceVar,
    paddingTop = "20dp",
    paddingLeft = "8dp",
    paddingRight = "8dp",
    gravity = "center",
  })
end

local function refreshList()
  local filtered, isFiltered = filterCatalog(searchQuery)
  buildList(filtered, isFiltered)
end

local function buildHeader()
  docHeader.removeAllViews()

  -- Hero
  docHeader.addView(loadlayout {
    MaterialCardView,
    layout_width = "match",
    layout_height = "wrap",
    layout_marginBottom = "10dp",
    radius = "20dp",
    CardElevation = 0,
    strokeWidth = "0dp",
    CardBackgroundColor = ui.primaryContainer,
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      paddingLeft = "20dp",
      paddingRight = "20dp",
      paddingTop = "18dp",
      paddingBottom = "18dp",
      {
        MaterialTextView,
        text = "文档中心",
        textSize = "24sp",
        textStyle = "bold",
        textColor = ui.onPrimaryContainer,
        letterSpacing = -0.01,
      },
      {
        MaterialTextView,
        text = "搜索或按分类浏览 API、模块与组件说明",
        textSize = "13sp",
        textColor = ui.onPrimaryContainer,
        paddingTop = "6dp",
        alpha = 0.9,
      },
      {
        MaterialCardView,
        layout_width = "wrap",
        layout_height = "wrap",
        layout_marginTop = "12dp",
        radius = "999dp",
        CardElevation = 0,
        strokeWidth = "0dp",
        CardBackgroundColor = ui.surfaceColor,
        {
          MaterialTextView,
          text = string.format("%d 篇 · %d 类", countDocs(catalog), #catalog),
          textSize = "12sp",
          textColor = ui.onSurface,
          paddingLeft = "12dp",
          paddingRight = "12dp",
          paddingTop = "5dp",
          paddingBottom = "5dp",
        },
      },
    },
  })

  -- Search
  docHeader.addView(loadlayout {
    MaterialCardView,
    layout_width = "match",
    layout_height = "48dp",
    layout_marginBottom = "6dp",
    radius = "24dp",
    CardElevation = 0,
    strokeWidth = "0dp",
    CardBackgroundColor = ui.surfaceVariant or ui.surfaceContainer,
    {
      AppCompatEditText,
      id = "docSearch",
      layout_width = "match",
      layout_height = "match",
      background = 0,
      singleLine = true,
      textSize = "15sp",
      paddingLeft = "16dp",
      paddingRight = "16dp",
      hint = "搜索文档，如 res、Activity、主题",
      textColor = ui.onSurface,
      textColorHint = ui.onSurfaceVar,
      imeOptions = "actionSearch",
    },
  })

  -- Section chips
  local chipRow = {
    LinearLayout,
    orientation = "horizontal",
    layout_width = "wrap",
    layout_height = "wrap",
    paddingTop = "2dp",
    paddingBottom = "4dp",
  }
  for _, section in ipairs(catalog) do
    table.insert(chipRow, {
      MaterialCardView,
      layout_width = "wrap",
      layout_height = "wrap",
      layout_marginRight = "8dp",
      radius = "999dp",
      CardElevation = 0,
      strokeWidth = "1dp",
      strokeColor = ui.outline,
      CardBackgroundColor = ui.surfaceContainer,
      clickable = true,
      focusable = true,
      {
        MaterialTextView,
        text = section.title,
        textSize = "12sp",
        textColor = ui.onSurface,
        paddingLeft = "12dp",
        paddingRight = "12dp",
        paddingTop = "7dp",
        paddingBottom = "7dp",
        onClick = function()
          searchQuery = section.title
          pcall(function()
            docSearch.setText(section.title)
            docSearch.setSelection(#section.title)
          end)
          refreshList()
        end,
      },
    })
  end
  docHeader.addView(loadlayout {
    HorizontalScrollView,
    layout_width = "match",
    layout_height = "wrap",
    horizontalScrollBarEnabled = false,
    overScrollMode = 2,
    chipRow,
  })
end

buildHeader()
refreshList()

-- Search listener
pcall(function()
  docSearch.addTextChangedListener {
    afterTextChanged = function(s)
      searchQuery = tostring(s or "")
      refreshList()
    end,
  }
end)

-- WebView
local settings = webView.getSettings()
settings.setJavaScriptEnabled(true)
settings.setDomStorageEnabled(true)
settings.setAllowFileAccess(true)
settings.setBuiltInZoomControls(true)
settings.setDisplayZoomControls(false)
settings.setSupportZoom(true)
pcall(function()
  settings.setLoadWithOverviewMode(true)
  settings.setUseWideViewPort(true)
end)

webView.setWebViewClient(WebViewClient {
  onPageFinished = function(view, url)
    setWebLoading(false)
  end,
  onReceivedError = function(view, errorCode, description, failingUrl)
    setWebLoading(false)
  end,
})

webView.setWebChromeClient(WebChromeClient {
  onProgressChanged = function(view, progress)
    if progress >= 100 then
      setWebLoading(false)
    end
  end,
})

function onOptionsItemSelected(m)
  if m.getItemId() == android.R.id.home then
    if vpg.getCurrentItem() ~= 0 then
      backToHome()
    else
      activity.finish()
    end
  end
end

this.addOnBackPressedCallback(function()
  if vpg.getCurrentItem() ~= 0 then
    if webView.canGoBack() then
      webView.goBack()
    else
      backToHome()
    end
  else
    activity.finish()
  end
end)
