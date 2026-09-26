--- 帮助文档目录：首页「帮助」tab 与帮助页（HelpActivity）共用。
--- 条目点击后由调用方决定打开方式（帮助页内部 pager / 首页跳 help 路由）。
local docLanguage = tostring(res.language or ""):find("zh") and "zh" or "en"

-- 文档分工（避免重复）：
-- color_api = 取色入口；LuaThemeUtil = 字段表；md3_design = 组件/设计；
-- layout_reference = 属性大全；layout_style = style/theme 构造；
-- module_loadlayout = 加载器机制
return {
  {
    title = "AI 助手",
    subtitle = "内置 Agent 的配置、对话和文件操作",
    items = {
      { title = res.string.ai_chat, desc = "配置模型、发送任务并让 Agent 协助修改工程", file = "agent_" .. docLanguage .. ".html", tags = "AI Agent 助手 模型 API 文件 MCP Skill" },
      { title = "AI Lua 沙盒", desc = "AI 临时代码的可用库与限制", file = "sandbox_" .. docLanguage .. ".html", tags = "AI 沙盒 sandbox 运行 Lua 安全" },
    },
  },
  {
    title = "入门",
    subtitle = "迁移、工程配置与设计约定",
    items = {
      { title = res.string.migration_guide, desc = "从旧版 AndroLua / NeLuaJ 迁移", file = "migration_" .. docLanguage .. ".html", tags = "迁移 升级 兼容" },
      { title = "init.lua", desc = "包名、SDK、主题名与权限", file = "init_lua_" .. docLanguage .. ".html", tags = "配置 权限 SDK 主题" },
      { title = "welcome.lua", desc = "打包时的启动页背景、图标或整页图", file = "welcome_" .. docLanguage .. ".html", tags = "启动页 welcome 打包 splash" },
      { title = res.string.md3_design, desc = "MD3 组件与间距圆角约定（取色见 Color）", file = "md3_design.html", tags = "MD3 组件 设计" },
      { title = "颜色与主题", desc = "dynamicColor、?attr/、themeUtil 怎么选", file = "color_api.html", tags = "颜色 动态取色 attr 主题" },
      { title = res.string.layout_reference, desc = "布局属性、单位与控件示例", file = "layout_reference.html", tags = "布局 控件 单位 dp" },
      { title = "布局 style / theme", desc = "styleAttr、styleRes、MaterialTextField 构造", file = "layout_style.html", tags = "style theme styleAttr Material" },
    },
  },
  {
    title = "语言与环境",
    subtitle = "运行时、全局对象与语法",
    items = {
      { title = res.string.global, desc = "this / activity / 全局模块", file = "global_env.html", tags = "全局 this activity" },
      { title = "LuaJ++", desc = "switch、lambda、import、try 等", file = "LuaJ++.html", tags = "语法 switch lambda import" },
      { title = "Java 互操作", desc = "bindClass、proxy、override", file = "java_interop.html", tags = "java luajava proxy override" },
      { title = res.string.backup_crash, desc = "崩溃日志与代码备份", file = "backup_crash.html", tags = "崩溃 备份 日志" },
      { title = res.string.utility_api, desc = "常用工具速查（详文见各模块）", file = "utility_api.html", tags = "工具 速查" },
    },
  },
  {
    title = "模块",
    subtitle = "资源、布局、文件与网络",
    items = {
      { title = "res", desc = "string / drawable / layout / raw", file = "module_res.html", tags = "资源 字符串 布局" },
      { title = "loadlayout", desc = "表驱动布局（style 见「布局 style / theme」）", file = "module_loadlayout.html", tags = "布局 loadlayout" },
      { title = "file", desc = "读写与目录", file = "module_file.html", tags = "文件 读写" },
      { title = "LuaFileUtil", desc = "工程内文件复制、删除、搜索", file = "LuaFileUtil.html", tags = "文件 复制 删除 搜索 LuaFileUtil" },
      { title = "okhttp", desc = "同步 / 异步 HTTP", file = "module_okhttp.html", tags = "网络 http" },
      { title = "saf", desc = "存储访问框架", file = "module_saf.html", tags = "存储 SAF" },
      { title = "ext", desc = "二进制 pack / unpack", file = "module_ext.html", tags = "二进制 pack" },
      { title = "lazy", desc = "延迟求值", file = "lazy.html", tags = "延迟 lazy" },
      { title = "xTask", desc = "协程异步任务", file = "xTask.html", tags = "异步 协程" },
    },
  },
  {
    title = "组件",
    subtitle = "Activity、列表与 UI 封装",
    items = {
      { title = "LuaActivity", desc = "生命周期、结果、权限", file = "LuaActivity.html", tags = "Activity 权限" },
      { title = "LuaFragment", desc = "Lua Fragment", file = "LuaFragment.html", tags = "Fragment" },
      { title = "LuaFragmentAdapter", desc = "ViewPager2 Fragment 适配器", file = "LuaFragmentAdapter.html", tags = "ViewPager2" },
      { title = "LuaPagerAdapter", desc = "ViewPager 适配器", file = "LuaPagerAdapter.html", tags = "ViewPager" },
      { title = "LuaRecyclerAdapter", desc = "表驱动 RecyclerView", file = "LuaRecyclerAdapter.html", tags = "RecyclerView" },
      { title = "LuaCustRecyclerAdapter", desc = "自定义 RecyclerView", file = "LuaCustRecyclerAdapter.html", tags = "RecyclerView 自定义" },
      { title = "LuaPreferenceFragment", desc = "Preference 设置页", file = "LuaPreferenceFragment.html", tags = "Preference" },
      { title = "LuaThemeUtil", desc = "themeUtil 字段表（用法见颜色与主题）", file = "LuaThemeUtil.html", tags = "themeUtil 字段" },
      { title = "MaterialTextField", desc = "Material 输入框", file = "MaterialTextField.html", tags = "输入框" },
      { title = "Coil", desc = "图片加载", file = "Coil.html", tags = "图片 Coil" },
    },
  },
  {
    title = "其它",
    subtitle = "系统能力",
    items = {
      { title = "FileObserver", desc = "目录文件变更监听", file = "other_FileObserver.html", tags = "监听 文件" },
      { title = "FastScrollerBuilder", desc = "列表快速滚动条", file = "other_FastScrollerBuilder.html", tags = "滚动条" },
    },
  },
}
