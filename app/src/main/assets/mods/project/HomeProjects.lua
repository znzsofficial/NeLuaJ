--- Homepage data only. Call scan/chooseDirectory on an IO dispatcher, never from a binder.
local M = {}
local File = luajava.bindClass("java.io.File")
local Util = luajava.kotlinObject("com.nekolaska.io.LuaFileUtil")
local InitReader = require "mods.project.InitReader"
local Recent = require "mods.project.RecentProjects"
local cache = {}
function M.scan(root)
  local ok, result = pcall(function()
    -- Passive inspection only. Recovery may move directories and must never race
    -- a live editor from this background scan. The foreground Retry action owns it.
    local persistence = require "mods.project.ProjectPersistence"
    local inspected, journal, detail = pcall(persistence.pendingRename)
    local migration = not inspected and { stage = "exception", error = tostring(journal) }
      or detail or journal
    local dir = File(root)
    if not dir.exists() then return { status = "error", projects = nil } end
    if not dir.isDirectory() then return { status = "root_not_directory" } end
    -- listMeta returns an empty table on an unreadable directory; listFiles distinguishes it.
    if not dir.canRead() or dir.listFiles() == nil then return { status = "error" } end
    local entries = Util.listMeta(root)
    if type(entries) ~= "table" then return { status = "error" } end
    local projects, nextCache = {}, {}
    for _, entry in ipairs(entries) do
      if entry.isDir then
        local path = root:gsub("/+$", "") .. "/" .. tostring(entry.name)
        local mtime = tonumber(Util.lastModified(path .. "/init.lua")) or 0
        local info = cache[path]
        if not info or info.mtime ~= mtime or mtime == 0 then
          local fields = InitReader.readFields(path, { "app_name", "appname", "package_name" }) or {}
          info = { appName = fields.app_name or fields.appname, pkg = fields.package_name, mtime = mtime }
        end
        nextCache[path] = info
        local appName = info.appName ~= "" and info.appName or nil
        local name = tostring(entry.name)
        projects[#projects + 1] = { path = path, name = name,
          appName = appName, pkg = info.pkg, mtime = tonumber(entry.mtime) or 0,
          sortName = (appName or name):lower(),
          searchText = table.concat({ name, appName or "", info.pkg or "" }, "\n"):lower(),
          icon = File(path .. "/icon.png").isFile() and (path .. "/icon.png") or nil }
      end
    end
    cache = nextCache
    table.sort(projects, function(a, b)
      if a.sortName == b.sortName then return a.path < b.path end
      return a.sortName < b.sortName
    end)
    local recent, recentError = Recent.list()
    if recentError then return { status = migration and "rename_pending" or "error", migration = migration, error = recentError } end
    local byPath = {}
    for _, row in ipairs(projects) do byPath[row.path] = row end
    local opened = {}
    for _, record in ipairs(recent) do
      local row = byPath[record.path]
      if row then
        opened[#opened + 1] = { path = row.path, name = row.name, appName = row.appName,
          pkg = row.pkg, openedAt = record.openedAt }
      elseif #opened < 5 and File(record.path).isDirectory() then
        opened[#opened + 1] = { path = record.path, name = record.path:match("[^/]+$"), openedAt = record.openedAt }
      end
      if #opened == 5 then break end
    end
    return { status = migration and "rename_pending" or (#projects == 0 and "empty" or "ready"),
      projects = projects, recent = opened, migration = migration }
  end)
  return ok and result or { status = "error", error = tostring(result) }
end
function M.filter(projects, query)
  query = tostring(query or ""):lower():match("^%s*(.-)%s*$")
  if query == "" then return projects end -- Treat this result as read-only.
  local out = {}
  for _, row in ipairs(projects) do
    local haystack = row.searchText or table.concat({ row.name or "", row.appName or "", row.pkg or "" }, "\n"):lower()
    if haystack:find(query, 1, true) then out[#out + 1] = row end
  end
  return out
end
function M.chooseDirectory(path)
  local ok, result = pcall(function()
    path = tostring(path or ""):match("^%s*(.-)%s*$")
    if path:sub(1, 1) ~= "/" or path:find("[\r\n]") then return nil end
    local dir = File(path)
    if not dir.isDirectory() or not dir.canRead() or dir.listFiles() == nil then return nil end
    return tostring(dir.getCanonicalPath())
  end)
  return ok and result or nil
end
return M
