require "mods.bootstrap"

import "java.io.File"
import "android.os.Environment"
import "android.view.View"
import "android.view.WindowManager"
import "android.widget.ArrayAdapter"
import "android.widget.Toast"
import "android.content.Context"
import "android.content.Intent"
import "android.graphics.drawable.ColorDrawable"
import "android.text.TextWatcher"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"

this.dynamicColor()
local res = res
local ColorUtil = this.themeUtil
local primaryColor = ColorUtil.ColorPrimary

this.setContentView(loadlayout(res.layout.media_browser))
  .setTitle(res.string.media_browser or "Media 浏览器")
  .getSupportActionBar()
  .setElevation(0)
  .setBackgroundDrawable(ColorDrawable(ColorUtil.getColorBackground()))
  .setDisplayShowHomeEnabled(true)
  .setDisplayHomeAsUpEnabled(true)

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

-- ─── 路径 ───────────────────────────────────────────────
local function mediaRoot()
  local ok, p = pcall(function()
    return this.getMediaDir().getAbsolutePath()
  end)
  if ok and p and p ~= "" then return p end
  ok, p = pcall(function()
    local dirs = activity.getExternalMediaDirs()
    if dirs and #dirs > 0 then return dirs[0].getAbsolutePath() end
  end)
  if ok and p then return p end
  return activity.getFilesDir().getAbsolutePath()
end

local function luaJRoot()
  local ok, p = pcall(function()
    return Environment.getExternalStorageDirectory().getAbsolutePath() .. "/LuaJ"
  end)
  if ok and p then return p end
  return mediaRoot()
end

local ROOTS = {
  all = { label = res.string.media_root_all or "全部", path = mediaRoot() },
  crash = { label = res.string.media_root_crash or "崩溃日志", path = mediaRoot() .. "/crash" },
  backups = { label = res.string.media_root_backups or "代码备份", path = mediaRoot() .. "/backups" },
  zip = { label = res.string.media_root_zip or "工程 ZIP", path = luaJRoot() .. "/Backup" },
}

local currentKey = "all"
local currentDir = ROOTS.all.path
local entries = {} -- full list in currentDir
local visible = {} -- filtered
local adapter
local searchQuery = ""

local function ensureDir(path)
  pcall(function()
    local f = File(path)
    if not f.exists() then f.mkdirs() end
  end)
end

local function humanSize(n)
  n = tonumber(n) or 0
  if n < 1024 then return string.format("%d B", n) end
  if n < 1024 * 1024 then return string.format("%.1f KB", n / 1024) end
  return string.format("%.1f MB", n / (1024 * 1024))
end

local function formatTime(ms)
  ms = tonumber(ms) or 0
  if ms <= 0 then return "—" end
  local sec = math.floor(ms / 1000)
  return os.date("%Y-%m-%d %H:%M", sec)
end

local function isTextLike(name)
  name = tostring(name or ""):lower()
  return name:match("%.log$")
    or name:match("%.txt$")
    or name:match("%.lua$")
    or name:match("%.json$")
    or name:match("%.md$")
    or name:match("%.xml$")
    or name:match("%.html$")
    or name:match("%.css$")
    or name:match("%.js$")
    or name:match("%.ini$")
    or name:match("%.prop")
end

local function snack(msg)
  Toast.makeText(activity, tostring(msg), Toast.LENGTH_SHORT).show()
end

local function copyText(s)
  activity.getSystemService(Context.CLIPBOARD_SERVICE).setText(tostring(s))
  snack(tostring(s) .. (res.string.copy_success or " 已复制"))
end

local function readFileLimited(path, maxBytes)
  maxBytes = maxBytes or 256 * 1024
  local f = io.open(path, "rb")
  if not f then return nil, "cannot open" end
  local data = f:read(maxBytes + 1)
  f:close()
  if not data then return "", nil end
  local truncated = #data > maxBytes
  if truncated then data = data:sub(1, maxBytes) end
  -- strip NULs for display
  data = data:gsub("%z", "")
  return data, truncated
end

local function openExternal(path)
  pcall(function()
    this.openFile(path, function()
      snack(res.string.NoSupport or "无法打开")
    end)
  end)
end

local function shareFile(path)
  pcall(function()
    local intent = Intent(Intent.ACTION_SEND)
    intent.setType("text/plain")
    local uri = activity.getUriForPath(path)
    intent.putExtra(Intent.EXTRA_STREAM, uri)
    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    intent.putExtra(Intent.EXTRA_SUBJECT, File(path).getName())
    activity.startActivity(Intent.createChooser(intent, res.string.media_share or "分享"))
  end)
end

local function deletePath(path, onDone)
  MaterialAlertDialogBuilder(activity)
    .setTitle(res.string.delete or "删除")
    .setMessage(tostring(path))
    .setPositiveButton(android.R.string.ok, function()
      pcall(function()
        local LuaUtil = bindClass "com.androlua.LuaUtil"
        LuaUtil.rmDir(File(path))
      end)
      if onDone then onDone() end
    end)
    .setNegativeButton(android.R.string.cancel, nil)
    .show()
end

local function showPreview(path, name)
  local body, truncated = readFileLimited(path, 200 * 1024)
  if body == nil then
    openExternal(path)
    return
  end
  local msg = body
  if truncated then
    msg = msg .. "\n\n… (" .. (res.string.media_truncated or "内容过长已截断") .. ")"
  end
  MaterialAlertDialogBuilder(activity)
    .setTitle(name or File(path).getName())
    .setMessage(msg)
    .setPositiveButton(res.string.media_open_external or "外部打开", function()
      openExternal(path)
    end)
    .setNeutralButton(res.string.media_share or "分享", function()
      shareFile(path)
    end)
    .setNegativeButton(android.R.string.cancel, nil)
    .show()
end

local function rootPathFor(key)
  return ROOTS[key] and ROOTS[key].path or mediaRoot()
end

local function isUnderRoot(dir)
  local root = rootPathFor(currentKey)
  dir = tostring(dir or "")
  root = tostring(root or "")
  if dir == root then return true end
  if #dir > #root and dir:sub(1, #root) == root then
    local c = dir:sub(#root + 1, #root + 1)
    return c == "/" or c == "\\"
  end
  return false
end

local function listDir(dir)
  local list = {}
  local f = File(dir)
  if not f.exists() or not f.isDirectory() or not f.canRead() then
    return list
  end
  local arr = f.listFiles()
  if not arr then return list end
  -- 与 MainFileList 一致：for _, child in (files) 遍历 Java File[]
  for _, child in (arr) do
    local name = tostring(child.getName())
    local isDir = child.isDirectory()
    local size = 0
    local mtime = 0
    pcall(function()
      if not isDir then size = child.length() end
      mtime = child.lastModified()
    end)
    list[#list + 1] = {
      path = tostring(child.getAbsolutePath()),
      name = name,
      isDir = isDir,
      size = size,
      mtime = mtime,
    }
  end
  table.sort(list, function(a, b)
    if a.isDir ~= b.isDir then return a.isDir end
    if a.mtime ~= b.mtime then return (a.mtime or 0) > (b.mtime or 0) end
    return tostring(a.name):lower() < tostring(b.name):lower()
  end)
  return list
end

local function displayLine(e)
  if e.isDir then
    return "[DIR] " .. e.name
  end
  return e.name .. "  ·  " .. humanSize(e.size) .. "  ·  " .. formatTime(e.mtime)
end

local function applyFilter()
  visible = {}
  local q = tostring(searchQuery or ""):lower()
  for _, e in ipairs(entries) do
    if q == "" or tostring(e.name):lower():find(q, 1, true) then
      visible[#visible + 1] = e
    end
  end
  local lines = {}
  for _, e in ipairs(visible) do
    lines[#lines + 1] = displayLine(e)
  end
  if not adapter then
    adapter = ArrayAdapter(activity, R.layout.item_check)
    fileList.setAdapter(adapter)
  else
    adapter.clear()
  end
  for _, s in ipairs(lines) do adapter.add(s) end
  adapter.notifyDataSetChanged()
  local empty = #visible == 0
  emptyView.setVisibility(empty and View.VISIBLE or View.GONE)
  fileList.setVisibility(empty and View.GONE or View.VISIBLE)
  local metaFmt = res.string.media_meta or "%d items"
  metaText.setText(string.format(metaFmt, #visible) .. " · " .. tostring(currentDir))
  pathText.setText(currentDir)
  local atRoot = currentDir == rootPathFor(currentKey)
  btnUp.setEnabled(not atRoot)
  btnUp.setAlpha(atRoot and 0.4 or 1)
end

local function navigate(dir)
  dir = tostring(dir or "")
  if dir == "" then return end
  ensureDir(dir)
  currentDir = dir
  entries = listDir(dir)
  applyFilter()
end

local function setRoot(key)
  if not ROOTS[key] then key = "all" end
  currentKey = key
  local path = ROOTS[key].path
  ensureDir(path)
  navigate(path)
end

local function goUp()
  local root = rootPathFor(currentKey)
  if currentDir == root then return end
  local parent = File(currentDir).getParent()
  if not parent or not isUnderRoot(parent) then
    navigate(root)
    return
  end
  navigate(parent)
end

local function itemActions(entry)
  local items = {}
  if not entry.isDir and isTextLike(entry.name) then
    items[#items + 1] = res.string.media_preview or "预览"
  end
  if not entry.isDir then
    items[#items + 1] = res.string.media_open_external or "外部打开"
  end
  items[#items + 1] = res.string.media_copy_path or "复制路径"
  if not entry.isDir then
    items[#items + 1] = res.string.media_share or "分享"
  end
  items[#items + 1] = res.string.delete or "删除"

  MaterialAlertDialogBuilder(activity)
    .setTitle(entry.name)
    .setItems(items, function(_, which)
      local label = items[which + 1]
      if label == (res.string.media_preview or "预览") then
        showPreview(entry.path, entry.name)
      elseif label == (res.string.media_open_external or "外部打开") then
        openExternal(entry.path)
      elseif label == (res.string.media_copy_path or "复制路径") then
        copyText(entry.path)
      elseif label == (res.string.media_share or "分享") then
        shareFile(entry.path)
      elseif label == (res.string.delete or "删除") then
        deletePath(entry.path, function() navigate(currentDir) end)
      end
    end)
    .setNegativeButton(android.R.string.cancel, nil)
    .show()
end

-- ─── UI wire ────────────────────────────────────────────
function onOptionsItemSelected(m)
  if m.getItemId() == android.R.id.home then
    if currentDir ~= rootPathFor(currentKey) then
      goUp()
    else
      activity.finish()
    end
  end
end

function onKeyDown(keyCode, event)
  if keyCode == 4 then -- BACK
    if currentDir ~= rootPathFor(currentKey) then
      goUp()
      return true
    end
  end
end

btnUp.onClick = function()
  goUp()
end

fileList.onItemClick = function(_, _, pos)
  local e = visible[pos + 1]
  if not e then return end
  if e.isDir then
    navigate(e.path)
  else
    if isTextLike(e.name) then
      showPreview(e.path, e.name)
    else
      openExternal(e.path)
    end
  end
end

fileList.onItemLongClick = function(_, _, pos)
  local e = visible[pos + 1]
  if e then itemActions(e) end
  return true
end

pcall(function()
  local watcher = TextWatcher({
    afterTextChanged = function(s)
      searchQuery = tostring(s or "")
      applyFilter()
    end,
    beforeTextChanged = function() end,
    onTextChanged = function() end,
  })
  -- MaterialTextField 代理到内部 EditText
  if searchEdit.addTextChangedListener then
    searchEdit.addTextChangedListener(watcher)
  elseif searchEdit.getEditText then
    searchEdit.getEditText().addTextChangedListener(watcher)
  end
end)

local function bindChip(chip, key)
  if not chip then return end
  pcall(function()
    chip.setOnClickListener(function()
      pcall(function() chip.setChecked(true) end)
      setRoot(key)
    end)
  end)
end

bindChip(chip_all, "all")
bindChip(chip_crash, "crash")
bindChip(chip_backups, "backups")
bindChip(chip_zip, "zip")

pcall(function()
  if chip_all then chip_all.setChecked(true) end
end)
setRoot("all")
