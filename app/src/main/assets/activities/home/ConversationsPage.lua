--- Cross-project conversation index. Loading/errors retain the last successful rows.
local M = {}
local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local RecyclerView = luajava.bindClass("androidx.recyclerview.widget.RecyclerView")
local LinearLayoutManager = luajava.bindClass("androidx.recyclerview.widget.LinearLayoutManager")
local LuaRecyclerAdapter = luajava.bindClass("com.androlua.adapter.LuaRecyclerAdapter")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
local MaterialCardView = luajava.bindClass("com.google.android.material.card.MaterialCardView")
local ImageView = luajava.bindClass("androidx.appcompat.widget.AppCompatImageView")
local Dialog = luajava.bindClass("com.google.android.material.dialog.MaterialAlertDialogBuilder")
local Snackbar = luajava.bindClass("com.google.android.material.snackbar.Snackbar")
local Store = require "mods.agent.ConversationStore"
local TextUtil = require "mods.utils.TextUtil"
local ActivityUtil = require "mods.utils.ActivityUtil"
local Projects = require "mods.project.HomeProjects"
local Recent = require "mods.project.RecentProjects"
local Style = require "activities.home.HomeStyle"
local Rows = require "activities.home.HomeRows"
local S, colors = res.string, this.themeUtil
local built, adapter, job, actionJob, deleteJob, activeDialog
local views, rows, adapterData = {}, {}, {}
local generation, actionGeneration = 0, 0
local disposed = false
local rowUpdates, hasLoaded = nil, false
local conversationFields = { "id", "name", "projectPath", "messageCount", "updatedAt", "running" }
local function snack(text)
  if built and not disposed then Snackbar.make(built, tostring(text), Snackbar.LENGTH_LONG).show() end
end
local function alive()
  return not disposed and not activity.isFinishing() and not activity.isDestroyed()
end
local function requestPermission()
  if _G.__homeUi and _G.__homeUi.requestStoragePermission then
    _G.__homeUi.requestStoragePermission()
  else
    this.requestStoragePermission()
  end
end
local function convName(conv)
  local name = tostring(conv.name or "")
  return name ~= "" and name or S.ai_unnamed_conv
end
local function navigate(project, action, payload)
  actionGeneration = actionGeneration + 1
  local token = actionGeneration
  if actionJob then pcall(function() actionJob.cancel() end) end
  actionJob = xTask(function() return Projects.chooseDirectory(project) end, function(path)
    if not alive() or token ~= actionGeneration then return end
    actionJob = nil
    if not path then snack(S.home_invalid_project) return end
    local ok, opened = pcall(function()
      if ActivityUtil.setPending(action, action == "open_agent_new" and path or (path .. "\n" .. payload)) ~= true then return false end
      return ActivityUtil.open("editor", path)
    end)
    if not ok or opened == false then snack(S.home_open_failed) return end
    xTask(function() return Recent.record(path) end, nil, "io")
  end, "io")
end
local function openConversation(conv, project)
  -- Never silently substitute the Projects root for a missing/deleted project.
  navigate(project or conv.projectPath, "open_agent_conv_switch", tostring(conv.id))
end
local function confirmDelete(conv)
  activeDialog = Dialog(activity).setTitle(S.ai_delete_conv).setMessage(S.ai_confirm_delete_conv:format(convName(conv)))
    .setPositiveButton(S.ai_delete, function()
      local token = generation
      deleteJob = xTask(function() return Store.delete(conv.id, conv.projectPath) end, function(ok)
        if not alive() or token ~= generation then return end
        deleteJob = nil
        snack(ok and S.ai_deleted or S.ai_delete_failed)
        if ok then M.refresh() end
      end, "io")
    end).setNegativeButton(android.R.string.cancel, nil).show()
end
local function showMenu(conv, project)
  activeDialog = Dialog(activity).setTitle(convName(conv)).setItems({ S.open, S.ai_delete }, function(_, which)
    which = tonumber(tostring(which))
    if which == 0 then openConversation(conv, project) elseif which == 1 then confirmDelete(conv) end
  end).setNegativeButton(android.R.string.cancel, nil).show()
end
local function rowData(item)
  local conv, project = item.conv, tostring(item.projectName or "")
  local name = convName(conv)
  local parts = { S.ai_center_msg_count:format(tonumber(conv.messageCount) or 0) }
  local tokens = type(conv.usage) == "table" and tonumber(conv.usage.tokens) or nil
  if tokens and tokens > 0 then parts[#parts + 1] = S.ai_row_usage:format(TextUtil.fmtTokens(tokens)) end
  if tostring(conv.updatedAt or "") ~= "" then parts[#parts + 1] = tostring(conv.updatedAt) end
  local projectName = project ~= "" and (project:gsub("/+$", ""):match("[^/]+$") or project) or ""
  local metadata = table.concat(parts, " · ")
  return {
    title = name, metadata = metadata,
    project = { text = projectName, visibility = projectName == "" and 8 or 0 },
    badge = { text = S.ai_conv_running, visibility = conv.running and 0 or 8 },
    conversationRow = { contentDescription = name .. "\n" .. projectName .. "\n" .. metadata,
      onClick = function() openConversation(conv, project) end,
      onLongClick = function() showMenu(conv, project) return true end },
  }
end
local function sameConversation(a, b)
  local aTokens = type(a.conv.usage) == "table" and a.conv.usage.tokens or nil
  local bTokens = type(b.conv.usage) == "table" and b.conv.usage.tokens or nil
  return a.projectName == b.projectName and Rows.same(a.conv, b.conv, conversationFields) and
    aTokens == bTokens
end
local function renderRows()
  rowUpdates.submit(rows)
end
local function setStatus(text, recovery)
  views.status.setText(text or "")
  views.status.setVisibility(text and text ~= "" and 0 or 8)
  views.statusBlock.setVisibility(text and text ~= "" and 0 or 8)
  views.retry.setVisibility(recovery and 0 or 8)
  views.retry.setText(not this.checkStoragePermission() and S.home_grant_storage or S.home_retry)
  if text ~= S.home_loading and _G.__homeUi and _G.__homeUi.pageContentReady then
    _G.__homeUi.pageContentReady("conversations")
  end
end
function M.refresh()
  if not built or disposed then return end
  generation = generation + 1
  local token = generation
  if job then pcall(function() job.cancel() end) job = nil end
  if not this.checkStoragePermission() then setStatus(S.need_manage_permission, true) return end
  setStatus(not hasLoaded and S.home_loading or (#rows == 0 and S.home_conversation_guidance or nil), false)
  local ok, launched = pcall(function()
    return xTask(function()
      local loaded, records, err = pcall(Store.loadIndex, true)
      if not loaded or err or type(records) ~= "table" then return { error = true } end
      local result = {}
      for _, record in ipairs(records) do
        local count = tonumber(record.messageCount) or 0
        local name = tostring(record.name or "")
        local placeholder = count == 0 and (name == "" or name == "新对话" or name == S.ai_new_conv or name == S.ai_unnamed_conv)
        if not placeholder then result[#result + 1] = { conv = record, projectName = record.projectPath } end
      end
      table.sort(result, function(a, b)
        local left, right = tostring(a.conv.updatedAt or ""), tostring(b.conv.updatedAt or "")
        if left == right then return tostring(a.conv.id) < tostring(b.conv.id) end
        return left > right
      end)
      return { rows = result }
    end, function(result)
      if not alive() or token ~= generation then return end
      job = nil
      if not this.checkStoragePermission() then setStatus(S.need_manage_permission, true) return end
      if type(result) ~= "table" or result.error then setStatus(S.home_conversations_failed, true) return end
      rows, hasLoaded = result.rows, true
      renderRows()
      -- Notify only after the adapter's backing rows and item count have changed.
      setStatus(#rows == 0 and S.home_conversation_guidance or nil, false)
    end, "io")
  end)
  if ok then job = launched else setStatus(S.home_conversations_failed, true) end
end
local function chooseProject()
  if not this.checkStoragePermission() then requestPermission() return end
  actionGeneration = actionGeneration + 1
  local token = actionGeneration
  if actionJob then pcall(function() actionJob.cancel() end) end
  setStatus(S.home_loading, false)
  actionJob = xTask(function() return Projects.scan(tostring(Bean.Path.app_root_pro_dir)) end, function(result)
    if not alive() or token ~= actionGeneration then return end
    actionJob = nil
    if type(result) ~= "table" or not result.projects then
      setStatus(S.home_scan_failed, true)
      return
    end
    if result.status == "rename_pending" then setStatus(S.home_rename_pending, true) return end
    if #result.projects == 0 then
      setStatus(S.home_no_project_guidance, false)
      -- A real creation route; onCreated is notification, openProject supplies the pending new chat.
      activeDialog = Dialog(activity).setTitle(S.home_choose_project).setMessage(S.home_no_project_guidance)
        .setPositiveButton(S.create_project, function()
          require("activities.main.CreateProject").show({ snack = snack,
            onCreated = function() M.refresh() end,
            openProject = function(path) navigate(path, "open_agent_new") return true end })
        end).setNegativeButton(android.R.string.cancel, nil).show()
      return
    end
    setStatus(#rows == 0 and S.home_conversation_guidance or nil, false)
    local names = {}
    for _, project in ipairs(result.projects) do
      names[#names + 1] = (project.appName or project.name) .. "\n" .. project.path
    end
    activeDialog = Dialog(activity).setTitle(S.home_choose_project).setItems(names, function(_, which)
      local project = result.projects[(tonumber(tostring(which)) or -1) + 1]
      if project then navigate(project.path, "open_agent_new") end
    end).setNegativeButton(android.R.string.cancel, nil).show()
  end, "io")
end
function M.pause()
  generation, actionGeneration = generation + 1, actionGeneration + 1
  if job then pcall(function() job.cancel() end) job = nil end
  if actionJob then pcall(function() actionJob.cancel() end) actionJob = nil end
  if deleteJob then pcall(function() deleteJob.cancel() end) deleteJob = nil end
  if activeDialog then pcall(function() activeDialog.dismiss() end) activeDialog = nil end
end
function M.dispose()
  M.pause()
  disposed = true
  built, adapter, views, adapterData = nil, nil, {}, {}
  rowUpdates = nil
end
M.onDispose = M.dispose
function M.build()
  if built then return built end
  disposed = false
  built = loadlayout(Style.listPage({ LinearLayout, orientation = "vertical", layout_width = "match", layout_height = "wrap",
    backgroundColor = colors.getColorSurface(), paddingLeft = "20dp", paddingRight = "20dp",
    Style.header(S.home_tab_conversations, Style.action("newConversation", S.home_new_conversation)),
    { LinearLayout, id = "statusBlock", orientation = "vertical", layout_width = "match", layout_height = "wrap",
      paddingTop = "16dp", paddingBottom = "24dp", visibility = 8,
      { MaterialTextView, id = "status", textSize = "14sp", textColor = colors.getColorOnSurfaceVariant(),
        accessibilityLiveRegion = 1, layout_width = "match", layout_height = "wrap", paddingBottom = "12dp" },
      Style.action("retry", S.home_retry, "tonal"),
    },
  }, { RecyclerView, id = "convList", layout_width = "match",
      clipToPadding = false, paddingTop = "8dp", paddingBottom = "24dp" }), views)
  views.pageHeader.setId(0x00d1f002)
  local rowLayout = { MaterialCardView, id = "conversationRow", radius = "16dp", cardElevation = 0, strokeWidth = 0,
    CardBackgroundColor = colors.getColorSurfaceContainer(), layout_width = "match", layout_height = "wrap",
    layout_marginBottom = "12dp", minHeight = "80dp", clickable = true, focusable = true, longClickable = true,
    { LinearLayout, orientation = "horizontal", layout_width = "match", layout_height = "wrap", padding = "16dp",
      { ImageView, src = res.drawable("ic_comment", colors.getColorOnSurfaceVariant()),
        layout_width = "24dp", layout_height = "24dp", layout_marginTop = "2dp", importantForAccessibility = 2 },
      { LinearLayout, orientation = "vertical", layout_width = "0dp", layout_weight = 1,
        layout_height = "wrap", layout_marginStart = "16dp",
        { MaterialTextView, id = "title", textSize = "16sp", textStyle = "bold", textColor = colors.getColorOnSurface(),
          layout_width = "match", layout_height = "wrap", maxLines = 2, ellipsize = "end" },
        { MaterialTextView, id = "project", textSize = "13sp", textColor = colors.getColorPrimary(),
          layout_width = "match", layout_height = "wrap", maxLines = 1, ellipsize = "end", layout_marginTop = "8dp" },
        { MaterialTextView, id = "metadata", textSize = "12sp", textColor = colors.getColorOnSurfaceVariant(),
          layout_width = "match", layout_height = "wrap", maxLines = 2, ellipsize = "end", layout_marginTop = "4dp" },
        { MaterialTextView, id = "badge", textSize = "12sp", textColor = colors.getColorPrimary(),
          layout_width = "wrap", layout_height = "wrap", layout_marginTop = "8dp", visibility = 8 },
      },
    },
  }
  adapter = LuaRecyclerAdapter(activity, adapterData, rowLayout)
  rowUpdates = Rows.new(adapterData, adapter,
    function(row) return tostring(row.conv.id) end, sameConversation, rowData)
  views.convList.setLayoutManager(LinearLayoutManager(activity))
  views.convList.setAdapter(adapter)
  views.newConversation.onClick = chooseProject
  views.retry.onClick = function()
    if not this.checkStoragePermission() then requestPermission() else M.refresh() end
  end
  renderRows()
  setStatus(not this.checkStoragePermission() and S.need_manage_permission or
    (not hasLoaded and S.home_loading or (#rows == 0 and S.home_conversation_guidance or nil)), not this.checkStoragePermission())
  return built
end
return M
