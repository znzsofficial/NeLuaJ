--- Process-owned MCP session; closing this dialog does not stop the server.
local M = {}
local Dialog = luajava.bindClass("com.google.android.material.dialog.MaterialAlertDialogBuilder")
local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local ScrollView = luajava.bindClass("android.widget.ScrollView")
local TextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
local Button = luajava.bindClass("com.google.android.material.button.MaterialButton")
local JSONObject = luajava.bindClass("org.json.JSONObject")
local File = luajava.bindClass("java.io.File")
local S = res.string
local active, child, busy, activeRefresh = nil, nil, false, nil

local function runtime()
  return luajava.kotlinObject("com.nekolaska.mcp.server.McpRuntime")
end
local function alive(dialog)
  return active == dialog and not activity.isFinishing() and not activity.isDestroyed()
end
function M.dismiss()
  if child then pcall(function() child.dismiss() end) child = nil end
  if active then pcall(function() active.dismiss() end) active = nil end
  activeRefresh = nil
end

function M.show()
  if active then return end
  local colors, views = this.themeUtil, {}
  local selected, writable, running, valid = nil, false, false, false
  local requireToken = true
  local function label(id, text)
    return { TextView, id = id, text = text, textSize = "14sp",
      textColor = colors.getColorOnSurfaceVariant(), layout_width = "match",
      layout_height = "wrap", layout_marginBottom = "12dp" }
  end
  local function button(id, text)
    return { Button, id = id, text = text, layout_width = "match", layout_height = "wrap",
      minHeight = "48dp", layout_marginTop = "8dp" }
  end
  local content = loadlayout({ ScrollView, layout_width = "match", layout_height = "wrap",
    { LinearLayout, orientation = "vertical", layout_width = "match", layout_height = "wrap",
      paddingLeft = "24dp", paddingRight = "24dp", paddingBottom = "16dp",
      label("status", S.mcp_stopped), label("scope", S.mcp_choose_hint),
       button("project", S.home_choose_project), button("permission", S.mcp_read_only),
       button("authentication", S.mcp_token_required),
      label("accessHint", S.mcp_access_hint), button("toggle", S.mcp_start),
      button("config", S.mcp_copy_config), button("token", S.mcp_copy_token),
      button("rotate", S.mcp_rotate), button("refresh", S.mcp_refresh),
      label("recent", S.mcp_recent_empty),
      label("lifetime", S.mcp_lifetime), label("adb", S.mcp_adb),
    } }, views)
  local dialog = Dialog(activity).setTitle(S.mcp_title).setView(content)
    .setPositiveButton(android.R.string.ok, nil).create()
  active = dialog
  local function controls()
    views.project.setEnabled(not busy and valid and not running)
    views.permission.setEnabled(not busy and valid and not running)
    views.authentication.setEnabled(not busy and valid and not running)
    views.authentication.setText(requireToken and S.mcp_token_required or S.mcp_token_optional)
    views.toggle.setEnabled(not busy and valid and (running or selected ~= nil))
    views.toggle.setText(running and S.mcp_stop or S.mcp_start)
    views.permission.setText(writable and S.mcp_read_write or S.mcp_read_only)
    views.config.setEnabled(not busy and valid and running)
    for _, name in ipairs({ "token", "rotate" }) do
      views[name].setEnabled(not busy and valid and running and requireToken)
    end
    views.refresh.setEnabled(not busy)
  end
  local function refresh(raw)
    local ok, state = pcall(function() return JSONObject(raw or tostring(runtime().status())) end)
    valid = ok
    if not ok then
      views.status.setText(S.mcp_failed)
      controls()
      return
    end
    running = state.optBoolean("running", false)
    if running then
      selected = tostring(state.optString("projectRoot", ""))
      writable = state.optBoolean("writable", false)
      requireToken = state.optBoolean("requireToken", true)
    end
    local text = running and S.mcp_running or S.mcp_stopped
    if running then text = text .. "\n" .. tostring(state.optString("endpoint", "http://127.0.0.1:8765/mcp")) end
    if state.has("error") and not state.isNull("error") and tostring(state.optString("error", "")) ~= "" then
      text = text .. "\n" .. tostring(state.optString("error", ""))
    end
    local recent = state.optJSONArray("recent")
    local entries = {}
    if recent then
      for i = 0, math.min(recent.length(), 5) - 1 do
        local entry = recent.optJSONObject(i)
        if entry then
          local timestamp = tonumber(tostring(entry.optLong("time", 0))) or 0
          local time = timestamp > 0 and os.date("%H:%M:%S", math.floor(timestamp / 1000)) or ""
          entries[#entries + 1] = time .. "  " .. tostring(entry.optString("tool", ""))
            .. " · " .. (entry.optBoolean("success", false) and S.mcp_call_success or S.mcp_call_failed)
        end
      end
    end
    views.recent.setText(#entries > 0 and (S.mcp_recent .. "\n" .. table.concat(entries, "\n")) or S.mcp_recent_empty)
    views.status.setText(text)
    views.scope.setText(selected or S.mcp_choose_hint)
    controls()
  end
  local function work(action, done)
    if busy then return end
    busy = true
    views.status.setText(S.mcp_working)
    controls()
    local launched = pcall(function()
      xTask(function()
        local ok, value = pcall(action)
        -- Never pass exception text, configuration or credentials to a logger.
        return { ok = ok, value = ok and value or nil }
      end, function(result)
        busy = false
        if not alive(dialog) then
          if activeRefresh then activeRefresh() end
          return
        end
        refresh()
        if type(result) ~= "table" or not result.ok then views.status.setText(S.mcp_failed) return end
        if done then done(result.value) end
      end, "io")
    end)
    if not launched then busy = false refresh() views.status.setText(S.mcp_failed) end
  end
  views.project.onClick = function()
    if not this.checkStoragePermission() then
      views.status.setText(S.need_manage_permission)
      this.requestStoragePermission()
      return
    end
    work(function()
      local result = require("mods.project.HomeProjects").scan(tostring(Bean.Path.app_root_pro_dir))
      if result.status == "rename_pending" or not result.projects then return nil end
      return result.projects
    end, function(projects)
      if not projects then views.status.setText(S.home_scan_failed) return end
      if #projects == 0 then views.status.setText(S.home_no_project_guidance) return end
      local names = {}
      for _, project in ipairs(projects) do names[#names + 1] = project.name .. "\n" .. project.path end
      child = Dialog(activity).setTitle(S.home_choose_project).setItems(names, function(_, which)
        local project = projects[(tonumber(tostring(which)) or -1) + 1]
        if project and alive(dialog) then selected = project.path refresh() end
      end).setNegativeButton(android.R.string.cancel, nil).show()
    end)
  end
  views.permission.onClick = function()
    child = Dialog(activity).setTitle(S.mcp_permissions)
      .setSingleChoiceItems({ S.mcp_read_only, S.mcp_read_write }, writable and 1 or 0, function(d, which)
        writable = tonumber(tostring(which)) == 1
        controls()
        d.dismiss()
      end).setNegativeButton(android.R.string.cancel, nil).show()
  end
  views.authentication.onClick = function()
    if busy or not valid or running then return end
    child = Dialog(activity).setTitle(S.mcp_authentication)
      .setSingleChoiceItems({ S.mcp_token_required, S.mcp_token_optional }, requireToken and 0 or 1, function(d, which)
        if alive(dialog) and not busy and valid and not running then
          requireToken = tonumber(tostring(which)) == 0
          controls()
        end
        d.dismiss()
      end).setNegativeButton(android.R.string.cancel, nil).show()
  end
  views.toggle.onClick = function()
    if running then work(function() runtime().stop() return tostring(runtime().status()) end, refresh) return end
    local path, allowWrite, authenticate = selected, writable, requireToken
    local root, agentRoot = tostring(Bean.Path.app_root_pro_dir), tostring(Bean.Path.agent_root_dir)
    local context = activity.getApplicationContext()
    work(function()
      -- Revalidate membership immediately before starting, including symlink escapes.
      local base, project = File(root).getCanonicalFile(), File(path).getCanonicalFile()
      if not project.isDirectory() or not project.canRead() or not base.equals(project.getParentFile()) then
        return nil
      end
      -- Keep HomeProjects' lexical path: AgentStorage scope keys distinguish aliases.
      return tostring(runtime().start(context, path, agentRoot, allowWrite, authenticate))
    end, function(raw)
      if raw then refresh(raw) else views.status.setText(S.home_invalid_project) end
    end)
  end
  local function copy(kind)
    local ok = pcall(function()
      local value = kind == "token" and tostring(runtime().token()) or tostring(runtime().configuration())
      local ClipData = luajava.bindClass("android.content.ClipData")
      local clip = ClipData.newPlainText("MCP", value)
      if kind == "token" then
        pcall(function()
          local extras = luajava.bindClass("android.os.PersistableBundle")()
          extras.putBoolean("android.content.extra.IS_SENSITIVE", true)
          clip.getDescription().setExtras(extras)
        end)
      end
      activity.getSystemService("clipboard").setPrimaryClip(clip)
    end)
    views.status.setText(ok and S.mcp_copied or S.mcp_failed)
  end
  views.config.onClick = function() copy("configuration") end
  views.token.onClick = function()
    if not busy and valid and running and requireToken then copy("token") end
  end
  views.rotate.onClick = function()
    if busy or not valid or not running or not requireToken then return end
    child = Dialog(activity).setTitle(S.mcp_rotate).setMessage(S.mcp_rotate_hint)
      .setPositiveButton(S.mcp_rotate, function()
        work(function() return tostring(runtime().rotateToken()) end, refresh)
      end).setNegativeButton(android.R.string.cancel, nil).show()
  end
  views.refresh.onClick = function() refresh() end
  activeRefresh = refresh
  dialog.setOnDismissListener(function()
    if active == dialog then active, activeRefresh = nil, nil end
    if child then pcall(function() child.dismiss() end) child = nil end
  end)
  dialog.show()
  refresh()
end

return M
