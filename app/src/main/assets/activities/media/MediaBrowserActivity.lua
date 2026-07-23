--- Media 浏览器：进出目录 + 打开/预览文件（无多选）
require "mods.bootstrap"

import "java.io.File"
import "android.os.Environment"
import "android.view.View"
import "android.view.WindowManager"
import "android.widget.Toast"
import "android.content.Context"
import "android.content.ClipData"
import "android.content.Intent"
import "android.graphics.drawable.ColorDrawable"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"
import "com.androlua.adapter.LuaAdapter"
import "android.widget.ImageView"
import "androidx.appcompat.widget.AppCompatTextView"
import "android.widget.LinearLayout"
import "vinx.material.textfield.MaterialTextField"

this.dynamicColor()
local res = res
local ColorUtil = this.themeUtil
local primaryColor = ColorUtil.ColorPrimary
local cOnSurface = ColorUtil.getColorOnSurface()
local cOnSurfaceVar = ColorUtil.getColorOnSurfaceVariant()

this.setContentView(loadlayout(res.layout.media_browser))
  .setTitle(res.string.media_browser)
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
  if this.getMediaDir then
    local dir = this.getMediaDir()
    if dir then return dir.getAbsolutePath() end
  end
  local dirs = activity.getExternalMediaDirs()
  if dirs and #dirs > 0 then return dirs[0].getAbsolutePath() end
  return activity.getFilesDir().getAbsolutePath()
end

local function luaJRoot()
  return Environment.getExternalStorageDirectory().getAbsolutePath() .. "/LuaJ"
end

local ROOTS = {
  all = { path = mediaRoot() },
  crash = { path = mediaRoot() .. "/crash" },
  backups = { path = mediaRoot() .. "/backups" },
  zip = { path = luaJRoot() .. "/Backup" },
}

local currentKey = "all"
local currentDir = ROOTS.all.path
local entries = {} -- { path, name, isDir, size, mtime }
local listData = {}
local adapter

local function ensureDir(path)
  local f = File(path)
  if not f.exists() then f.mkdirs() end
end

local function humanSize(n)
  n = tonumber(n) or 0
  if n < 1024 then return string.format("%d B", n) end
  if n < 1024 * 1024 then return string.format("%.1f KB", n / 1024) end
  if n < 1024 * 1024 * 1024 then return string.format("%.1f MB", n / (1024 * 1024)) end
  return string.format("%.2f GB", n / (1024 * 1024 * 1024))
end

local function formatTime(ms)
  ms = tonumber(ms) or 0
  if ms <= 0 then return "—" end
  return os.date("%Y-%m-%d %H:%M", math.floor(ms / 1000))
end

local function extOf(name)
  name = tostring(name or ""):lower()
  return name:match("%.([%w]+)$") or ""
end

local suffixIcon = {
  lua = "file_code", luac = "file_c_code",
  java = "file_code", kt = "file_code",
  xml = "file_json", json = "file_json", html = "file_code",
  txt = "file_text", log = "file_text", md = "file_text",
  png = "file_img", jpg = "file_img", jpeg = "file_img", gif = "file_img", webp = "file_img",
  zip = "file_zip", apk = "file_apk", dex = "file_dex",
  mp3 = "file_audio", wav = "file_audio",
  mp4 = "file_video",
}

local function iconForEntry(e)
  local name = "file_text"
  if e.isDir then
    name = "folder"
  else
    name = suffixIcon[extOf(e.name)] or "file_text"
  end
  local d = res.drawable(name, primaryColor)
  if d then return d end
  return res.drawable(name)
end

local TEXT_EXT = {
  lua = true, luac = true, txt = true, log = true, md = true, json = true,
  xml = true, html = true, htm = true, css = true, js = true, properties = true,
  conf = true, ini = true, csv = true, sh = true, bat = true, gradle = true,
  kts = true, java = true, kt = true, c = true, h = true, cpp = true,
}

local function isTextLike(name)
  return TEXT_EXT[extOf(name)] == true
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

local function snack(msg)
  Toast.makeText(activity, tostring(msg), Toast.LENGTH_SHORT).show()
end

local function copyText(s)
  local cm = activity.getSystemService(Context.CLIPBOARD_SERVICE)
  cm.setPrimaryClip(ClipData.newPlainText("media", tostring(s)))
  snack(res.string.copy .. " ✓")
end

local function readFileLimited(path, maxBytes)
  maxBytes = maxBytes or 256 * 1024
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read(maxBytes + 1)
  f:close()
  if not data then return "", false end
  local truncated = #data > maxBytes
  if truncated then data = data:sub(1, maxBytes) end
  return data:gsub("%z", ""), truncated
end

local function openExternal(path)
  this.openFile(path, function()
    snack(res.string.NoSupport)
  end)
end

local function showPreview(path, name)
  local body, truncated = readFileLimited(path, 300 * 1024)
  if body == nil then
    openExternal(path)
    return
  end
  local title = name or File(path).getName()
  if truncated then
    title = title .. " · " .. res.string.media_truncated
  end
  local binding = {}
  local content = loadlayout({
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    paddingLeft = "8dp",
    paddingRight = "8dp",
    paddingTop = "4dp",
    {
      AppCompatTextView,
      text = path,
      textSize = "11sp",
      textColor = cOnSurfaceVar,
      maxLines = 2,
      paddingBottom = "6dp",
    },
    {
      MaterialTextField,
      id = "previewBody",
      layout_width = "match",
      layout_height = "wrap",
      minHeight = "220dp",
      textSize = "12sp",
      text = body,
      singleLine = false,
      minLines = 10,
      gravity = "start|top",
      textIsSelectable = true,
      inputType = "textMultiLine",
      TintColor = primaryColor,
      style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
    },
  }, binding)
  MaterialAlertDialogBuilder(activity)
    .setTitle(title)
    .setView(content)
    .setPositiveButton(res.string.media_open_external, function()
      openExternal(path)
    end)
    .setNeutralButton(res.string.media_copy_content, function()
      local t = body
      if binding.previewBody then
        t = tostring(binding.previewBody.getText())
      end
      copyText(t)
    end)
    .setNegativeButton(android.R.string.cancel, nil)
    .show()
end

local function listDir(dir)
  local list = {}
  local f = File(dir)
  if not f.exists() or not f.isDirectory() or not f.canRead() then
    return list
  end
  local arr = f.listFiles()
  if not arr then return list end
  for _, child in (arr) do
    if child then
      local isDir = child.isDirectory()
      list[#list + 1] = {
        path = tostring(child.getAbsolutePath()),
        name = tostring(child.getName()),
        isDir = isDir,
        size = isDir and 0 or child.length(),
        mtime = child.lastModified(),
      }
    end
  end
  table.sort(list, function(a, b)
    if a.isDir ~= b.isDir then return a.isDir end
    if a.mtime ~= b.mtime then return (a.mtime or 0) > (b.mtime or 0) end
    return tostring(a.name):lower() < tostring(b.name):lower()
  end)
  return list
end

local itemLayout = {
  LinearLayout,
  orientation = "horizontal",
  layout_width = "match",
  layout_height = "wrap",
  gravity = "center_vertical",
  paddingLeft = "12dp",
  paddingRight = "12dp",
  paddingTop = "10dp",
  paddingBottom = "10dp",
  {
    ImageView,
    id = "icon",
    layout_width = "40dp",
    layout_height = "40dp",
    scaleType = "centerInside",
  },
  {
    LinearLayout,
    orientation = "vertical",
    layout_width = "0dp",
    layout_weight = 1,
    layout_height = "wrap",
    layout_marginStart = "10dp",
    {
      AppCompatTextView,
      id = "title",
      layout_width = "match",
      layout_height = "wrap",
      textSize = "14sp",
      textColor = cOnSurface,
      maxLines = 1,
      ellipsize = "middle",
    },
    {
      AppCompatTextView,
      id = "subtitle",
      layout_width = "match",
      layout_height = "wrap",
      textSize = "11sp",
      textColor = cOnSurfaceVar,
      maxLines = 1,
      ellipsize = "end",
      layout_marginTop = "2dp",
    },
  },
}

local function ensureAdapter()
  if adapter then return end
  adapter = LuaAdapter(activity, listData, itemLayout)
  fileList.setAdapter(adapter)
  fileList.setDividerHeight(0)
  pcall(function() fileList.setLayoutAnimation(nil) end)
  -- LuaAdapter getItemId = position+1；第 3 参 position 为 0-based，统一用 position+1
  fileList.onItemClick = function(_, _, position, _)
    local e = entries[position + 1]
    if not e then return end
    if e.isDir then
      navigate(e.path)
    elseif isTextLike(e.name) then
      showPreview(e.path, e.name)
    else
      openExternal(e.path)
    end
  end
  fileList.onItemLongClick = function(_, _, position, _)
    local e = entries[position + 1]
    if not e then return true end
    copyText(e.path)
    return true
  end
end

local function refreshList()
  ensureAdapter()
  for i = #listData, 1, -1 do
    listData[i] = nil
  end
  local dirLabel = res.string.media_type_dir
  for _, e in ipairs(entries) do
    listData[#listData + 1] = {
      icon = { src = iconForEntry(e) },
      title = { text = e.name },
      subtitle = {
        text = e.isDir
          and dirLabel
          or (humanSize(e.size) .. "  ·  " .. formatTime(e.mtime)),
      },
    }
  end
  adapter.notifyDataSetChanged()
  local empty = #entries == 0
  emptyView.setVisibility(empty and View.VISIBLE or View.GONE)
  fileList.setVisibility(empty and View.GONE or View.VISIBLE)
  pathText.setText(currentDir)
  local atRoot = currentDir == rootPathFor(currentKey)
  btnUp.setEnabled(not atRoot)
  btnUp.setAlpha(atRoot and 0.4 or 1)
end

function navigate(dir)
  dir = tostring(dir or "")
  if dir == "" then return end
  ensureDir(dir)
  currentDir = dir
  pathText.setText(currentDir)
  -- 目录一般不大：主线程 list，避免 xTask/Recycler 动画与点击竞态
  entries = listDir(dir)
  refreshList()
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
  if keyCode == 4 then
    if currentDir ~= rootPathFor(currentKey) then
      goUp()
      return true
    end
  end
end

btnUp.onClick = function() goUp() end
btnRefresh.onClick = function() navigate(currentDir) end

local function bindChip(chip, key)
  if not chip then return end
  chip.setOnClickListener(function()
    chip.setChecked(true)
    setRoot(key)
  end)
end

bindChip(chip_all, "all")
bindChip(chip_crash, "crash")
bindChip(chip_backups, "backups")
bindChip(chip_zip, "zip")

if chip_all then chip_all.setChecked(true) end
setRoot("all")
