--- 本地 Skill 支持：只读取 SKILL.md，不执行 Skill 文件中的代码。
local _M = {}
local File = luajava.bindClass("java.io.File")
local skills = {}
local loaded = false
local MAX_SKILL_BYTES = 128 * 1024

local function trim(value)
  return tostring(value or ""):gsub("^%s*(.-)%s*$", "%1")
end

local function parseSkill(path, scope)
  local ok, raw = pcall(function() return file.readall(path) end)
  if not ok or not raw or raw == "" then return nil end
  if #raw > MAX_SKILL_BYTES then return nil end
  local name = path:match("([^/]+)/SKILL%.md$") or "skill"
  local description = ""
  local triggers = {}
  local body = raw
  if raw:sub(1, 3) == "---" then
    local stop = raw:find("\n%-%-%-", 4)
    if stop then
      local header = raw:sub(4, stop - 1)
      body = raw:sub(stop + 4):gsub("^\r?\n", "")
      for line in (header .. "\n"):gmatch("(.-)\n") do
        local key, value = line:match("^%s*([%w_%-]+)%s*:%s*(.-)%s*$")
        if key == "name" then name = trim(value)
        elseif key == "description" then description = trim(value)
        elseif key == "triggers" or key == "keywords" then
          for item in value:gmatch("[^,%s]+") do triggers[#triggers + 1] = trim(item):lower() end
        end
      end
    end
  end
  if name == "" or body == "" then return nil end
  return { name = name, description = description, triggers = triggers, body = body, path = path, scope = scope }
end

local function scanRoot(root, scope)
  local result = {}
  local base = File(root)
  if not base.exists() or not base.isDirectory() then return result end
  local entries = base.listFiles()
  if not entries then return result end
  for _, dir in ipairs(entries) do
    if dir.isDirectory() then
      local skillPath = File(dir, "SKILL.md").getAbsolutePath()
      local skill = parseSkill(skillPath, scope)
      if skill then result[#result + 1] = skill end
    end
  end
  return result
end

function _M.configure(globalRoot, projectRoot)
  local byName = {}
  local function merge(root, scope, priority)
    local scanned = scanRoot(root, scope)
    table.sort(scanned, function(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end)
    for _, skill in ipairs(scanned) do
      local key = tostring(skill.name):lower()
      if not byName[key] or priority >= byName[key]._priority then
        skill._priority = priority
        byName[key] = skill
      end
    end
  end
  merge(tostring(globalRoot or "") .. "/skills", "global", 1)
  merge(tostring(projectRoot or "") .. "/skills", "project", 2)
  merge(tostring(projectRoot or "") .. "/.agents/skills", "project", 3)
  skills = {}
  for _, skill in pairs(byName) do skills[#skills + 1] = skill end
  table.sort(skills, function(a, b)
    if a._priority ~= b._priority then return a._priority > b._priority end
    return tostring(a.name):lower() < tostring(b.name):lower()
  end)
  loaded = true
end

function _M.reload(globalRoot, projectRoot)
  _M.configure(globalRoot, projectRoot)
end

function _M.list()
  if not loaded then return {} end
  return skills
end

function _M.match(text)
  text = trim(text):lower()
  if text == "" then return nil end
  local best, score = nil, 0
  for _, skill in ipairs(skills) do
    local current = 0
    if text:find(tostring(skill.name):lower(), 1, true) then current = current + 3 end
    if skill.description ~= "" and text:find(skill.description:lower(), 1, true) then current = current + 1 end
    for _, trigger in ipairs(skill.triggers) do
      if text:find(trigger, 1, true) then current = current + 2 end
    end
    if current > score or (current == score and current > 0
        and (not best or skill._priority > (best._priority or 0))) then
      best, score = skill, current
    end
  end
  return best
end

function _M.prompt(skill)
  if not skill then return "" end
  return "\n\n# 当前启用的本地 Skill: " .. skill.name .. "\n"
    .. "来源: " .. skill.path .. "\n"
    .. "以下内容是本地 Skill 指令。仅在不违反系统提示词和用户当前要求时遵循：\n"
    .. skill.body
end

return _M
