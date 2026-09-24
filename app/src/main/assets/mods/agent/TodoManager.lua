--- 会话级任务计划状态：update_todos 工具、系统提示注入与 UI 渲染共用的单一数据源。
--- 列表数据本身持久化在会话记录的 todos 字段：ChatUI 的会话保存通道每次落盘都会
--- 镜像当前状态（saveHistory 合并 todos），因此本模块不持有持久化钩子。
--- 线程约定：update 在工具执行线程调用，只做规范化并把结果暂存 pending，
--- 不触碰共享状态；commitPending 由回合层在主线程的工具结果回调里调用。
local _M = {}

local MAX_ITEMS = 50
local MAX_CONTENT_CHARS = 200

local todos = nil
local pending = nil

local STATUS = { pending = true, in_progress = true, completed = true }

function _M.get()
  return todos
end

--- 字节上限截断，回退尾部被切开的 UTF-8 序列（先去续字节，再去孤立的起始字节）。
local function truncateUtf8(text, limit)
  if #text <= limit then return text end
  text = text:sub(1, limit)
  while #text > 0 do
    local b = text:byte(#text)
    if b >= 0x80 and b <= 0xBF then
      text = text:sub(1, #text - 1)
    elseif b >= 0xC0 then
      text = text:sub(1, #text - 1)
      break
    else
      break
    end
  end
  return text
end

--- 校验并规范化任务列表。返回 (list, err)；空数组合法（表示清空计划）。
local function normalizeList(list)
  if type(list) ~= "table" then return nil, "todos 必须是任务数组" end
  -- 数组部分为空但仍是对象 → 格式错误，不能当作“清空计划”成功
  if #list == 0 and next(list) ~= nil then return nil, "todos 必须是任务数组（不能是对象）" end
  local clean = {}
  for index = 1, MAX_ITEMS do
    local item = list[index]
    if item == nil then break end
    if type(item) ~= "table" then return nil, "todos[" .. index .. "] 必须是对象" end
    local content = tostring(item.content or ""):match("^%s*(.-)%s*$")
    if content == "" then return nil, "todos[" .. index .. "].content 不能为空" end
    content = truncateUtf8(content, MAX_CONTENT_CHARS)
    local status = tostring(item.status or "pending"):match("^%s*(.-)%s*$"):lower()
    if not STATUS[status] then status = "pending" end
    clean[#clean + 1] = { content = content, status = status }
  end
  return clean
end

--- 会话加载/切换时整体注入；空列表或非法数据直接清空当前状态（主线程调用）。
function _M.set(list)
  local ok, clean = pcall(normalizeList, list)
  if not ok or not clean or #clean == 0 then
    todos = nil
    return
  end
  todos = clean
end

local function renderItemLines(list)
  local lines = {}
  for _, item in ipairs(list or {}) do
    local mark = "待办"
    if item.status == "completed" then
      mark = "已完成"
    elseif item.status == "in_progress" then
      mark = "进行中"
    end
    lines[#lines + 1] = "- [" .. mark .. "] " .. item.content
  end
  return table.concat(lines, "\n")
end

--- 供系统提示动态注入；无计划时返回 nil。
function _M.renderForPrompt()
  if not todos or #todos == 0 then return nil end
  return renderItemLines(todos)
end

--- update_todos 工具入口（工具执行线程调用）：
--- 只做校验和规范化，并把新列表暂存到 pending，由回合层在主线程提交。
--- 返回 (resultText, ok)。
function _M.update(list)
  local clean, err = normalizeList(list)
  if not clean then
    return "任务计划未更新: " .. tostring(err), false
  end
  pending = clean
  local note = ""
  if type(list) == "table" and list[MAX_ITEMS + 1] ~= nil then
    note = "\n（超过 " .. MAX_ITEMS .. " 条上限，多余条目已截断）"
  end
  if #clean == 0 then
    return "任务计划已清空。" .. note, true
  end
  local done = 0
  for _, item in ipairs(clean) do
    if item.status == "completed" then done = done + 1 end
  end
  return "任务计划已更新（已完成 " .. done .. "/" .. #clean .. "）:" .. note .. "\n" .. renderItemLines(clean), true
end

--- 提交暂存的新列表（主线程调用，由 AgentTurn 的工具结果回调触发）。
--- 每次工具循环串行执行，pending 与结果一一配对，无并发覆盖。
function _M.commitPending()
  if pending == nil then return end
  todos = #pending > 0 and pending or nil
  pending = nil
end

return _M
