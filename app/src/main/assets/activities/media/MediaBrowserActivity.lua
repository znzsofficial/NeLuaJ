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
import "android.text.TextWatcher"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"
import "com.androlua.adapter.LuaRecyclerAdapter"
import "com.androlua.LuaUtil"
import "android.widget.ScrollView"
import "android.widget.ImageView"
import "androidx.appcompat.widget.AppCompatEditText"
import "androidx.appcompat.widget.AppCompatTextView"
import "android.widget.LinearLayout"
import "androidx.recyclerview.widget.RecyclerView"
import "androidx.recyclerview.widget.LinearLayoutManager"

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

if not table.clear then
  function table.clear(t)
    if t then for k in pairs(t) do t[k] = nil end end
  end
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
  all = { label = res.string.media_root_all or "全部", path = mediaRoot() },
  crash = { label = res.string.media_root_crash or "崩溃日志", path = mediaRoot() .. "/crash" },
  backups = { label = res.string.media_root_backups or "代码备份", path = mediaRoot() .. "/backups" },
  zip = { label = res.string.media_root_zip or "工程 ZIP", path = luaJRoot() .. "/Backup" },
}

local SORT_TIME, SORT_NAME, SORT_SIZE = "time", "name", "size"
local currentKey = "all"
local currentDir = ROOTS.all.path
local entries = {}
local visible = {}
local adapter
local listData = {}
local searchQuery = ""
local sortMode = SORT_TIME
local selectMode = false
local selected = {} -- path -> true
-- 异步列目录世代号：丢弃过期结果，避免快速切换/连点卡死
local listGen = 0
local searchGen = 0
local listing = false

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

-- 扩展名 → 矢量图标名（与主文件列表一致）
local suffixIcon = {
  lua = "file_code", luac = "file_c_code",
  java = "file_java", kt = "file_code", kts = "file_code",
  xml = "file_json", html = "file_code", htm = "file_code",
  css = "file_code", js = "file_code",
  json = "file_json", yml = "file_json", yaml = "file_json",
  toml = "file_json", ini = "file_json", cfg = "file_json",
  properties = "file_text", prop = "file_text",
  txt = "file_text", log = "file_text", md = "file_text", csv = "file_text",
  zip = "file_zip", bak = "file_zip", alp = "file_zip", jar = "file_zip",
  apk = "file_apk", aab = "file_apk",
  dex = "file_dex",
  png = "file_img", jpg = "file_img", jpeg = "file_img", gif = "file_img",
  webp = "file_img", bmp = "file_img", svg = "file_img",
  mp3 = "file_audio", wav = "file_audio", ogg = "file_audio", flac = "file_audio",
  mp4 = "file_video", mkv = "file_video", avi = "file_video",
  sh = "file_code", bat = "file_code",
}

local cPrimary = ColorUtil.getColorPrimary()
local cSecondary = ColorUtil.getColorSecondary()
local cOnSurface = ColorUtil.getColorOnSurface()
local cOnSurfaceVar = ColorUtil.getColorOnSurfaceVariant()
local cError = ColorUtil.getColorError and ColorUtil.getColorError() or 0xFFB3261E

local iconColor = {
  folder = cPrimary,
  folder_up = cOnSurfaceVar,
  folder_doc = cOnSurfaceVar,
  file_code = cPrimary,
  file_c_code = cSecondary,
  file_json = 0xFFF9A825,
  file_text = cOnSurfaceVar,
  file_img = 0xFF4CAF50,
  file_audio = 0xFF9C27B0,
  file_video = 0xFFE91E63,
  file_zip = cOnSurfaceVar,
  file_apk = 0xFF8BC34A,
  file_java = 0xFFFF9800,
  file_dex = 0xFFFF5722,
  file = cOnSurfaceVar,
}

local iconSize = this.dpToPx(28)
local iconCache = {}

local function iconOf(name, color)
  local key = tostring(name) .. ":" .. tostring(color or "")
  local cached = iconCache[key]
  if cached then return cached end
  local d = res.drawable(name, color or iconColor[name] or cOnSurfaceVar)
  if d then d.setBounds(0, 0, iconSize, iconSize) end
  iconCache[key] = d
  return d
end

local function iconForEntry(entry)
  if entry.isDir then
    local key = string.lower(tostring(entry.name or ""))
    if key == "crash" then return iconOf("folder_doc", cError) end
    if key == "backups" or key == "backup" then return iconOf("folder", cSecondary) end
    return iconOf("folder")
  end
  local e = extOf(entry.name)
  local name = suffixIcon[e] or "file"
  return iconOf(name)
end

local function isTextLike(name)
  local e = extOf(name)
  return e == "log" or e == "txt" or e == "lua" or e == "json" or e == "md"
    or e == "xml" or e == "html" or e == "htm" or e == "css" or e == "js"
    or e == "ini" or e == "prop" or e == "properties" or e == "csv"
    or e == "kt" or e == "java" or e == "c" or e == "h" or e == "cpp"
    or e == "yml" or e == "yaml" or e == "toml" or e == "sh" or e == "bat"
end

local function mimeOf(name)
  local e = extOf(name)
  if e == "txt" or e == "log" or e == "md" or e == "csv" then return "text/plain" end
  if e == "html" or e == "htm" then return "text/html" end
  if e == "json" then return "application/json" end
  if e == "xml" then return "text/xml" end
  if e == "lua" or e == "js" or e == "css" then return "text/plain" end
  if e == "zip" then return "application/zip" end
  if e == "apk" then return "application/vnd.android.package-archive" end
  if e == "png" then return "image/png" end
  if e == "jpg" or e == "jpeg" then return "image/jpeg" end
  if e == "gif" then return "image/gif" end
  if e == "webp" then return "image/webp" end
  return "*/*"
end

local function snack(msg)
  Toast.makeText(activity, tostring(msg), Toast.LENGTH_SHORT).show()
end

local function copyText(s)
  local cm = activity.getSystemService(Context.CLIPBOARD_SERVICE)
  cm.setPrimaryClip(ClipData.newPlainText("media", tostring(s)))
  snack((res.string.copy or "复制") .. " ✓")
end

local function readFileLimited(path, maxBytes)
  maxBytes = maxBytes or 256 * 1024
  local f = io.open(path, "rb")
  if not f then return nil, "cannot open" end
  local data = f:read(maxBytes + 1)
  f:close()
  if not data then return "", false end
  local truncated = #data > maxBytes
  if truncated then data = data:sub(1, maxBytes) end
  return data:gsub("%z", ""), truncated
end

local function openExternal(path)
  this.openFile(path, function()
    snack(res.string.NoSupport or "无法打开")
  end)
end

local function shareFiles(paths)
  if not paths or #paths == 0 then
    snack(res.string.media_none_selected or "未选择文件")
    return
  end
  if #paths == 1 then
    local path = paths[1]
    local intent = Intent(Intent.ACTION_SEND)
    intent.setType(mimeOf(File(path).getName()))
    intent.putExtra(Intent.EXTRA_STREAM, activity.getUriForPath(path))
    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    intent.putExtra(Intent.EXTRA_SUBJECT, File(path).getName())
    activity.startActivity(Intent.createChooser(intent, res.string.media_share or "分享"))
    return
  end
  local intent = Intent(Intent.ACTION_SEND_MULTIPLE)
  intent.setType("*/*")
  local uris = luajava.newInstance("java.util.ArrayList")
  for _, path in ipairs(paths) do
    uris.add(activity.getUriForPath(path))
  end
  intent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
  intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
  activity.startActivity(Intent.createChooser(intent, res.string.media_share or "分享"))
end

local function shareFile(path)
  shareFiles({ path })
end

local function deletePaths(paths, onDone)
  if not paths or #paths == 0 then return end
  local msg = #paths == 1 and tostring(paths[1])
    or string.format(res.string.media_delete_n or "删除 %d 项？", #paths)
  MaterialAlertDialogBuilder(activity)
    .setTitle(res.string.delete or "删除")
    .setMessage(msg)
    .setPositiveButton(android.R.string.ok, function()
      for _, path in ipairs(paths) do
        LuaUtil.rmDir(File(path))
        selected[path] = nil
      end
      if onDone then onDone() end
    end)
    .setNegativeButton(android.R.string.cancel, nil)
    .show()
end

local function deletePath(path, onDone)
  deletePaths({ path }, onDone)
end

local function showFileInfo(entry)
  local f = File(entry.path)
  local lines = {
    "Name: " .. tostring(entry.name),
    "Path: " .. tostring(entry.path),
    "Type: " .. (entry.isDir and "directory" or (extOf(entry.name) ~= "" and extOf(entry.name) or "file")),
    "Size: " .. (entry.isDir and "—" or humanSize(entry.size)),
    "Modified: " .. formatTime(entry.mtime),
  }
  if not entry.isDir then
    lines[#lines + 1] = "Readable: " .. tostring(f.canRead())
    lines[#lines + 1] = "Writable: " .. tostring(f.canWrite())
  end
  MaterialAlertDialogBuilder(activity)
    .setTitle(res.string.media_info or "详情")
    .setMessage(table.concat(lines, "\n"))
    .setPositiveButton(res.string.media_copy_path or "复制路径", function()
      copyText(entry.path)
    end)
    .setNegativeButton(android.R.string.ok, nil)
    .show()
end

local function showPreview(path, name)
  local body, truncated = readFileLimited(path, 300 * 1024)
  if body == nil then
    openExternal(path)
    return
  end
  local title = name or File(path).getName()
  if truncated then
    title = title .. " · " .. (res.string.media_truncated or "已截断")
  end

  local binding = {}
  local content = loadlayout({
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    padding = "8dp",
    {
      AppCompatTextView,
      text = path,
      textSize = "11sp",
      textColor = ColorUtil.getColorOnSurfaceVariant(),
      maxLines = 2,
      paddingBottom = "6dp",
    },
    {
      ScrollView,
      layout_width = "match",
      layout_height = "wrap",
      {
        AppCompatEditText,
        id = "previewBody",
        layout_width = "match",
        layout_height = "wrap",
        minHeight = "220dp",
        textSize = "12sp",
        text = body,
        gravity = "start|top",
        textIsSelectable = true,
        BackgroundColor = 0,
        inputType = "textMultiLine",
      },
    },
  }, binding)

  MaterialAlertDialogBuilder(activity)
    .setTitle(title)
    .setView(content)
    .setPositiveButton(res.string.media_open_external or "外部打开", function()
      openExternal(path)
    end)
    .setNeutralButton(res.string.media_copy_content or "复制内容", function()
      local t = body
      if binding.previewBody then
        t = tostring(binding.previewBody.getText())
      end
      copyText(t)
    end)
    .setNegativeButton(res.string.media_share or "分享", function()
      shareFile(path)
    end)
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
  pcall(function()
    local f = File(dir)
    if not f.exists() or not f.isDirectory() or not f.canRead() then
      return
    end
    -- 与 MainFileList 一致：listFiles() + for-in 遍历 File[]
    local arr = f.listFiles()
    if not arr then return end
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
  end)
  return list
end

local function sortEntries(list)
  table.sort(list, function(a, b)
    if a.isDir ~= b.isDir then return a.isDir end
    if sortMode == SORT_NAME then
      return tostring(a.name):lower() < tostring(b.name):lower()
    elseif sortMode == SORT_SIZE then
      if (a.size or 0) ~= (b.size or 0) then
        return (a.size or 0) > (b.size or 0)
      end
      return tostring(a.name):lower() < tostring(b.name):lower()
    end
    if a.mtime ~= b.mtime then return (a.mtime or 0) > (b.mtime or 0) end
    return tostring(a.name):lower() < tostring(b.name):lower()
  end)
end

local function selectedCount()
  local n = 0
  for _ in pairs(selected) do n = n + 1 end
  return n
end

local function selectedPaths(filesOnly)
  local paths = {}
  for _, e in ipairs(visible) do
    if selected[e.path] and (not filesOnly or not e.isDir) then
      paths[#paths + 1] = e.path
    end
  end
  return paths
end

local function setSelectMode(on)
  selectMode = on and true or false
  if not selectMode then selected = {} end
  local vis = selectMode and View.VISIBLE or View.GONE
  btnSelectAll.setVisibility(vis)
  btnDeleteSel.setVisibility(vis)
  btnShareSel.setVisibility(vis)
  btnCopyPaths.setVisibility(vis)
  btnSelectMode.setText(selectMode
    and (res.string.media_cancel_select or "取消多选")
    or (res.string.media_select or "多选"))
end

local function sortLabel()
  if sortMode == SORT_NAME then return res.string.media_sort_name or "名称" end
  if sortMode == SORT_SIZE then return res.string.media_sort_size or "大小" end
  return res.string.media_sort_time or "时间"
end

local function updateSelectBar()
  if not selectMode then return end
  btnSelectMode.setText(string.format(
    res.string.media_selected or "已选 %d", selectedCount()))
end

local itemLayout = {
  LinearLayout,
  orientation = "horizontal",
  layout_width = "match",
  layout_height = "wrap",
  gravity = "center_vertical",
  paddingLeft = "12dp",
  paddingRight = "12dp",
  paddingTop = "8dp",
  paddingBottom = "8dp",
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
  {
    AppCompatTextView,
    id = "check",
    layout_width = "28dp",
    layout_height = "28dp",
    layout_marginStart = "4dp",
    gravity = "center",
    textSize = "18sp",
    textColor = cPrimary,
    visibility = "gone",
  },
}

-- 前向声明：ensureAdapter → onItemActivate → navigate/applyFilter → ensureAdapter
local navigate
local applyFilter
local ensureAdapter
local itemActions

local function onItemActivate(index, longPress)
  local e = visible[index]
  if not e then return true end
  -- 长按：未多选时进入多选并勾选；已多选则打开菜单
  if longPress then
    if not selectMode then
      setSelectMode(true)
      selected[e.path] = true
      applyFilter()
    else
      itemActions(e)
    end
    return true
  end
  if selectMode then
    selected[e.path] = not selected[e.path] and true or nil
    applyFilter()
    return true
  end
  if e.isDir then
    navigate(e.path)
  elseif isTextLike(e.name) then
    showPreview(e.path, e.name)
  else
    openExternal(e.path)
  end
  return true
end

function ensureAdapter()
  if adapter then return end
  adapter = LuaRecyclerAdapter(this, listData, itemLayout)
  adapter.setDataBinder(function(binding, data, holder, position)
    -- 优先用 data 字段，避免 bind 时再扫 visible 造成卡顿
    local e = visible[position + 1]
    local path = (data and data.path) or (e and e.path)
    local name = (data and data.title and data.title.text) or (e and e.name) or ""
    local isDir = e and e.isDir
    if binding.icon then
      pcall(function()
        binding.icon.setImageDrawable(e and iconForEntry(e) or nil)
      end)
    end
    if binding.title then
      binding.title.setText(name)
    end
    if binding.subtitle then
      binding.subtitle.setText((data.subtitle and data.subtitle.text) or "")
    end
    if binding.check then
      if selectMode and path then
        binding.check.setVisibility(View.VISIBLE)
        local on = selected[path]
        binding.check.setText(on and "☑" or "☐")
        binding.check.setTextColor(on and cPrimary or cOnSurfaceVar)
      else
        binding.check.setVisibility(View.GONE)
      end
    end
    if path and selectMode and selected[path] then
      holder.itemView.setBackgroundColor(0x221565C0)
    else
      holder.itemView.setBackgroundColor(0)
    end
    -- 点击：用 bindingAdapterPosition，避免复用错位；列目录中忽略点击
    local itemView = holder.itemView
    itemView.setClickable(true)
    itemView.setLongClickable(true)
    itemView.onClick = function()
      if listing then return end
      local pos = holder.getBindingAdapterPosition()
      if pos == nil or pos < 0 then return end
      onItemActivate(pos + 1, false)
    end
    itemView.onLongClick = function()
      if listing then return true end
      local pos = holder.getBindingAdapterPosition()
      if pos == nil or pos < 0 then return true end
      return onItemActivate(pos + 1, true)
    end
  end)
  fileList.setLayoutManager(LinearLayoutManager(activity, RecyclerView.VERTICAL, false))
  fileList.setHasFixedSize(true)
  pcall(function() fileList.setItemAnimator(nil) end)
  fileList.setAdapter(adapter)
end

function applyFilter()
  ensureAdapter()
  local q = tostring(searchQuery or ""):lower()
  local nextVisible = {}
  for _, e in ipairs(entries) do
    if q == "" or tostring(e.name):lower():find(q, 1, true) then
      nextVisible[#nextVisible + 1] = e
    end
  end
  sortEntries(nextVisible)

  -- 先换引用再填 listData，减少 bind 中途 visible 被清空的竞态
  visible = nextVisible
  table.clear(listData)

  local fileBytes, dirs, files = 0, 0, 0
  local dirLabel = res.string.media_type_dir or "文件夹"
  for _, e in ipairs(visible) do
    if e.isDir then
      dirs = dirs + 1
    else
      files = files + 1
      fileBytes = fileBytes + (e.size or 0)
    end
    listData[#listData + 1] = {
      title = { text = e.name },
      subtitle = {
        text = e.isDir
          and dirLabel
          or (humanSize(e.size) .. "  ·  " .. formatTime(e.mtime)),
      },
      path = e.path,
      selected = selected[e.path] and true or false,
    }
  end

  pcall(function() adapter.notifyDataSetChanged() end)
  local empty = #visible == 0
  emptyView.setVisibility(empty and View.VISIBLE or View.GONE)
  fileList.setVisibility(empty and View.INVISIBLE or View.VISIBLE)

  local meta = string.format(
    res.string.media_meta_detail or "%d 项 · %d 文件夹 · %d 文件 · %s",
    #visible, dirs, files, humanSize(fileBytes))
  if selectMode then
    meta = meta .. "  ·  " .. string.format(res.string.media_selected or "已选 %d", selectedCount())
  end
  meta = meta .. "  ·  " .. (res.string.media_sort or "排序") .. ": " .. sortLabel()
  metaText.setText(meta)
  pathText.setText(currentDir)

  local atRoot = currentDir == rootPathFor(currentKey)
  btnUp.setEnabled(not atRoot and not listing)
  btnUp.setAlpha((atRoot or listing) and 0.4 or 1)
  updateSelectBar()
  if not listing then
    swipeRefresh.setRefreshing(false)
  end
end

function navigate(dir)
  dir = tostring(dir or "")
  if dir == "" then return end
  ensureDir(dir)
  currentDir = dir
  if not selectMode then selected = {} end
  pathText.setText(currentDir)
  listGen = listGen + 1
  local gen = listGen
  listing = true
  pcall(function() swipeRefresh.setRefreshing(true) end)
  -- 与主文件列表一致：后台 listFiles，主线程刷新，避免大目录卡死主线程
  xTask(function()
    return listDir(dir)
  end, function(list)
    if gen ~= listGen then return end
    listing = false
    entries = type(list) == "table" and list or {}
    applyFilter()
    pcall(function() swipeRefresh.setRefreshing(false) end)
  end)
end

local function setRoot(key)
  if not ROOTS[key] then key = "all" end
  currentKey = key
  setSelectMode(false)
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

function itemActions(entry)
  local items, acts = {}, {}
  local function add(label, fn)
    items[#items + 1] = label
    acts[#acts + 1] = fn
  end

  if not entry.isDir and isTextLike(entry.name) then
    add(res.string.media_preview or "预览", function()
      showPreview(entry.path, entry.name)
    end)
  end
  if not entry.isDir then
    add(res.string.media_open_external or "外部打开", function()
      openExternal(entry.path)
    end)
    add(res.string.media_share or "分享", function()
      shareFile(entry.path)
    end)
  end
  add(res.string.media_copy_path or "复制路径", function()
    copyText(entry.path)
  end)
  if not entry.isDir and isTextLike(entry.name) then
    add(res.string.media_copy_content or "复制内容", function()
      local body = readFileLimited(entry.path, 512 * 1024)
      if body then copyText(body) else snack("read failed") end
    end)
  end
  add(res.string.media_info or "详情", function()
    showFileInfo(entry)
  end)
  add(res.string.media_select or "多选", function()
    setSelectMode(true)
    selected[entry.path] = true
    applyFilter()
  end)
  add(res.string.delete or "删除", function()
    deletePath(entry.path, function() navigate(currentDir) end)
  end)

  MaterialAlertDialogBuilder(activity)
    .setTitle(entry.name)
    .setItems(items, function(_, which)
      local fn = acts[which + 1]
      if fn then fn() end
    end)
    .setNegativeButton(android.R.string.cancel, nil)
    .show()
end

local function pickSort()
  local labels = {
    res.string.media_sort_time or "按时间",
    res.string.media_sort_name or "按名称",
    res.string.media_sort_size or "按大小",
  }
  local modes = { SORT_TIME, SORT_NAME, SORT_SIZE }
  MaterialAlertDialogBuilder(activity)
    .setTitle(res.string.media_sort or "排序")
    .setItems(labels, function(_, which)
      sortMode = modes[which + 1] or SORT_TIME
      applyFilter()
    end)
    .setNegativeButton(android.R.string.cancel, nil)
    .show()
end

-- ─── UI wire ────────────────────────────────────────────
function onOptionsItemSelected(m)
  if m.getItemId() == android.R.id.home then
    if selectMode then
      setSelectMode(false)
      applyFilter()
    elseif currentDir ~= rootPathFor(currentKey) then
      goUp()
    else
      activity.finish()
    end
  end
end

function onKeyDown(keyCode, event)
  if keyCode == 4 then -- BACK
    if selectMode then
      setSelectMode(false)
      applyFilter()
      return true
    end
    if currentDir ~= rootPathFor(currentKey) then
      goUp()
      return true
    end
  end
end

btnUp.onClick = function() goUp() end
btnRefresh.onClick = function() navigate(currentDir) end
btnSort.onClick = function() pickSort() end

btnSelectMode.onClick = function()
  setSelectMode(not selectMode)
  applyFilter()
end

btnSelectAll.onClick = function()
  if not selectMode then return end
  local allOn = true
  for _, e in ipairs(visible) do
    if not selected[e.path] then allOn = false break end
  end
  for _, e in ipairs(visible) do
    selected[e.path] = (not allOn) and true or nil
  end
  applyFilter()
end

btnDeleteSel.onClick = function()
  local paths = selectedPaths(false)
  if #paths == 0 then
    snack(res.string.media_none_selected or "未选择")
    return
  end
  -- 多选删除：确认后批量 rmDir，退出多选并刷新
  deletePaths(paths, function()
    setSelectMode(false)
    navigate(currentDir)
    snack(string.format(res.string.media_deleted_n or "已删除 %d 项", #paths))
  end)
end

btnShareSel.onClick = function()
  local paths = selectedPaths(true)
  if #paths == 0 then
    snack(res.string.media_none_selected or "未选择文件")
    return
  end
  shareFiles(paths)
end

btnCopyPaths.onClick = function()
  local paths = selectedPaths(false)
  if #paths == 0 then
    snack(res.string.media_none_selected or "未选择")
    return
  end
  copyText(table.concat(paths, "\n"))
end

swipeRefresh.setColorSchemeColors({ primaryColor })
swipeRefresh.setOnRefreshListener(function()
  navigate(currentDir)
end)

do
  -- 搜索防抖：避免每个字全量 sort + notify 把列表卡死
  local SEARCH_DEBOUNCE_MS = 280
  local function scheduleFilter()
    searchGen = searchGen + 1
    local gen = searchGen
    local host = searchEdit
    pcall(function()
      if searchEdit.getEditText then host = searchEdit.getEditText() end
    end)
    pcall(function()
      host.postDelayed(function()
        if gen ~= searchGen then return end
        applyFilter()
      end, SEARCH_DEBOUNCE_MS)
    end)
  end
  local watcher = TextWatcher({
    afterTextChanged = function(s)
      searchQuery = tostring(s or "")
      scheduleFilter()
    end,
    beforeTextChanged = function() end,
    onTextChanged = function() end,
  })
  if searchEdit.addTextChangedListener then
    searchEdit.addTextChangedListener(watcher)
  else
    searchEdit.getEditText().addTextChangedListener(watcher)
  end
end

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
