--- 首页「项目」tab：最近修改卡片行 + 完整工程列表（按修改时间排序）。
--- 工程定义：/sdcard/LuaJ/Projects/ 下的一级目录；名称优先取 init.lua 的
--- app_name（字符串直读，不执行文件），回退目录名。
local _M = {}

local File = luajava.bindClass("java.io.File")
local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local HorizontalScrollView = luajava.bindClass("android.widget.HorizontalScrollView")
local ScrollView = luajava.bindClass("android.widget.ScrollView")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
local MaterialButton = luajava.bindClass("com.google.android.material.button.MaterialButton")
local MaterialCardView = luajava.bindClass("com.google.android.material.card.MaterialCardView")
local Toast = luajava.bindClass("android.widget.Toast")

local ActivityUtil = require "mods.utils.ActivityUtil"

local ColorUtil = this.themeUtil
local res = res
local dp = function(n) return this.dpToPx(n) end

local background = ColorUtil.getColorBackground()
local onSurface = ColorUtil.getColorOnSurface()
local onSurfaceVar = ColorUtil.getColorOnSurfaceVariant()
local primary = ColorUtil.getColorPrimary()
local surfaceCard = ColorUtil.getColorSurfaceContainer()

local built = nil
local views = {}

--- 读取 init.lua 的 app_name / package_name（纯字符串匹配，不执行文件）
local function readInitField(path, key)
  local ok, content = pcall(function() return file.readall(path .. "/init.lua") end)
  if not ok or type(content) ~= "string" then return nil end
  return content:match(key .. '%s*=%s*"([^"]*)"') or content:match(key .. "%s*=%s*'([^']+)'")
end

--- 扫描工程目录，按 mtime 降序返回 { { path, name, appName, pkg, mtime } }
local function scanProjects()
  local root = Bean.Path.app_root_pro_dir
  local projects = {}
  local ok, names = pcall(function() return file.list(root) end)
  if not ok or type(names) ~= "table" then return projects end
  for _, name in ipairs(names) do
    local path = root .. "/" .. tostring(name)
    local dir = File(path)
    if dir.isDirectory() then
      local mtime = 0
      pcall(function() mtime = tonumber(dir.lastModified()) or 0 end)
      projects[#projects + 1] = {
        path = path,
        name = tostring(name),
        appName = readInitField(path, "app_name"),
        pkg = readInitField(path, "package_name"),
        mtime = mtime,
      }
    end
  end
  table.sort(projects, function(a, b) return a.mtime > b.mtime end)
  return projects
end

local function formatTime(mtime)
  if not mtime or mtime <= 0 then return "" end
  return os.date("%Y-%m-%d %H:%M", mtime / 1000)
end

local function openProject(path)
  ActivityUtil.open("editor", path)
end

local function showProjectMenu(project)
  pcall(function()
    local MaterialAlertDialogBuilder = luajava.bindClass("com.google.android.material.dialog.MaterialAlertDialogBuilder")
    MaterialAlertDialogBuilder(activity)
      .setTitle(project.name)
      .setItems({ res.string.project_settings, res.string.open }, function(_, which)
        if which == 0 then
          ActivityUtil.open("project_settings", project.path)
        else
          openProject(project.path)
        end
      end)
      .setNegativeButton(android.R.string.cancel, nil)
      .show()
  end)
end

--- 最近修改横向卡片
local function buildRecentCard(project)
  local cardViews = {}
  local card = loadlayout({
    MaterialCardView,
    radius = "16dp",
    CardElevation = 0,
    CardBackgroundColor = surfaceCard,
    layout_width = "160dp",
    layout_height = "wrap",
    clickable = true,
    focusable = true,
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      padding = "12dp",
      {
        MaterialTextView,
        text = project.appName or project.name,
        textSize = "15sp",
        textStyle = "bold",
        textColor = onSurface,
        maxLines = 1,
        ellipsize = "end",
      },
      {
        MaterialTextView,
        text = project.name,
        textSize = "11sp",
        textColor = onSurfaceVar,
        maxLines = 1,
        ellipsize = "end",
        layout_marginTop = "2dp",
      },
      {
        MaterialTextView,
        text = formatTime(project.mtime),
        textSize = "11sp",
        textColor = onSurfaceVar,
        layout_marginTop = "4dp",
      },
    },
  }, cardViews)
  card.onClick = function() openProject(project.path) end
  pcall(function()
    card.setOnLongClickListener(function()
      showProjectMenu(project)
      return true
    end)
  end)
  return card
end

--- 完整列表行
local function buildListRow(project)
  local row = loadlayout({
    MaterialCardView,
    radius = "14dp",
    CardElevation = 0,
    CardBackgroundColor = surfaceCard,
    layout_width = "match",
    layout_height = "wrap",
    clickable = true,
    focusable = true,
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      padding = "14dp",
      {
        MaterialTextView,
        text = project.appName or project.name,
        textSize = "15sp",
        textStyle = "bold",
        textColor = onSurface,
        maxLines = 1,
        ellipsize = "end",
      },
      {
        MaterialTextView,
        text = project.name .. (project.pkg and (" · " .. project.pkg) or ""),
        textSize = "11sp",
        textColor = onSurfaceVar,
        maxLines = 1,
        ellipsize = "end",
        layout_marginTop = "2dp",
      },
      {
        MaterialTextView,
        text = formatTime(project.mtime),
        textSize = "11sp",
        textColor = primary,
        layout_marginTop = "4dp",
      },
    },
  })
  row.onClick = function() openProject(project.path) end
  pcall(function()
    row.setOnLongClickListener(function()
      showProjectMenu(project)
      return true
    end)
  end)
  return row
end

--- 独立加载的根视图必须用显式 LayoutParams 传 margin
local function addRowWithMargin(container, child, topMargin)
  local lp = LinearLayout.LayoutParams(-1, -2)
  lp.topMargin = dp(topMargin)
  container.addView(child, lp)
end

local function renderRecent(projects)
  local container = views.recentRow
  if not container then return end
  container.removeAllViews()
  local recentCount = math.min(5, #projects)
  if recentCount == 0 then
    views.recentBlock.setVisibility(8) -- GONE
    return
  end
  views.recentBlock.setVisibility(0)
  for i = 1, recentCount do
    local lp = LinearLayout.LayoutParams(-2, -2)
    if i > 1 then lp.leftMargin = dp(10) end
    container.addView(buildRecentCard(projects[i]), lp)
  end
end

local function renderList(projects)
  local container = views.projectList
  if not container then return end
  container.removeAllViews()
  if #projects == 0 then
    views.emptyHint.setVisibility(0)
    views.listBlock.setVisibility(8)
    return
  end
  views.emptyHint.setVisibility(8)
  views.listBlock.setVisibility(0)
  for i, project in ipairs(projects) do
    addRowWithMargin(container, buildListRow(project), i > 1 and 8 or 0)
  end
end

function _M.refresh()
  if not built then return end
  local projects = scanProjects()
  renderRecent(projects)
  renderList(projects)
end

function _M.build()
  if built then return built end
  built = loadlayout({
    LinearLayout,
    layout_width = "match",
    layout_height = "match",
    orientation = "vertical",
    backgroundColor = background,
    {
      -- 顶栏：标题 + 新建按钮
      LinearLayout,
      orientation = "horizontal",
      layout_width = "match",
      layout_height = "wrap",
      gravity = "center_vertical",
      paddingLeft = "16dp",
      paddingRight = "16dp",
      paddingTop = "12dp",
      paddingBottom = "4dp",
      {
        MaterialTextView,
        text = res.string.home_tab_projects,
        textSize = "22sp",
        textStyle = "bold",
        textColor = onSurface,
        layout_width = "0dp",
        layout_weight = 1,
      },
      {
        MaterialButton,
        id = "btnNew",
        text = res.string.create_project,
        textSize = "13sp",
        layout_width = "wrap",
        layout_height = "wrap",
      },
    },
    {
      ScrollView,
      layout_width = "match",
      layout_height = "match",
      fillViewport = true,
      overScrollMode = 2,
      {
        LinearLayout,
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        paddingLeft = "16dp",
        paddingRight = "16dp",
        paddingBottom = "24dp",
        {
          -- 最近修改卡片行
          LinearLayout,
          id = "recentBlock",
          orientation = "vertical",
          layout_width = "match",
          layout_height = "wrap",
          layout_marginTop = "4dp",
          {
            MaterialTextView,
            text = res.string.home_recent_projects,
            textSize = "13sp",
            textStyle = "bold",
            textColor = onSurfaceVar,
            paddingBottom = "8dp",
          },
          {
            HorizontalScrollView,
            layout_width = "match",
            layout_height = "wrap",
            overScrollMode = 2,
            {
              LinearLayout,
              id = "recentRow",
              orientation = "horizontal",
              layout_width = "wrap",
              layout_height = "wrap",
            },
          },
        },
        {
          -- 全部工程列表
          LinearLayout,
          id = "listBlock",
          orientation = "vertical",
          layout_width = "match",
          layout_height = "wrap",
          layout_marginTop = "12dp",
          {
            MaterialTextView,
            text = res.string.home_all_projects,
            textSize = "13sp",
            textStyle = "bold",
            textColor = onSurfaceVar,
            paddingBottom = "8dp",
          },
          {
            LinearLayout,
            id = "projectList",
            orientation = "vertical",
            layout_width = "match",
            layout_height = "wrap",
          },
        },
        {
          MaterialTextView,
          id = "emptyHint",
          text = res.string.home_no_projects,
          textSize = "14sp",
          textColor = onSurfaceVar,
          gravity = "center",
          padding = "32dp",
          visibility = 8,
        },
      },
    },
  }, views)

  views.btnNew.onClick = function()
    require("activities.main.CreateProject").show({
      snack = function(msg)
        pcall(function() Toast.makeText(activity, msg, Toast.LENGTH_SHORT).show() end)
      end,
      onCreated = function()
        -- 创建完成后刷新列表（对话框不会触发 onResume）
        _M.refresh()
      end,
    })
  end

  return built
end

return _M
