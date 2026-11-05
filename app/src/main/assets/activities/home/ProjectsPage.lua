--- Native project home: IO-only scans, retained results, recycled searchable rows.
local M = {}
local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local HorizontalScrollView = luajava.bindClass("android.widget.HorizontalScrollView")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
local MaterialCardView = luajava.bindClass("com.google.android.material.card.MaterialCardView")
local EditText = luajava.bindClass("androidx.appcompat.widget.AppCompatEditText")
local UI = require "mods.ui.Components"
local ImageView = luajava.bindClass("androidx.appcompat.widget.AppCompatImageView")
local RecyclerView = luajava.bindClass("androidx.recyclerview.widget.RecyclerView")
local LinearLayoutManager = luajava.bindClass("androidx.recyclerview.widget.LinearLayoutManager")
local LuaRecyclerAdapter = luajava.bindClass("com.androlua.adapter.LuaRecyclerAdapter")
local Dialog = luajava.bindClass("com.google.android.material.dialog.MaterialAlertDialogBuilder")
local Snackbar = luajava.bindClass("com.google.android.material.snackbar.Snackbar")
local ActivityUtil = require "mods.utils.ActivityUtil"
local Data = require "mods.project.HomeProjects"
local Recent = require "mods.project.RecentProjects"
local Style = require "activities.home.HomeStyle"
local Rows = require "activities.home.HomeRows"
local S, colors = res.string, this.themeUtil
local built, adapter, job, directoryJob, directoryDialog
local views, projects, adapterData = {}, {}, {}
local generation, directoryGeneration = 0, 0
local state, query, disposed = "loading", "", false
local onSurface, secondary, surfaceCard
local rowUpdates, renderedRecent
local hasLoaded = false
local projectFields = { "path", "name", "appName", "pkg", "icon", "mtime" }
local recentFields = { "path", "name", "appName", "openedAt" }

local function snack(message)
  if built and not disposed then Snackbar.make(built, tostring(message), Snackbar.LENGTH_LONG).show() end
end
local function permission()
  return this.checkStoragePermission()
end
local function requestPermission()
  if _G.__homeUi and _G.__homeUi.requestStoragePermission then
    _G.__homeUi.requestStoragePermission()
  else
    this.requestStoragePermission()
  end
end
local function alive(token)
  return not disposed and generation == token and not activity.isFinishing() and not activity.isDestroyed()
end
local function openProject(path, openMain)
  local ok, opened = pcall(function()
    -- Ordinary project/folder opens must restore their workspace, not force main.lua
    -- or replace an unrelated pending request. Only newly created projects opt in.
    if openMain == true and ActivityUtil.setPending("open_file", path .. "/main.lua") ~= true then return false end
    return ActivityUtil.open("editor", path)
  end)
  if not ok or opened == false then snack(S.home_open_failed) return false end
  -- Metadata writes also stay off the UI thread. Editor can call record on successful open too.
  xTask(function() return Recent.record(path) end, nil, "io")
  return true
end
local function showProjectMenu(project)
  require("mods.project.ProjectMenu").show(project.path, project.name, {
    snack = snack,
    open = openProject,
    afterRename = function(oldPath, newPath, detail)
      -- Persistence service owns migration/status messaging, including pending failures.
      M.refresh()
    end,
    refresh = function() M.refresh() end,
    renameFailed = function(detail)
      -- Rejected requests (live editor/name conflict) did not start a migration.
      -- ProjectMenu already presents their specific failure message.
      if not detail or not detail.retryable then return end
      if not disposed then
        state = "rename_pending"
        views.status.setText(S.home_rename_pending)
        views.status.setVisibility(0)
        views.statusBlock.setVisibility(0)
        views.retry.setVisibility(0)
        views.retry.setEnabled(true)
        if _G.__homeUi and _G.__homeUi.pageContentReady then _G.__homeUi.pageContentReady("projects") end
      end
    end,
  })
end
local function rowData(project)
  return {
    title = project.appName or project.name,
    metadata = project.name .. (project.pkg and (" · " .. project.pkg) or ""),
    icon = project.icon or res.drawable("android_studio", secondary),
    projectRow = {
      contentDescription = (project.appName or project.name) .. "\n" .. project.path,
      onClick = function() openProject(project.path) end,
      onLongClick = function() showProjectMenu(project) return true end,
    },
  }
end
local function renderStatus()
  local text = ""
  if state == "permission" then text = S.need_manage_permission
  elseif state == "error" then text = S.home_scan_failed
  elseif state == "root_not_directory" then text = S.home_root_not_directory
  elseif state == "rename_pending" then text = S.home_rename_pending
  elseif state == "loading" and not hasLoaded then text = S.home_loading
  elseif #adapterData == 0 then text = query ~= "" and S.home_no_search_results or S.home_no_projects end
  views.status.setText(text)
  views.status.setVisibility(text == "" and 8 or 0)
  views.statusBlock.setVisibility(text == "" and 8 or 0)
  local recovery = state == "permission" or state == "error" or state == "root_not_directory" or state == "rename_pending"
  views.retry.setVisibility(recovery and 0 or 8)
  views.retry.setText(state == "permission" and S.home_grant_storage or S.home_retry)
  views.retry.setEnabled(state ~= "loading")
  views.clear.setVisibility(query == "" and 8 or 0)
  if state ~= "loading" and _G.__homeUi and _G.__homeUi.pageContentReady then
    _G.__homeUi.pageContentReady("projects")
  end
end
local function renderList()
  rowUpdates.submit(Data.filter(projects, query))
  renderStatus()
end
local function renderRecent(recent)
  local equal = renderedRecent and #renderedRecent == #recent
  if equal then
    for i, project in ipairs(recent) do
      if not Rows.same(renderedRecent[i], project, recentFields) then equal = false break end
    end
  end
  if equal then return end
  renderedRecent = recent
  views.recentRow.removeAllViews()
  views.recentBlock.setVisibility(#recent == 0 and 8 or 0)
  for _, project in ipairs(recent) do
    local card = loadlayout({ MaterialCardView, radius = "16dp", cardElevation = 0, strokeWidth = 0,
      CardBackgroundColor = surfaceCard, layout_width = "184dp", layout_height = "wrap",
      minHeight = "80dp", clickable = true, focusable = true, longClickable = true,
      contentDescription = (project.appName or project.name) .. "\n" .. project.path,
      { LinearLayout, orientation = "vertical", padding = "16dp", layout_width = "match", layout_height = "wrap",
        { MaterialTextView, text = project.appName or project.name, textSize = "16sp", textColor = onSurface,
          maxLines = 1, ellipsize = "end" },
        { MaterialTextView, text = os.date("%Y-%m-%d %H:%M", (project.openedAt or 0) / 1000),
           textSize = "12sp", textColor = secondary, layout_marginTop = "8dp" },
      },
    })
    card.onClick = function() openProject(project.path) end
    card.onLongClick = function() showProjectMenu(project) return true end
    -- Root loadlayout params have no parent. Supply width AND spacing here.
    local lp = LinearLayout.LayoutParams(this.dpToPx(184), -2)
    lp.setMarginEnd(this.dpToPx(12))
    views.recentRow.addView(card, lp)
  end
end
function M.refresh()
  if not built or disposed then return end
  generation = generation + 1
  local token = generation
  if job then pcall(function() job.cancel() end) job = nil end
  if not permission() then state = "permission" renderStatus() return end
  state = "loading"
  renderStatus() -- A loading indicator must not invalidate/rebind successful rows.
  local root = tostring(Bean.Path.app_root_pro_dir)
  local ok, launched = pcall(function()
    return xTask(function() return Data.scan(root) end, function(result)
      if not alive(token) or root ~= tostring(Bean.Path.app_root_pro_dir) then return end
      job = nil
      if not permission() then state = "permission" renderStatus() return end
      result = type(result) == "table" and result or { status = "error" }
      state = result.status
      -- Never turn a failed refresh into a successful empty dataset.
      if result.projects then
        projects, hasLoaded = result.projects, true
        renderRecent(result.recent or {})
        renderList()
      else renderStatus() end
    end, "io")
  end)
  if ok then job = launched else state = "error" renderStatus() end
end
local function openDirectoryDialog()
  if not permission() then requestPermission() return end
  local binding = {}
  -- Match the existing file/package dialogs: padded container + outlined field.
  local content = loadlayout({ LinearLayout, orientation = "vertical",
    layout_width = "match", layout_height = "wrap",
    paddingLeft = "20dp", paddingRight = "20dp", paddingTop = "12dp", paddingBottom = "4dp",
    focusable = true, focusableInTouchMode = true,
    UI.textField { id = "directoryInput", hint = S.home_directory_path,
      text = tostring(Bean.Path.app_root_pro_dir) },
  }, binding)
  local input = binding.directoryInput
  local dialog = Dialog(activity).setTitle(S.home_open_directory).setView(content)
    .setPositiveButton(S.open, nil).setNegativeButton(android.R.string.cancel, nil).create()
  dialog.setOnShowListener(function()
    local button = dialog.getButton(-1)
    button.onClick = function()
      directoryGeneration = directoryGeneration + 1
      local token, text = directoryGeneration, tostring(input.getText())
      input.setError(nil)
      if directoryJob then pcall(function() directoryJob.cancel() end) end
      button.setEnabled(false)
      directoryJob = xTask(function() return Data.chooseDirectory(text) end, function(path)
        if disposed or token ~= directoryGeneration or not dialog.isShowing() then return end
        directoryJob = nil
        button.setEnabled(true)
        if not path then input.setError(S.home_invalid_directory) return end
        if openProject(path) then dialog.dismiss() end
      end, "io")
    end
  end)
  directoryDialog = dialog
  dialog.show()
end
local function retryPendingRename()
  -- Recovery is deliberately explicit and synchronous: gate + backend cannot be
  -- separated by an IO job during which a new editor could acquire the old paths.
  local dialog = Dialog(activity).setTitle(S.rename).setMessage(S.home_rename_recovery_confirm)
    .setPositiveButton(S.home_retry, function()
      if disposed then return end
      local menu = require "mods.project.ProjectMenu"
      local called, complete, detail = pcall(menu.resumePendingRename)
      if not called or complete ~= true then
        if called and detail and detail.error == "project_in_use" then
          snack(S.project_rename_close_editor)
          return
        end
        state = "rename_pending"
        renderList()
        snack(S.home_rename_pending)
        return
      end
      M.refresh() -- one read-only refresh, never a recovery/refresh loop
    end).setNegativeButton(android.R.string.cancel, nil).create()
  directoryDialog = dialog
  dialog.show()
end
function M.pause()
  generation, directoryGeneration = generation + 1, directoryGeneration + 1
  if job then pcall(function() job.cancel() end) job = nil end
  if directoryJob then pcall(function() directoryJob.cancel() end) directoryJob = nil end
  if directoryDialog then pcall(function() directoryDialog.dismiss() end) directoryDialog = nil end
end
function M.dispose()
  M.pause()
  disposed = true
  built, adapter, views, adapterData = nil, nil, {}, {}
  rowUpdates, renderedRecent = nil, nil
end
M.onDispose = M.dispose
function M.build()
  if built then return built end
  disposed = false
  onSurface, secondary, surfaceCard = colors.getColorOnSurface(), colors.getColorOnSurfaceVariant(), colors.getColorSurfaceContainer()
  local create = Style.action("btnNew", S.home_create_project)
  local folder = UI.iconButton { id = "openDirectory", icon = res.drawable("folder"),
    description = S.home_open_directory,
    props = { layout_marginStart = "12dp", backgroundTint = colors.getColorSecondaryContainer(),
      iconTint = colors.getColorOnSecondaryContainer() },
  }
  local clear = UI.iconButton { id = "clear", icon = res.drawable("close"), description = S.clear,
    props = { iconTint = secondary, visibility = 8 },
  }
  built = loadlayout(Style.listPage({ LinearLayout, orientation = "vertical", layout_width = "match", layout_height = "wrap",
    backgroundColor = colors.getColorSurface(), paddingLeft = "20dp", paddingRight = "20dp",
    Style.header(S.home_tab_projects, create),
    { LinearLayout, orientation = "horizontal", gravity = "center_vertical", layout_width = "match", layout_height = "wrap",
      { MaterialCardView, radius = "16dp", cardElevation = 0, strokeWidth = 0,
        CardBackgroundColor = surfaceCard, layout_width = "0dp", layout_weight = 1, layout_height = "wrap",
        { LinearLayout, orientation = "horizontal", gravity = "center_vertical",
          layout_width = "match", layout_height = "wrap", paddingStart = "16dp", paddingEnd = "4dp",
          { ImageView, src = res.drawable("search", secondary), layout_width = "20dp", layout_height = "20dp",
            importantForAccessibility = 2 },
          { EditText, id = "search", hint = S.home_search_projects, contentDescription = S.home_search_projects,
            textSize = "14sp", singleLine = true, textColor = onSurface, hintTextColor = secondary,
            backgroundColor = 0, paddingStart = "12dp", paddingEnd = "8dp", minHeight = "56dp",
            layout_width = "0dp", layout_weight = 1, layout_height = "wrap" },
          clear,
        },
      },
      folder,
    },
    { LinearLayout, orientation = "vertical", id = "recentBlock", visibility = 8,
      layout_width = "match", layout_height = "wrap",
      Style.section(S.home_recent_projects),
      { HorizontalScrollView, layout_width = "match", layout_height = "wrap", overScrollMode = 2, horizontalScrollBarEnabled = false,
        { LinearLayout, id = "recentRow", orientation = "horizontal", layout_width = "wrap", layout_height = "wrap" } },
    },
    Style.section(S.home_all_projects),
    { LinearLayout, id = "statusBlock", orientation = "vertical", layout_width = "match", layout_height = "wrap",
      paddingBottom = "12dp", visibility = 8,
      { MaterialTextView, id = "status", textSize = "14sp", textColor = secondary,
        accessibilityLiveRegion = 1, layout_width = "match", layout_height = "wrap", paddingTop = "8dp", paddingBottom = "8dp" },
      Style.action("retry", S.home_retry, "tonal"),
    },
  }, { RecyclerView, id = "projectList", layout_width = "match",
      clipToPadding = false, paddingBottom = "24dp" }), views)
  views.pageHeader.setId(0x00d0f002)
  local rowLayout = { MaterialCardView, id = "projectRow", radius = "16dp", cardElevation = 0, strokeWidth = 0,
    CardBackgroundColor = surfaceCard, layout_width = "match", layout_height = "wrap", layout_marginBottom = "12dp",
    minHeight = "80dp", clickable = true, focusable = true, longClickable = true,
    { LinearLayout, orientation = "horizontal", gravity = "center_vertical", padding = "16dp",
      layout_width = "match", layout_height = "wrap",
      { ImageView, id = "icon", layout_width = "44dp", layout_height = "44dp", scaleType = "fitCenter", importantForAccessibility = 2 },
      { LinearLayout, orientation = "vertical", layout_width = "0dp", layout_weight = 1, layout_height = "wrap", layout_marginStart = "16dp",
        { MaterialTextView, id = "title", textSize = "16sp", textStyle = "bold", textColor = onSurface, maxLines = 1, ellipsize = "end" },
        { MaterialTextView, id = "metadata", textSize = "12sp", textColor = secondary, maxLines = 2, ellipsize = "end", layout_marginTop = "4dp" },
      },
    },
  }
  adapter = LuaRecyclerAdapter(activity, adapterData, rowLayout)
  rowUpdates = Rows.new(adapterData, adapter, function(row) return row.path end,
    function(a, b) return Rows.same(a, b, projectFields) end, rowData)
  views.projectList.setLayoutManager(LinearLayoutManager(activity))
  views.projectList.setAdapter(adapter) -- existing adapter's Coil loader decodes/caches icons off-thread
  -- loadlayout's generated IDs vary across Activity instances. This ID is deliberately
  -- outside the shell's per-page scroller range and lets Android restore text/selection.
  views.search.setId(0x00d0f001)
  views.search.setSaveEnabled(true)
  views.search.setFreezesText(true)
  views.search.addTextChangedListener(luajava.bindClass("android.text.TextWatcher")({
    beforeTextChanged = function() end, onTextChanged = function() end,
    afterTextChanged = function(text) query = tostring(text or "") renderList() end,
  }))
  views.clear.onClick = function() views.search.setText("") end
  views.retry.onClick = function()
    if not permission() then requestPermission()
    elseif state == "rename_pending" then retryPendingRename()
    else M.refresh() end
  end
  views.openDirectory.onClick = openDirectoryDialog
  views.btnNew.onClick = function()
    if not permission() then requestPermission() return end
    require("activities.main.CreateProject").show({ snack = snack,
      onCreated = function(path, openAfter) M.refresh() end,
      openProject = function(path) return openProject(path, true) end })
  end
  state = permission() and "loading" or "permission"
  if query ~= "" then views.search.setText(query) else renderList() end
  -- Shell owns refresh scheduling, including the initial visible-page scan.
  return built
end
return M
