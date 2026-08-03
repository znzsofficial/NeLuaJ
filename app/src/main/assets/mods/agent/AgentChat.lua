--- NeLuaJ+ 内置 AI 编码助手
--- 调用 OpenAI 兼容 API，支持工具调用（文件操作 + MCP）
local _M = {}

local MCPClient = require("mods.agent.MCPClient")
local ChangeSet = require("mods.agent.ChangeSet")
local AgentStorage = require("mods.agent.AgentStorage")
local ContextManager = require("mods.agent.ContextManager")
local OpenAIClient = require("mods.agent.OpenAIClient")
local ToolExecutor = require("mods.agent.ToolExecutor")
local SkillManager = require("mods.agent.SkillManager")
local Thread = luajava.bindClass("java.lang.Thread")
local activeSkill = nil

local SYSTEM_PROMPT = [[
你是 NeLuaJ+ 内置编码助手。NeLuaJ+ 是 Android Lua 运行时，用 Lua 在手机上写完整 App。
回答用中文，代码块用 ```lua 标记。

# 工作流程

接到任务后按顺序执行，不要跳步：

1. **先读再改** — 用 read_file 读取要修改的文件，用 list_dir / search_in_files 了解项目结构，绝不凭空猜测
2. **理解上下文** — NeLuaJ+ 的代码风格可能和你熟悉的 Lua 不同，先读懂现有代码再动手，尽量沿用现有写法
3. **增量修改** — 修改现有文件用 apply_patch，不要用 create_file 整文件重写
4. **验证** — 修改后有编译错误信息会自动提供给你，据此修正；纯逻辑可先用 run_lua 沙盒验证

# 输出规范

- 简洁、直接，只回答当前问题，不要寒暄、铺垫或额外总结
- 多行回复用 Markdown 组织，代码块标注语言；引用代码用 `文件:行号` 格式
- 改完代码说明改了什么，不要逐行复述代码
- 用户只问方向/方案时先给结论，不要急着动手改

# 禁止事项

- 绝不凭空猜测文件内容、项目结构或 API 用法——先读文件、先查文档
- 不要假设某个库/API 存在——先确认 NeLuaJ+ 是否提供，不确定就读对应文档
- 不要把 LuaJ++ 合法语法当错误报出来（见下方语法清单）
- 不要无 views 表调用 loadlayout（见"loadlayout 使用规范"）
- 不要一次改动超出任务范围的内容
- 创建/删除/修改/运行前必须等用户确认

# 工具使用

路径相对于当前项目根目录。创建/删除/修改/运行操作需要用户确认。

- read_file — 读取文件（修改前必读；大文件用 offset 按行续读，max 控制长度）
- read_files — 批量读取多个文件（paths 数组，一次最多 20 个），需要一起读多个文件时用它减少往返
- list_dir — 列出目录内容（recursive=true 递归，pattern 按名称过滤）
- search_in_files — 按内容搜索（类似 grep，ignore_case 可忽略大小写）
- get_env_info — 获取运行环境信息（Android/Lua 版本、项目目录、API 配置）
- run_lua — 受限沙盒运行 Lua 验证：自动语法检查，捕获 print 输出与运行时错误，有超时保护。沙盒不含 io/package/luajava/require（不能访问文件系统和 Android 接口）。先写好完整代码自检再运行。需确认
- apply_patch — 修改现有文件（优先使用）
- create_file — 创建新文件或覆盖整个文件
- append_file — 向现有文件末尾追加内容
- rename_file — 重命名或移动文件/文件夹
- create_folder / delete_file / delete_folder — 目录和文件管理

注意：delete_file/delete_folder 不允许删除项目根目录或其上级目录（会拒绝执行）。

能同时读多个文件时一起读，减少往返。

# MCP 外部工具

接入 MCP 服务器后，会额外提供 `mcp::<服务器名>::<工具名>` 形式的工具，用于调用外部系统能力（数据库、Web 搜索、业务 API 等）。任务需要外部数据/服务时优先考虑调用它们；调用前会弹窗让用户确认。

# 大文件分段读取

read_file 返回带行号的内容。文件较大时一次读不完，根据返回的"共 N 行"信息，用 offset=行号 继续读下一段，直到读完整个文件再修改。

# apply_patch 格式

用 SEARCH/REPLACE 块，可包含多块：
```
<<<<<<< SEARCH
原始代码（必须与文件内容完全一致）
=======
新代码
>>>>>>> REPLACE
```
SEARCH 部分必须在文件中唯一匹配。

# 代码风格

- 遵循目标文件既有风格（缩进、命名、写法），不要擅自换风格
- 优先复用项目已有的工具函数和模块，不要重复造轮子
- 不要加与功能无关的注释

# LuaJ++ 语法

NeLuaJ+ 使用 LuaJ++ 语法扩展，以下写法都是合法的。看到这些语法时不要标记为错误：

- 链式调用可跨行，方法后跟 `{ }` 块等价于传 table 参数
- `.属性 = 值` 是 setter 简写，等价于 `set属性(值)`
- `btn.onClick = function(v) end` 等价于 setOnClickListener
- import "java.lang.String" 导入 Java 类
- lambda a,b -> a+b
- switch/case/default/end、try/catch(e)/finally/end、defer、continue
- `!=` `!` `&&` `||` 等价于 `~=` `not` `and` `or`
- 位运算 `& | ~ >> <<`，复合赋值 `+= -= ..=`
- 三目: `b = if a 1 else 2`
- 可省略 then/do/in/function 关键字

<example>
main.lua 入口文件写法（合法，勿报错）:
```lua
activity.setContentView(res.layout.main)
  .setSupportActionBar(toolbar)
  .getSupportActionBar() {
    Title = res.string.app_title,
  }
```
</example>

<example>
res/layout/main.lua 布局文件写法（合法，勿报错）:
```lua
import "com.google.android.material.appbar.MaterialToolbar"
import "android.widget.LinearLayout"

return {
  LinearLayout,
  orientation = "vertical",
  layout_width = "match",
  layout_height = "match",
  {
    MaterialToolbar,
    id = "toolbar",
    layout_width = "match",
    layout_height = "?attr/actionBarSize",
  },
}
```
</example>

# 判断语法时的规则

- 先用 read_file 读取文件，不要凭空判断
- 上面列出的 LuaJ++ 扩展语法都是合法的，绝不能标记为错误
- 工程模板生成的代码一定是合法的
- 只有真正的语法错误（括号不匹配、缺少 end、关键字拼写错误）才需要指出

# 全局环境

- this / activity — 当前 Activity 实例
- res — 资源模块（res.string.key, res.layout.name, res.drawable(name)）
- loadlayout(table, views) — 声明式布局（见下方"loadlayout 使用规范"）
- file — 文件操作（file.save / file.readall / file.list / file.exists / file.mkdir）
- json — json.encode / json.decode
- luajava — Java 互操作（bindClass / createProxy / newInstance）
- okHttp — 异步 HTTP，okhttp — 同步 HTTP
- print — 输出到控制台

# loadlayout 使用规范（重要）

`loadlayout(布局表, views 表)`。**必须传入第二个参数 views 表**，例如：

```lua
local views = {}
loadlayout({
  LinearLayout,
  id = "root",
  {
    TextView,
    id = "tv",
  },
}, views)
-- 之后一律用 views.tv / views.root 访问控件
views.tv.text = "hello"
```

- **不带第二参数时，布局中所有带 id 的控件会被直接写入全局表 _G**（loadlayout 默认行为），造成全局污染：名字可能被覆盖、无法回收、作用域泄漏。禁止在函数/脚本里用无 views 的 loadlayout。
- 只有脚本确实希望暴露全局控件时才允许省略 views 表（例如顶层入口 main.lua 里全局限定控件名），否则一律用 `local views = {}` 显式传入。
- 每个控件的 `id` 必须是 views 表里的唯一字符串 key；重复 id 会互相覆盖。
- 布局文件（res/layout/*.lua）返回布局表本身，不需要也不能调用 loadlayout。

# IDE 内置文档

NeLuaJ+ 自带 API 文档，用 read_file 读取（路径写 `res/doc/文件名`）：
- module_loadlayout.html — 布局语法完整参考
- LuaActivity.html — Activity API
- java_interop.html — Java 互操作
- module_file.html — 文件 API
- module_okhttp.html — HTTP API
- module_res.html — 资源模块
- global_env.html — 全局环境
- layout_reference.html — 布局属性参考
- LuaJ++.html — LuaJ++ 语法扩展
- color_api.html — 颜色 API
- Coil.html — 图片加载
- LuaThemeUtil.html — 主题工具

不确定 API 用法时，先读对应文档，不要猜。
]]

function _M.getSystemPrompt()
  local custom = this.getSharedData("ai_system_prompt", "")
  if custom and custom ~= "" then
    return custom .. SkillManager.prompt(activeSkill)
  end
  return SYSTEM_PROMPT .. SkillManager.prompt(activeSkill)
end

function _M.configureSkills()
  local project = Bean and Bean.Path and Bean.Path.this_dir or activity.getLuaDir()
  local root = Bean and Bean.Path and Bean.Path.agent_root_dir or (activity.getLuaDir() .. "/agents")
  activeSkill = nil
  SkillManager.configure(root, project)
end

function _M.selectSkill(text)
  activeSkill = SkillManager.match(text)
  return activeSkill
end

function _M.getActiveSkill() return activeSkill end
function _M.clearActiveSkill() activeSkill = nil end

_M.configureSkills()

-- ─── 工具定义（OpenAI function calling 格式）──

_M.TOOLS = {
  {
    type = "function",
    ["function"] = {
      name = "create_file",
      description = "创建或覆盖文件。路径可以是绝对路径或相对于当前项目的路径。操作需要用户确认。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "文件路径，如 main.lua 或 /sdcard/test.lua" },
          content = { type = "string", description = "文件内容" },
        },
        required = { "path", "content" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "create_folder",
      description = "创建文件夹（含缺失的父目录）。操作需要用户确认。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "文件夹路径" },
        },
        required = { "path" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "delete_file",
      description = "删除文件。操作需要用户确认。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "要删除的文件路径" },
        },
        required = { "path" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "delete_folder",
      description = "删除文件夹及其所有内容。操作需要用户确认。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "要删除的文件夹路径" },
        },
        required = { "path" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "read_file",
      description = "读取文件内容。大文件按行分段读取：offset 指定从第几行开始（1 起），max 限制返回最大字符数（默认 8000）。返回带行号内容，便于后续 apply_patch。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "文件路径" },
          offset = { type = "integer", description = "起始行号（可选，默认 1）" },
          max = { type = "integer", description = "返回最大字符数（可选，默认 8000）" },
        },
        required = { "path" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "read_files",
      description = "批量读取多个文件内容（一次调用读多个文件，减少往返）。paths 为文件路径数组，最多 20 个。每个文件都按行号分页返回，用 offset/max 控制分页。总返回有上限，超出会截断。某个文件读取失败不影响其他文件。",
      parameters = {
        type = "object",
        properties = {
          paths = { type = "array", items = { type = "string" }, description = "要读取的文件路径列表" },
          offset = { type = "integer", description = "起始行号（可选，默认 1）" },
          max = { type = "integer", description = "每个文件返回最大字符数（可选，默认 4000）" },
        },
        required = { "paths" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "search_in_files",
      description = "在目录内按内容递归搜索（类似 grep）。返回 路径:行号: 内容 列表。用于快速定位某段代码/字符串出现的位置。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "搜索目录（可选，默认当前项目目录）" },
          pattern = { type = "string", description = "要搜索的文本，普通子串匹配（非正则）" },
          max = { type = "integer", description = "最大结果数（可选，默认 50）" },
          ignore_case = { type = "boolean", description = "忽略大小写（可选，默认 false）" },
        },
        required = { "pattern" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "run_lua",
      description = "在受限沙盒中运行 Lua 代码（语法检查 + 捕获 print 输出 + 超时保护，不影响项目文件）。沙盒不含 io/package/luajava/require，不能访问文件系统或 Android 接口。用于验证算法/逻辑代码能否运行并查看输出。操作需要用户确认。",
      parameters = {
        type = "object",
        properties = {
          code = { type = "string", description = "要运行的完整 Lua 代码（纯 Lua，可用 print 输出结果）" },
          timeout = { type = "integer", description = "超时毫秒数（可选，默认 3000，上限 8000）" },
        },
        required = { "code" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "apply_patch",
      description = "对现有文件应用增量修改。支持 SEARCH/REPLACE 块格式和 Unified Diff 格式。优先使用此工具而非 create_file 来修改已有文件。操作需要用户确认。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "要修改的文件路径" },
          patch = { type = "string", description = "补丁内容。推荐 SEARCH/REPLACE 块格式：每块用 <<<<<<< SEARCH / ======= / >>>>>>> REPLACE 包裹。也支持 unified diff 格式。" },
        },
        required = { "path", "patch" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "replace_in_file",
      description = "简单字符串替换：把文件中的指定文本直接替换为新文本（普通匹配，非正则）。适合小改动，比 apply_patch 更不容易失败。count 可选限制替换次数（默认替换全部）。操作需要用户确认。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "要修改的文件路径" },
          old = { type = "string", description = "要查找的原文（普通字符串，区分大小写）" },
          new = { type = "string", description = "替换后的新文本" },
          count = { type = "integer", description = "最多替换次数（可选，默认全部）" },
        },
        required = { "path", "old", "new" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "list_dir",
      description = "列出目录下的文件和文件夹。recursive=true 时递归列出子目录（自动跳过 .git/build/node_modules 等，pattern 可按名称过滤）。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "目录路径，默认当前项目目录" },
          recursive = { type = "boolean", description = "是否递归列出子目录（可选，默认 false）" },
          pattern = { type = "string", description = "按名称过滤（普通子串匹配，可选）" },
        },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "append_file",
      description = "向现有文件末尾追加内容（不覆盖已有内容）。文件不存在时创建。适合写日志、追加配置等。操作需要用户确认。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "文件路径" },
          content = { type = "string", description = "要追加的内容" },
        },
        required = { "path", "content" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "rename_file",
      description = "重命名或移动文件/文件夹（源路径 → 新路径，同目录改名或跨目录移动均可，不支持跨存储设备）。操作需要用户确认。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "原路径" },
          new_path = { type = "string", description = "新路径（目标路径）" },
        },
        required = { "path", "new_path" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "get_env_info",
      description = "获取当前运行环境信息（Android 版本、Lua 版本、项目目录、API 配置等），用于给出贴合环境的建议。",
      parameters = {
        type = "object",
      },
    },
  },
}

-- ─── 路径解析 ──

local function resolvePath(path)
  if not path or path == "" then
    return Bean and Bean.Path and Bean.Path.this_dir or activity.getLuaDir()
  end
  if path:sub(1, 1) == "/" then return path end
  local base = Bean and Bean.Path and Bean.Path.this_dir or activity.getLuaDir()
  return base .. "/" .. path
end

-- 规范化绝对路径：解析 . 和 .. 段，返回去掉冗余分隔符的路径
local function normalizePath(path)
  if not path or path == "" then return "" end
  local abs = path
  if abs:sub(1, 1) ~= "/" then
    abs = resolvePath(abs)
  end
  local parts = {}
  for seg in abs:gmatch("[^/]+") do
    if seg == ".." then
      if #parts > 0 then parts[#parts] = nil end
    elseif seg ~= "." then
      parts[#parts + 1] = seg
    end
  end
  return "/" .. table.concat(parts, "/")
end

-- 目标是否与项目根目录重合，或为项目根目录的上级目录（删它会连带删掉项目）
local function isProjectRootOrAncestor(path)
  local normalized = normalizePath(path)
  local root = normalizePath(Bean and Bean.Path and Bean.Path.this_dir or activity.getLuaDir())
  if normalized == "" or root == "" then return false end
  if normalized == root then return true end
  return root:sub(1, #normalized + 1) == normalized .. "/"
end

-- ─── 补丁解析与应用 ──

local function splitLines(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line:sub(-1) == "\r" then line = line:sub(1, -2) end
    lines[#lines + 1] = line
  end
  return lines
end

--- 应用 SEARCH/REPLACE 块
--- 格式: <<<<<<< SEARCH\nold\n=======\nnew\n>>>>>>> REPLACE

--- SEARCH 未整体命中时，找出在文件中分别存在的行，帮助模型定位差异
local function searchContextLines(original, searchContent)
  local origLines = {}
  for line in (original .. "\n"):gmatch("(.-)\n") do origLines[#origLines + 1] = line end
  local searchLines = {}
  for line in (searchContent .. "\n"):gmatch("(.-)\n") do
    local t = line:gsub("^%s*(.-)%s*$", "%1")
    if t ~= "" then searchLines[#searchLines + 1] = t end
  end
  local hints = {}
  for _, sl in ipairs(searchLines) do
    for i, ol in ipairs(origLines) do
      local ot = ol:gsub("^%s*", "")
      if ot == sl or ot:find(sl, 1, true) or sl:find(ot, 1, true) then
        hints[#hints + 1] = string.format("第 %d 行: %s", i, ol)
        break
      end
    end
  end
  if #hints > 0 then
    return "SEARCH 未整体匹配。以下行在文件中分别存在（可能被改动）:\n" .. table.concat(hints, "\n")
  end
  return ""
end

--- 行签名：去首尾空白并把连续空白折叠为单个空格，用于忽略缩进/空白差异的宽松匹配
local function lineSignature(line)
  return (line:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1"))
end

--- 计算每行起始字节位置（1 起）
local function computeLineStarts(text)
  local starts = { 1 }
  local pos = 1
  while true do
    local nl = text:find("\n", pos, true)
    if not nl then break end
    starts[#starts + 1] = nl + 1
    pos = nl + 1
  end
  return starts
end

--- 取第 i 行内容（不含行尾换行）
local function lineAt(text, starts, i)
  local p = starts[i]
  if not p then return nil end
  local e = starts[i + 1]
  if e then return text:sub(p, e - 2) end
  return text:sub(p)
end

--- 预计算每行的宽松签名
local function computeLineSigs(text, starts)
  local sigs = {}
  for i = 1, #starts do
    sigs[i] = lineSignature(lineAt(text, starts, i))
  end
  return sigs
end

--- 在 result 中按行签名找 searchLines 的宽松匹配窗口（忽略每行的缩进/空白差异），返回起止行号
local function fuzzyFindWindow(searchLines, resultSigs, resultCount)
  -- 跳过 search 首尾的空白行（上下文）
  local first, last = 1, #searchLines
  while first <= last and lineSignature(searchLines[first]) == "" do first = first + 1 end
  while last >= first and lineSignature(searchLines[last]) == "" do last = last - 1 end
  if first > last then return nil end

  local sigs = {}
  for i = first, last do sigs[#sigs + 1] = lineSignature(searchLines[i]) end

  for start = 1, resultCount do
    local matched = true
    for j = 1, #sigs do
      local ri = start + j - 1
      if ri > resultCount or resultSigs[ri] ~= sigs[j] then
        matched = false
        break
      end
    end
    if matched then
      return start, start + #sigs - 1
    end
  end
  return nil
end

--- 宽松整行替换：old 的行块在 text 中按行签名匹配后替换为 new（字面量替换失败时的回退）
local function fuzzyLineReplace(text, old, new, maxCount)
  local normalized = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  local count = 0
  while true do
    local starts = computeLineStarts(normalized)
    local l1, l2 = fuzzyFindWindow(splitLines(old), computeLineSigs(normalized, starts), #starts)
    if not l1 then break end
    local a = starts[l1]
    local b = starts[l2 + 1] and (starts[l2 + 1] - 2) or #normalized
    normalized = normalized:sub(1, a - 1) .. new .. normalized:sub(b + 1)
    count = count + 1
    if maxCount and maxCount > 0 and count >= maxCount then break end
  end
  if count == 0 then return nil, 0 end
  return normalized, count
end

local function applySearchReplace(original, patch)
  -- 统一行尾为 \n，避免 \r\n 差异导致匹配失败
  local result = original:gsub("\r\n", "\n"):gsub("\r", "\n")
  local applied = 0

  -- 逐个查找 SEARCH/REPLACE 块
  local pos = 1
  while true do
    local searchStart = patch:find("<<<<<<<%s*SEARCH", pos)
    if not searchStart then break end

    local separator = patch:find("=======", searchStart)
    if not separator then
      return nil, "缺少 ======= 分隔符"
    end

    local replaceEnd = patch:find(">>>>>>>%s*REPLACE", separator + 7)
    if not replaceEnd then
      return nil, "缺少 >>>>>>> REPLACE 结束标记"
    end

    -- 提取 SEARCH 和 REPLACE 内容（去掉首尾换行，统一 \n）
    local searchContent = patch:sub(searchStart, separator - 1)
    searchContent = searchContent:match("\n(.*)$") or ""
    searchContent = searchContent:gsub("\n$", "")
    searchContent = searchContent:gsub("\r\n", "\n"):gsub("\r", "\n")

    local replaceContent = patch:sub(separator + 7, replaceEnd - 1)
    replaceContent = replaceContent:match("^\n(.*)$") or replaceContent
    replaceContent = replaceContent:gsub("\n$", "")
    replaceContent = replaceContent:gsub("\r\n", "\n"):gsub("\r", "\n")

    -- 匹配策略：1) 精确  2) 去首尾空行的精确  3) 忽略空白差异的宽松匹配
    local foundStart, foundEnd = result:find(searchContent, 1, true)
    if not foundStart then
      local trimmed = searchContent:gsub("^%s*\n", ""):gsub("\n%s*$", "")
      if trimmed ~= "" then
        foundStart, foundEnd = result:find(trimmed, 1, true)
        if foundStart then searchContent = trimmed end
      end
    end
    if not foundStart then
      local starts = computeLineStarts(result)
      local l1, l2 = fuzzyFindWindow(splitLines(searchContent), computeLineSigs(result, starts), #starts)
      if l1 then
        foundStart = starts[l1]
        foundEnd = starts[l2 + 1] and (starts[l2 + 1] - 2) or #result
      end
    end
    if not foundStart then
      local hint = searchContextLines(result, searchContent)
      local extra = ""
      if hint ~= "" then extra = "\n\n" .. hint end
      return nil, "SEARCH 块未在文件中找到匹配:\n" .. searchContent:sub(1, 200) .. extra
    end

    result = result:sub(1, foundStart - 1) .. replaceContent .. result:sub(foundEnd + 1)
    applied = applied + 1
    pos = replaceEnd + 20
  end

  if applied == 0 then
    return nil, "未找到有效的 SEARCH/REPLACE 块"
  end

  return result, applied
end

--- 应用 Unified Diff
local function applyUnifiedDiff(original, patch)
  original = original:gsub("\r\n", "\n"):gsub("\r", "\n")
  local origLines = splitLines(original)
  local patchLines = splitLines(patch)
  local result = {}
  local origIdx = 1

  local i = 1
  while i <= #patchLines do
    local line = patchLines[i]

    -- 跳过文件头
    if line:match("^%-%-%-") or line:match("^%+%+%+") then
      i = i + 1

    -- hunk 头: @@ -old_start,old_len +new_start,new_len @@
    elseif line:match("^@@") then
      local oldStart = tonumber(line:match("@@ %-(%d+)")) or 1
      -- 输出到 hunk 开始位置
      while origIdx < oldStart and origIdx <= #origLines do
        result[#result + 1] = origLines[origIdx]
        origIdx = origIdx + 1
      end
      i = i + 1

      -- 处理 hunk body
      while i <= #patchLines do
        local hline = patchLines[i]
        if hline:match("^@@") or hline:match("^%-%-%-") or hline:match("^%+%+%+") then
          break
        end
        if hline:match("^%+") then
          result[#result + 1] = hline:sub(2)
          i = i + 1
        elseif hline:match("^%-") then
          origIdx = origIdx + 1
          i = i + 1
        elseif hline:match("^ ") then
          result[#result + 1] = origLines[origIdx] or ""
          origIdx = origIdx + 1
          i = i + 1
        elseif hline == "" then
          -- 空行可能是 context
          i = i + 1
        else
          i = i + 1
        end
      end
    else
      i = i + 1
    end
  end

  -- 复制剩余原始行
  while origIdx <= #origLines do
    result[#result + 1] = origLines[origIdx]
    origIdx = origIdx + 1
  end

  return table.concat(result, "\n"), 1
end

--- 主入口：自动判断格式并应用补丁
function _M.applyPatch(original, patch)
  -- 检测 SEARCH/REPLACE 格式
  if patch:find("<<<<<<<%s*SEARCH") then
    return applySearchReplace(original, patch)
  end

  -- 检测 Unified Diff 格式
  if patch:match("^%-%-%-") or patch:match("^@@") or patch:find("\n%-%-%-") then
    return applyUnifiedDiff(original, patch)
  end

  return nil, "无法识别补丁格式：需要 SEARCH/REPLACE 块或 Unified Diff"
end

--- 普通字符串替换（非模式匹配），替换所有出现或最多 count 次
local function plainReplace(text, old, new, maxCount)
  if old == "" then return text, 0 end
  local result = {}
  local pos = 1
  local count = 0
  while true do
    local s, e = text:find(old, pos, true)
    if not s then break end
    result[#result + 1] = text:sub(pos, s - 1)
    result[#result + 1] = new
    count = count + 1
    if maxCount and maxCount > 0 and count >= maxCount then
      result[#result + 1] = text:sub(e + 1)
      return table.concat(result), count
    end
    pos = e + 1
  end
  result[#result + 1] = text:sub(pos)
  return table.concat(result), count
end

--- 文件大小格式化
local function formatSize(n)
  if not n then return "" end
  if n < 1024 then return n .. "B" end
  if n < 1024 * 1024 then return string.format("%.1fKB", n / 1024) end
  return string.format("%.1fMB", n / 1024 / 1024)
end

--- 读取单个文件内容（含候选路径解析、大小限制、行号分页），返回 (内容字符串, 错误信息)
local function readFileContent(pathArg, offsetArg, maxArg)
  local path = resolvePath(pathArg)
  local candidates = { path }
  if pathArg and pathArg:sub(1, 1) ~= "/" then
    local luaDir = activity.getLuaDir()
    if luaDir and luaDir ~= path:sub(1, #luaDir) then
      candidates[#candidates + 1] = luaDir .. "/" .. pathArg
    end
    local ideDir = activity.getLuaDir()
    if ideDir then
      candidates[#candidates + 1] = ideDir .. "/res/doc/" .. pathArg
      candidates[#candidates + 1] = ideDir .. "/res/doc/" .. pathArg:gsub("^res/doc/", "")
    end
  end
  local ok, content = pcall(function()
    for _, candidate in ipairs(candidates) do
      if file.exists(candidate) then
        path = candidate
        local infoOk2, info2 = pcall(function() return file.info(candidate) end)
        if infoOk2 and info2 and info2.size and info2.size > 4 * 1024 * 1024 then
          return "<文件过大（" .. formatSize(info2.size) .. "），请用 offset/max 参数分段读取>"
        end
        return file.readall(candidate)
      end
    end
    return nil
  end)
  if not ok then
    return nil, "读取文件失败\n路径: " .. path .. "\n原因: " .. tostring(content)
  end
  if not content then
    return nil, "文件不存在或为空: " .. tostring(pathArg)
      .. "\n尝试路径: " .. table.concat(candidates, " | ")
  end

  -- 分页读取：按行切片，返回带行号内容
  local offset = math.max(1, tonumber(offsetArg) or 1)
  local maxChars = math.max(256, tonumber(maxArg) or 8000)
  local totalLines = 0
  local lines = {}
  for line in (content .. "\n"):gmatch("(.-)\n") do
    totalLines = totalLines + 1
    if totalLines >= offset then
      lines[#lines + 1] = string.format("%6d| %s", totalLines, line)
    end
  end

  if offset > totalLines then
    return nil, "offset 超出文件总行数（共 " .. totalLines .. " 行，offset=" .. offset .. "）\n文件: " .. path
  end

  local numbered = table.concat(lines, "\n")
  if #numbered > maxChars then
    numbered = numbered:sub(1, maxChars) .. "\n...(已截断，用 offset 继续读取)"
  end
  return numbered .. "\n---\n共 " .. totalLines .. " 行，当前显示从第 " .. offset .. " 行起"
end

-- ─── 工具执行（不含确认，确认在 ChatUI 层做）──

local function legacyExecuteTool(name, args)
  local originalName = name
  name = ToolExecutor.normalizeToolName(name, args)

  -- MCP 工具调用（mcp::服务器::工具）
  if name:match("^mcp::") then
    local ns, tool = name:sub(6):match("^([^:]+)::(.+)$")
    if not ns or not tool then
      return "MCP 工具名格式错误: " .. name
    end
    local server = MCPClient.findServer(ns)
    if not server then
      return "找不到 MCP 服务器: " .. ns
    end
    local okCall, text, err = pcall(MCPClient.callTool, server, tool, args)
    if not okCall then
      return "MCP 工具调用异常: " .. tostring(text)
    end
    if text then
      return text
    end
    return "MCP 工具调用失败: " .. tostring(err or "未知错误")
  end

  if name == "create_file" then
    local path = resolvePath(args.path)
    local ok, err = pcall(function()
      file.save(path, args.content or "")
    end)
    if ok then
      return "文件已创建: " .. path
    else
      return "创建文件失败\n路径: " .. path .. "\n原因: " .. tostring(err)
    end

  elseif name == "create_folder" then
    local path = resolvePath(args.path)
    local ok, err = pcall(function()
      file.mkdir(path)
    end)
    if ok then
      return "文件夹已创建: " .. path
    else
      return "创建文件夹失败\n路径: " .. path .. "\n原因: " .. tostring(err)
    end

  elseif name == "delete_file" then
    local path = resolvePath(args.path)
    if isProjectRootOrAncestor(path) then
      return "出于安全原因，禁止删除项目根目录或其上级目录: " .. args.path
    end
    local ok, err = pcall(function()
      local LuaFileUtil = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
      LuaFileUtil.remove(path)
    end)
    if ok then
      return "文件已删除: " .. path
    else
      return "删除文件失败\n路径: " .. path .. "\n原因: " .. tostring(err)
    end

  elseif name == "delete_folder" then
    local path = resolvePath(args.path)
    if isProjectRootOrAncestor(path) then
      return "出于安全原因，禁止删除项目根目录或其上级目录: " .. args.path
    end
    local ok, err = pcall(function()
      local LuaUtil = luajava.bindClass("com.androlua.LuaUtil")
      local File = luajava.bindClass("java.io.File")
      LuaUtil.rmDir(File(path))
    end)
    if ok then
      return "文件夹已删除: " .. path
    else
      return "删除文件夹失败\n路径: " .. path .. "\n原因: " .. tostring(err)
    end

  elseif name == "read_file" then
    local content, err = readFileContent(args.path, args.offset, args.max)
    if not content then return err end
    return content

  elseif name == "read_files" then
    local paths = args.paths
    if type(paths) == "string" then paths = { paths } end
    if type(paths) ~= "table" or #paths == 0 then
      return "read_files 需要 paths 参数（文件路径数组）"
    end
    if #paths > 20 then
      return "read_files 一次最多读取 20 个文件"
    end
    local perFileMax = math.max(256, tonumber(args.max) or 4000)
    local parts = {}
    local totalLen = 0
    local MAX_TOTAL = 60000
    local truncated = false
    for i, p in ipairs(paths) do
      if totalLen >= MAX_TOTAL then
        truncated = true
        break
      end
      local remaining = MAX_TOTAL - totalLen
      local content, err = readFileContent(p, args.offset, math.min(perFileMax, remaining))
      local block = "===== " .. tostring(p) .. " =====\n" .. (content or err)
      totalLen = totalLen + #block
      parts[#parts + 1] = block
    end
    local result = table.concat(parts, "\n\n")
    if truncated or totalLen >= MAX_TOTAL then
      result = result .. "\n\n...(批量读取结果过多，已截断，如需剩余内容请用 read_file 单独读取)"
    end
    return result

  elseif name == "list_dir" then
    local path = resolvePath(args.path)
    local recursive = args.recursive == true or args.recursive == "true" or args.recursive == 1
    local filter = args.pattern or ""
    if type(filter) == "string" then filter = filter:gsub("^%s*(.-)%s*$", "%1") end
    local ok, list = pcall(function()
      return file.list(path)
    end)
    if not ok then
      return "列出目录失败\n路径: " .. path .. "\n原因: " .. tostring(list)
    end
    if not list then
      return "目录不存在或无法访问: " .. path
    end

    -- 递归列出：跳过的目录 + 深度/数量上限
    if recursive then
      local SKIP = {
        [".git"] = true, [".svn"] = true, [".hg"] = true, [".idea"] = true,
        [".gradle"] = true, ["build"] = true, ["dist"] = true, ["target"] = true,
        ["node_modules"] = true, ["bin"] = true, ["obj"] = true, [".cxx"] = true,
      }
      local out = {}
      local count = 0
      local MAX_DEPTH = 6
      local MAX_ITEMS = 500
      local function walk(dir, depth, prefix)
        if count >= MAX_ITEMS or depth > MAX_DEPTH then return end
        local okw, entries = pcall(function() return file.list(dir) end)
        if not okw or not entries then return end
        local names = {}
        for _, name in ipairs(entries) do
          if name ~= "." and name ~= ".." then names[#names + 1] = name end
        end
        table.sort(names)
        for _, name in ipairs(names) do
          if count >= MAX_ITEMS then return end
          local full = dir .. "/" .. name
          local typeOk, ftype = pcall(function() return file.type(full) end)
          if typeOk and ftype == "dir" then
            local line = prefix .. name .. "/"
            if filter == "" or line:find(filter, 1, true) or name:find(filter, 1, true) then
              out[#out + 1] = line
              count = count + 1
            end
            if not SKIP[name] then
              walk(full, depth + 1, line)
            end
          elseif typeOk and ftype == "file" then
            local line = prefix .. name
            if filter == "" or line:find(filter, 1, true) or name:find(filter, 1, true) then
              out[#out + 1] = line
              count = count + 1
            end
          end
        end
      end
      walk(path, 0, "")
      if count == 0 then
        return "目录为空或没有匹配项: " .. path
      end
      local result = table.concat(out, "\n")
      if #result > 8000 then
        result = result:sub(1, 8000) .. "\n...(结果过多，已截断)"
      end
      return "递归列表（" .. count .. " 项）:\n" .. result
    end

    local dirs, files = {}, {}
    for i, name in ipairs(list) do
      if name ~= "." and name ~= ".." then
        local full = path .. "/" .. name
        local typeOk, ftype = pcall(function() return file.type(full) end)
        if typeOk and ftype == "dir" then
          dirs[#dirs + 1] = name .. "/"
        else
          local size = ""
          local infoOk, info = pcall(function() return file.info(full) end)
          if infoOk and info and info.size then
            size = "  " .. formatSize(info.size)
          end
          files[#files + 1] = name .. size
        end
      end
    end
    local out = {}
    if #dirs > 0 then
      out[#out + 1] = "目录 (" .. #dirs .. "):"
      for _, d in ipairs(dirs) do out[#out + 1] = "  " .. d end
    end
    if #files > 0 then
      out[#out + 1] = "文件 (" .. #files .. "):"
      for _, f in ipairs(files) do out[#out + 1] = "  " .. f end
    end
    if #out == 0 then
      return "目录为空: " .. path
    end
    return table.concat(out, "\n")

  elseif name == "search_in_files" then
    local root = resolvePath(args.path or "")
    local pattern = args.pattern or ""
    local maxResults = math.max(1, tonumber(args.max) or 50)
    local ignoreCase = args.ignore_case == true or args.ignore_case == "true" or args.ignore_case == 1
    if pattern == "" then
      return "search_in_files 需要 pattern 参数"
    end
    local matchPattern = pattern
    if ignoreCase then matchPattern = pattern:lower() end

    -- 跳过的目录
    local SKIP_DIRS = {
      [".git"] = true, [".svn"] = true, [".hg"] = true, [".idea"] = true,
      [".gradle"] = true, ["build"] = true, ["dist"] = true, ["target"] = true,
      ["node_modules"] = true, ["bin"] = true, ["obj"] = true, [".cxx"] = true,
    }
    local results = {}
    local scanned = 0
    local MAX_SCAN = 2000
    local MAX_DEPTH = 8
    local MAX_FILE = 1024 * 1024

    local function walk(dir, depth)
      if #results >= maxResults or scanned >= MAX_SCAN or depth > MAX_DEPTH then return end
      local ok, entries = pcall(function() return file.list(dir) end)
      if not ok or not entries then return end
      for _, name in ipairs(entries) do
        if #results >= maxResults or scanned >= MAX_SCAN then return end
        if name ~= "." and name ~= ".." then
          local full = dir .. "/" .. name
          local typeOk, ftype = pcall(function() return file.type(full) end)
          if typeOk and ftype == "dir" then
            if not SKIP_DIRS[name] then
              walk(full, depth + 1)
            end
          elseif typeOk and ftype == "file" then
            scanned = scanned + 1
            local infoOk, info = pcall(function() return file.info(full) end)
            if infoOk and info and info.size and info.size <= MAX_FILE then
              local okr, content = pcall(function() return file.readall(full) end)
              if okr and content and not content:find("\0", 1, true) then
                local lineno = 0
                for line in (content .. "\n"):gmatch("(.-)\n") do
                  lineno = lineno + 1
                  local haystack = line
                  if ignoreCase then haystack = haystack:lower() end
                  if haystack:find(matchPattern, 1, true) then
                    results[#results + 1] = full .. ":" .. lineno .. ": " .. line
                    if #results >= maxResults then return end
                  end
                end
              end
            end
          end
        end
      end
    end

    walk(root, 0)
    if #results == 0 then
      return "未找到匹配「" .. pattern .. "」的文件\n目录: " .. root
        .. "\n已扫描 " .. scanned .. " 个文件"
    end
    local out = table.concat(results, "\n")
    if #out > 8000 then
      out = out:sub(1, 8000) .. "\n...(结果过多，已截断)"
    end
    return "搜索「" .. pattern .. "」共 " .. #results .. " 处:\n" .. out

  elseif name == "run_lua" then
    local code = args.code or args.content or ""
    if code == "" then
      return "run_lua 需要 code 参数"
    end
    -- 加载沙盒（executeTool 无 pcall 包裹，异常会卡住 UI，这里统一兜底）
    local okBind, LuaSandbox = pcall(function()
      return luajava.bindClass("com.androlua.LuaSandbox")
    end)
    if not okBind then
      return "沙盒加载失败: " .. tostring(LuaSandbox)
    end
    -- 语法预检：纯编译，无副作用
    local okSyntax, syntaxErr = pcall(function()
      return LuaSandbox.checkSyntax(code)
    end)
    if not okSyntax then
      return "语法检查异常: " .. tostring(syntaxErr)
    end
    if syntaxErr then
      return "Lua 语法错误:\n" .. tostring(syntaxErr)
    end
    -- 受限沙盒原地运行：捕获 print 输出与运行时错误，超时保护
    -- （同步阻塞主线程，默认 3s、上限 8s，避免长卡顿触发 ANR）
    local timeout = math.max(1000, math.min(8000, tonumber(args.timeout) or 3000))
    local okRun, res = pcall(function()
      return LuaSandbox.run(code, timeout)
    end)
    if not okRun then
      return "沙盒运行异常: " .. tostring(res)
    end
    local elapsed = tostring(res.elapsed or 0) .. "ms"
    local output = tostring(res.output or "")
    if res.ok then
      if output ~= "" then
        return "运行成功（耗时 " .. elapsed .. "）:\n" .. output
      end
      return "运行成功，无输出（耗时 " .. elapsed .. "）"
    end
    local err = tostring(res.error or "运行失败")
    if output ~= "" then
      err = err .. "\n--- 部分输出 ---\n" .. output
    end
    return "运行失败（耗时 " .. elapsed .. "）:\n" .. err

  elseif name == "apply_patch" then
    local path = resolvePath(args.path)
    local patch = args.patch or ""
    local original = ""
    local readOk, readResult = pcall(function() return file.readall(path) end)
    if not readOk then
      return "读取文件失败\n路径: " .. path .. "\n原因: " .. tostring(readResult)
    end
    if not readResult then
      return "文件不存在或为空: " .. path
    end
    original = readResult

    local newContent, countOrErr = _M.applyPatch(original, patch)
    if not newContent then
      return "补丁应用失败\n文件: " .. path .. "\n原因: " .. tostring(countOrErr)
    end

    local writeOk, writeErr = pcall(function()
      file.save(path, newContent)
    end)
    if not writeOk then
      return "补丁写入失败\n文件: " .. path .. "\n原因: " .. tostring(writeErr)
    end
    local count = type(countOrErr) == "number" and countOrErr or 1
    return "补丁已应用（" .. count .. " 处修改）: " .. path

  elseif name == "replace_in_file" then
    local path = resolvePath(args.path)
    local old = args.old or ""
    local new = args.new or ""
    if old == "" then
      return "replace_in_file 需要 old 参数（要替换的文本）"
    end
    local readOk, original = pcall(function() return file.readall(path) end)
    if not readOk then
      return "读取文件失败\n路径: " .. path .. "\n原因: " .. tostring(original)
    end
    if not original then
      return "文件不存在或为空: " .. path
    end
    local maxCount = tonumber(args.count) or 0
    local newContent, replaced = plainReplace(original, old, new, maxCount)
    if replaced == 0 then
      -- 字面量未命中时回退到忽略空白差异的整行替换
      local okFuzzy, cnt = fuzzyLineReplace(original, old, new, maxCount)
      if okFuzzy then newContent, replaced = okFuzzy, cnt end
    end
    if replaced == 0 then
      return "未找到要替换的文本: " .. old
    end
    local writeOk, writeErr = pcall(function()
      file.save(path, newContent)
    end)
    if not writeOk then
      return "替换写入失败\n文件: " .. path .. "\n原因: " .. tostring(writeErr)
    end
    return "已替换 " .. replaced .. " 处: " .. path

  elseif name == "append_file" then
    local path = resolvePath(args.path)
    if not args.path or args.path == "" then
      return "append_file 需要 path 参数"
    end
    local ok, err = pcall(function()
      local File = luajava.bindClass("java.io.File")
      local FileWriter = luajava.bindClass("java.io.FileWriter")
      local fw = FileWriter(File(path), true)
      fw.write(tostring(args.content or ""))
      fw.flush()
      fw.close()
    end)
    if ok then
      return "已追加到文件: " .. path
    else
      return "追加失败\n路径: " .. path .. "\n原因: " .. tostring(err)
    end

  elseif name == "rename_file" then
    local src = resolvePath(args.path)
    local dst = resolvePath(args.new_path)
    if not args.path or args.path == "" then
      return "rename_file 需要 path 参数（原路径）"
    end
    if not args.new_path or args.new_path == "" then
      return "rename_file 需要 new_path 参数（新路径）"
    end
    if isProjectRootOrAncestor(src) then
      return "出于安全原因，禁止移动项目根目录或其上级目录"
    end
    local ok, err = pcall(function()
      local File = luajava.bindClass("java.io.File")
      local f = File(src)
      if not f.exists() then
        error("原路径不存在: " .. src)
      end
      if not f.renameTo(File(dst)) then
        error("重命名/移动失败（目标已存在或跨存储设备）")
      end
    end)
    if ok then
      return "已重命名/移动: " .. src .. " → " .. dst
    else
      return "重命名失败\n原路径: " .. src .. "\n目标: " .. dst .. "\n原因: " .. tostring(err)
    end

  elseif name == "get_env_info" then
    local out = {}
    local okEnv, resEnv = pcall(function()
      local Build = luajava.bindClass("android.os.Build")
      local release, sdk = "未知", "未知"
      pcall(function()
        local v = luajava.bindClass("android.os.Build$VERSION")
        release = tostring(v.RELEASE or "未知")
        sdk = tostring(v.SDK_INT or "未知")
      end)
      out[#out + 1] = "Android: " .. release .. " (API " .. sdk .. ")"
      out[#out + 1] = "设备: " .. tostring(Build.MANUFACTURER) .. " " .. tostring(Build.MODEL)
      out[#out + 1] = "Lua: " .. tostring(_VERSION)
      out[#out + 1] = "项目根目录: " .. tostring(resolvePath(""))
      local luaDir = activity.getLuaDir()
      out[#out + 1] = "Lua 目录: " .. tostring(luaDir or "")
      out[#out + 1] = "API URL: " .. tostring(_M.getApiUrl())
      out[#out + 1] = "当前模型: " .. tostring(_M.getModel())
    end)
    if not okEnv then
      return "获取环境信息失败: " .. tostring(resEnv)
    end
    return table.concat(out, "\n")
  end

  return "未知工具: " .. tostring(originalName) .. "（规范化后: " .. tostring(name) .. "）"
end

local function changeSetFileType(path)
  local ok, kind = pcall(function() return file.type(path) end)
  return ok and kind or nil
end

local function changeSetListFiles(path)
  local out = {}
  local ok, entries = pcall(function() return file.list(path) end)
  if not ok or type(entries) ~= "table" then return out end
  for _, name in ipairs(entries) do
    if name ~= "." and name ~= ".." then out[#out + 1] = path .. "/" .. name end
  end
  return out
end

local function changeSetRemove(path)
  local kind = changeSetFileType(path)
  if not kind then return true end
  local ok, err = pcall(function()
    if kind == "dir" then
      local LuaUtil = luajava.bindClass("com.androlua.LuaUtil")
      LuaUtil.rmDir(luajava.bindClass("java.io.File")(path))
    else
      luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE.remove(path)
    end
  end)
  return ok, err
end

AgentStorage.configure(
  Bean and Bean.Path and Bean.Path.this_dir or activity.getLuaDir(),
  Bean and Bean.Path and Bean.Path.agent_root_dir
)

function _M.syncAgentProjectScope()
  local path = Bean and Bean.Path and Bean.Path.this_dir or activity.getLuaDir()
  AgentStorage.configureCurrent(path, Bean and Bean.Path and Bean.Path.agent_root_dir)
  _M.configureSkills()
  ChangeSet.configure({
    resolve = resolvePath,
    type = changeSetFileType,
    listFiles = changeSetListFiles,
    read = function(p) local ok, c = pcall(function() return file.readall(p) end); return ok and c or nil end,
    write = function(p, c) return pcall(function() file.save(p, c or "") end) end,
    ensureParent = function(p) pcall(function() local F = luajava.bindClass("java.io.File"); local parent = F(p).getParentFile(); if parent then parent.mkdirs() end end) end,
    loadState = function()
      local stored = AgentStorage.read("changesets.json")
      if stored and stored ~= "" then return stored end
      local legacy = this.getSharedData("ai_changesets", "")
      if legacy ~= "" and AgentStorage.write("changesets.json", legacy) then this.setSharedData("ai_changesets", "") end
      return legacy
    end,
    saveState = function(encoded)
      if AgentStorage.write("changesets.json", encoded or "") then this.setSharedData("ai_changesets", "") end
    end,
    scope = function() return normalizePath(Bean and Bean.Path and Bean.Path.this_dir or activity.getLuaDir()) end,
    mkdir = function(p) return pcall(function() file.mkdir(p) end) end,
    remove = changeSetRemove,
    isTracked = function(n) return n == "create_file" or n == "create_folder" or n == "delete_file" or n == "delete_folder" or n == "apply_patch" or n == "replace_in_file" or n == "append_file" or n == "rename_file" end,
    resultSucceeded = function(r) local t = tostring(r or ""); return not t:find("失败", 1, true) and not t:find("异常", 1, true) and not t:find("拒绝", 1, true) and not t:find("禁止", 1, true) end,
  })
end

-- ─── 判断工具是否需要用户确认 ──

-- ─── 配置读写 ──

local function getApiKey()
  return this.getSharedData("ai_api_key", "")
end

local function getApiUrl()
  return this.getSharedData("ai_api_url", "https://api.deepseek.com/v1")
end

local function getModel()
  return this.getSharedData("ai_model", "deepseek-v4-flash")
end

local function getTemperature()
  local v = tonumber(this.getSharedData("ai_temperature", "0.7"))
  if not v then return 0.7 end
  return math.max(0, math.min(2, v))
end

-- 模型上下文长度（context window），用于历史消息截断预算
local function getContextLength()
  local v = tonumber(this.getSharedData("ai_context_length", "30000"))
  if not v then return 30000 end
  return math.floor(v)
end

local function getMaxTokens()
  local v = tonumber(this.getSharedData("ai_max_tokens", "4096"))
  if not v then v = 4096 end
  v = math.max(256, math.min(32768, math.floor(v)))
  -- 输出不能超过上下文窗口（至少留 500 token 余量）
  local ctx = getContextLength()
  return math.min(v, math.max(256, ctx - 500))
end

-- 失败自动重试次数（0 = 不重试）
local function getRetryCount()
  local v = tonumber(this.getSharedData("ai_retry_count", "2"))
  if not v then return 2 end
  if v < 0 then return 0 end
  return math.floor(v)
end

-- 自签名证书开关：开启时用忽略证书校验的客户端
local function getHttpClient()
  if this.getSharedData("ai_allow_selfsigned", "0") == "1" then
    local ok, client = pcall(function() return okHttp.unsafe end)
    if ok and client then return client end
  end
  return okHttp
end

function _M.hasApiKey()
  return getApiKey() ~= ""
end

function _M.setApiKey(key) this.setSharedData("ai_api_key", key) end
function _M.setApiUrl(url) this.setSharedData("ai_api_url", url) end
function _M.setModel(model) this.setSharedData("ai_model", model) end
function _M.getApiKey() return getApiKey() end
function _M.getApiUrl() return getApiUrl() end
function _M.getModel() return getModel() end

-- ─── 多模型管理 ──

local MODELS_KEY = "ai_models"
local MODEL_INDEX_KEY = "ai_model_index"
local modelsCache = nil

function _M.loadModels()
  if modelsCache then return modelsCache end
  local raw = this.getSharedData(MODELS_KEY, "")
  if raw == "" then
    -- 迁移旧版单模型到多模型列表
    local key = getApiKey()
    if key ~= "" then
      modelsCache = { { name = _M.getModel(), url = getApiUrl(), key = key, model = _M.getModel() } }
      return modelsCache
    end
    modelsCache = {}
    return modelsCache
  end
  local ok, decoded = pcall(json.decode, raw)
  if ok and type(decoded) == "table" then
    modelsCache = decoded
    return modelsCache
  end
  modelsCache = {}
  return modelsCache
end

function _M.saveModels(models)
  modelsCache = models
  local ok, encoded = pcall(json.encode, models)
  if ok then this.setSharedData(MODELS_KEY, encoded) end
end

function _M.getCurrentModelIndex()
  local idx = tonumber(this.getSharedData(MODEL_INDEX_KEY, "0")) or 0
  local models = _M.loadModels()
  if idx < 1 or idx > #models then idx = 1 end
  if #models == 0 then idx = 0 end
  return idx
end

function _M.setCurrentModel(index)
  this.setSharedData(MODEL_INDEX_KEY, tostring(index))
  local models = _M.loadModels()
  if index >= 1 and index <= #models then
    local m = models[index]
    _M.setApiKey(m.key)
    _M.setApiUrl(m.url)
    _M.setModel(m.model)
  end
end

function _M.getCurrentModelName()
  local models = _M.loadModels()
  local idx = _M.getCurrentModelIndex()
  if idx >= 1 and idx <= #models then
    return models[idx].name
  end
  return _M.getModel()
end

function _M.addModel(name, url, key, model)
  local models = _M.loadModels()
  models[#models + 1] = { name = name, url = url, key = key, model = model }
  _M.saveModels(models)
  return #models
end

function _M.updateModel(index, name, url, key, model)
  local models = _M.loadModels()
  if index >= 1 and index <= #models then
    models[index] = { name = name, url = url, key = key, model = model }
    _M.saveModels(models)
    return true
  end
  return false
end

function _M.removeModel(index)
  local models = _M.loadModels()
  if index >= 1 and index <= #models then
    local current = _M.getCurrentModelIndex()
    table.remove(models, index)
    _M.saveModels(models)
    if #models == 0 then
      _M.setCurrentModel(0)
    elseif current > index then
      _M.setCurrentModel(current - 1)
    elseif current == index then
      _M.setCurrentModel(math.min(current, #models))
    elseif current > #models then
      _M.setCurrentModel(#models)
    end
    return true
  end
  return false
end

-- 初始化：确保当前模型设置生效
local function initCurrentModel()
  local models = _M.loadModels()
  if #models > 0 then
    local idx = _M.getCurrentModelIndex()
    if idx >= 1 and idx <= #models then
      local m = models[idx]
      _M.setApiKey(m.key)
      _M.setApiUrl(m.url)
      _M.setModel(m.model)
    end
  end
end
initCurrentModel()

-- ─── 多会话管理 ──

local CONV_KEY = "ai_conversations"
local CONV_IDX_KEY = "ai_current_conv"
local convsCache = nil
local convSeq = 0

function _M.loadConversations()
  if convsCache then return convsCache end
  local raw = this.getSharedData(CONV_KEY, "")
  if raw == "" then
    convsCache = {}
    return convsCache
  end
  local ok, decoded = pcall(json.decode, raw)
  if ok and type(decoded) == "table" then
    local projectPath = normalizePath(Bean and Bean.Path and Bean.Path.this_dir or activity.getLuaDir())
    local migrated = false
    for _, conv in ipairs(decoded) do
      if type(conv) == "table" and not conv.projectPath then
        conv.projectPath = projectPath
        migrated = true
      end
    end
    convsCache = decoded
    if migrated then
      local encodedOk, encoded = pcall(json.encode, convsCache)
      if encodedOk then this.setSharedData(CONV_KEY, encoded) end
    end
    return convsCache
  end
  convsCache = {}
  return convsCache
end

function _M.saveConversations(convs)
  convsCache = convs
  local ok, encoded = pcall(json.encode, convs)
  if ok then this.setSharedData(CONV_KEY, encoded) end
end

function _M.getCurrentConvIndex()
  local convs = _M.loadConversations()
  if #convs == 0 then return 0 end
  local projectPath = normalizePath(Bean and Bean.Path and Bean.Path.this_dir or activity.getLuaDir())
  local stored = tonumber(this.getSharedData(CONV_IDX_KEY, "0")) or 0
  if stored >= 1 and stored <= #convs and convs[stored].projectPath == projectPath then
    return stored
  end
  for index = #convs, 1, -1 do
    if convs[index].projectPath == projectPath then
      this.setSharedData(CONV_IDX_KEY, tostring(index))
      return index
    end
  end
  return 0
end

function _M.setCurrentConv(index)
  this.setSharedData(CONV_IDX_KEY, tostring(index))
end

function _M.getCurrentConv()
  local convs = _M.loadConversations()
  local idx = _M.getCurrentConvIndex()
  if idx >= 1 and idx <= #convs then
    return convs[idx], idx
  end
  return nil, 0
end

function _M.getCurrentProjectPath()
  return normalizePath(Bean and Bean.Path and Bean.Path.this_dir or activity.getLuaDir())
end

function _M.createConversation(name)
  local convs = _M.loadConversations()
  convSeq = convSeq + 1
  local id = "conv_" .. tostring(os.time()) .. "_" .. tostring(convSeq)
  local conv = {
    id = id,
    name = name or "",
    projectPath = normalizePath(Bean and Bean.Path and Bean.Path.this_dir or activity.getLuaDir()),
    messages = {},
    createdAt = os.date("%m-%d %H:%M"),
  }
  convs[#convs + 1] = conv
  _M.saveConversations(convs)
  _M.setCurrentConv(#convs)
  return conv, #convs
end

function _M.saveCurrentConv(messages)
  local convs = _M.loadConversations()
  local idx = _M.getCurrentConvIndex()
  if idx >= 1 and idx <= #convs then
    -- 持久化全量历史，发送时才按 token 预算裁剪
    convs[idx].messages = messages
    convs[idx].projectPath = convs[idx].projectPath or normalizePath(Bean and Bean.Path and Bean.Path.this_dir or activity.getLuaDir())
    if convs[idx].name == "" or convs[idx].name == "新对话" then
      for _, m in ipairs(messages) do
        if m.role == "user" and m.content and m.content ~= "" then
          convs[idx].name = m.content:gsub("\n", " "):sub(1, 30)
          break
        end
      end
    end
    _M.saveConversations(convs)
  end
end

function _M.deleteConversation(index)
  local convs = _M.loadConversations()
  if index >= 1 and index <= #convs then
    table.remove(convs, index)
    _M.saveConversations(convs)
    local current = _M.getCurrentConvIndex()
    if current > #convs then
      _M.setCurrentConv(math.max(1, #convs))
    end
    return true
  end
  return false
end

function _M.renameConversation(index, name)
  local convs = _M.loadConversations()
  if index >= 1 and index <= #convs and name ~= "" then
    convs[index].name = name
    _M.saveConversations(convs)
    return true
  end
  return false
end

-- ─── 构建编辑器上下文 ──

function _M.buildContext()
  local parts = {}

  local this_file = Bean and Bean.Path and Bean.Path.this_file
  if this_file and this_file ~= "" then
    table.insert(parts, "当前文件: " .. this_file)
  end

  local this_dir = Bean and Bean.Path and Bean.Path.this_dir
  if this_dir and this_dir ~= "" then
    table.insert(parts, "项目路径: " .. this_dir)
  end

  if mLuaEditor and mLuaEditor.getVisibility and mLuaEditor.getVisibility() == 0 then
    local code = tostring(mLuaEditor.getText() or "")
    if #code > 0 then
      local selStart = mLuaEditor.getSelectionStart()
      local selEnd = mLuaEditor.getSelectionEnd()
      if selStart ~= selEnd then
        local sel = code:sub(selStart + 1, selEnd)
        table.insert(parts, "选中代码:\n```lua\n" .. sel .. "\n```")
      end
      if #code <= 5000 then
        table.insert(parts, "文件内容:\n```lua\n" .. code .. "\n```")
      else
        table.insert(parts, "文件内容(前5000字符):\n```lua\n" .. code:sub(1, 5000) .. "\n```")
      end
    end
  end

  if error_Text and error_Text.getVisibility and error_Text.getVisibility() == 0 then
    local err = tostring(error_Text.getText() or "")
    if err ~= "" then
      table.insert(parts, "编译错误: " .. err)
    end
  end

  -- 项目文件列表
  if this_dir and this_dir ~= "" then
    local ok, list = pcall(function() return file.list(this_dir) end)
    if ok and list then
      local names = {}
      for _, name in ipairs(list) do
        if name ~= "." and name ~= ".." then
          names[#names + 1] = name
        end
      end
      if #names > 0 then
        table.insert(parts, "项目文件列表:\n" .. table.concat(names, "\n"))
      end
    end
  end

  return table.concat(parts, "\n\n")
end

-- ─── 上下文构建兼容层 ──
-- 实际实现位于 ContextManager.lua，公开入口在文件末尾转发。

-- ─── 连接测试 ──

--[[ Legacy API client implementation removed from the runtime.

--- @param onResult function(ok: boolean, msg: string)
local function legacyTestConnection(onResult)
  local key = getApiKey()
  if key == "" then
    if onResult then onResult(false, "请先设置 API Key") end
    return
  end
  local baseUrl = getApiUrl()
  if not baseUrl:match("/chat/completions$") then
    baseUrl = baseUrl:gsub("/+$", "") .. "/chat/completions"
  end
  local bodyStr = json.encode({
    model = getModel(),
    messages = { { role = "user", content = "ping" } },
    max_tokens = 1,
    stream = false,
  })
  local headers = {
    ["Authorization"] = "Bearer " .. key,
    ["Content-Type"] = "application/json",
  }
  getHttpClient().postJson(baseUrl, bodyStr, headers, function(code, respBody)
    local codeNum = tonumber(tostring(code or ""))
    if codeNum and codeNum == 200 then
      if onResult then onResult(true, "连接成功，模型 " .. getModel()) end
      return
    end
    local msg = "HTTP " .. tostring(codeNum or code or "?")
    local b = tostring(respBody or "")
    local ok2, decoded = pcall(json.decode, b)
    if ok2 and decoded then
      local e = decoded.error or {}
      local em = ""
      if type(e) == "table" then
        em = e.message or e.type or ""
      else
        em = tostring(e)
      end
      if em ~= "" then msg = msg .. ": " .. em end
    elseif b ~= "" and #b < 500 then
      msg = msg .. ": " .. b
    end
    if onResult then onResult(false, msg) end
  end)
end

-- ─── 流式发送（支持 tool_calls）──
--- @param messages table 消息列表
--- @param callbacks table { onChunk=fn, onToolCalls=fn, onDone=fn, onError=fn }
local function cloneValue(value)
  if type(value) ~= "table" then return value end
  local copy = {}
  for key, item in pairs(value) do
    copy[key] = cloneValue(item)
  end
  return copy
end

local function legacySendStream(messages, callbacks)
  callbacks = callbacks or {}
  local finished = false
  local function finish(callback, ...)
    if finished then return end
    finished = true
    if callback then callback(...) end
  end
  local key = getApiKey()
  if key == "" then
    finish(callbacks.onError, "请先设置 API Key")
    return
  end

  -- 构建完整 API URL
  local baseUrl = getApiUrl()
  if not baseUrl:match("/chat/completions$") then
    baseUrl = baseUrl:gsub("/+$", "") .. "/chat/completions"
  end

  -- 检测模型是否支持 tools
  local modelName = getModel():lower()
  local supportsTools = not callbacks.disableTools and not modelName:match("reasoner") and not modelName:match("r1%-") and not modelName:match("^o1") and not modelName:match("^o3")

  -- 不支持 tools 的模型：过滤掉 tool_calls 和 tool 消息
  local sendMessages = cloneValue(messages)
  if not supportsTools then
    local filtered = {}
    for _, m in ipairs(sendMessages) do
      if m.role == "tool" then
        -- 跳过
      elseif m.role == "assistant" and m.tool_calls then
        if m.content and m.content ~= "" then
          m.tool_calls = nil
          filtered[#filtered + 1] = m
        end
      else
        filtered[#filtered + 1] = m
      end
    end
    sendMessages = filtered
  end

  -- Repair histories created by providers that omitted tool-call ids.
  -- The id must match between assistant.tool_calls and the following tool message.
  if supportsTools then
    local nextToolId = 0
    local pendingToolIds = nil
    local function fallbackToolId()
      nextToolId = nextToolId + 1
      return "call_history_" .. tostring(nextToolId)
    end
    for _, m in ipairs(sendMessages) do
      if m.role == "assistant" and m.tool_calls then
        pendingToolIds = {}
        for _, tc in ipairs(m.tool_calls) do
          local id = tc.id
          if not id or id == "" then
            id = fallbackToolId()
            tc.id = id
          end
          pendingToolIds[#pendingToolIds + 1] = id
        end
      elseif m.role == "tool" then
        -- 只从紧邻的 assistant tool_calls 组中修复缺失 ID，禁止跨组配对。
        if pendingToolIds and #pendingToolIds > 0 then
          if not m.tool_call_id or m.tool_call_id == "" then
            m.tool_call_id = table.remove(pendingToolIds, 1)
          else
            for index, id in ipairs(pendingToolIds) do
              if id == m.tool_call_id then
                table.remove(pendingToolIds, index)
                break
              end
            end
          end
        end
      else
        pendingToolIds = nil
      end
    end
  end

  -- 清理消息中的 tool_calls function 键
  for _, m in ipairs(sendMessages) do
    if m.tool_calls then
      for _, tc in ipairs(m.tool_calls) do
      end
    end
  end

  local body = {
    model = getModel(),
    messages = sendMessages,
    stream = true,
    max_tokens = callbacks.maxTokens or getMaxTokens(),
    temperature = getTemperature(),
  }
  if supportsTools then
    local tools = {}
    for _, t in ipairs(_M.TOOLS) do
      tools[#tools + 1] = t
    end
    -- 合并 MCP 服务器工具（mcp::服务器::工具），仅读缓存，不在此处发起网络请求
    pcall(function()
      local mcpTools = MCPClient.getCachedOpenAiTools()
      if type(mcpTools) == "table" and #mcpTools > 0 then
        for _, t in ipairs(mcpTools) do
          tools[#tools + 1] = t
        end
      end
    end)
    body.tools = tools
  end

  -- 统计最终请求消息（含工具定义），由 UI 直接显示本次实际发送的用量。
  if callbacks.onPrepared then
    local usage = 0
    for _, message in ipairs(body.messages or {}) do
      local encoded = json.encode(message)
      usage = usage + ContextManager.estimateTokens(encoded)
    end
    for _, tool in ipairs(body.tools or {}) do
      local encoded = json.encode(tool)
      usage = usage + ContextManager.estimateTokens(encoded)
    end
    callbacks.onPrepared({
      used = math.ceil(usage / 4),
      budget = math.max(2000, getContextLength() - getMaxTokens() - 200),
    })
  end

  local headers = {
    ["Authorization"] = "Bearer " .. key,
    ["Content-Type"] = "application/json",
  }

  local bodyStr = json.encode(body)
  if not bodyStr or bodyStr == "" then
    if callbacks.onError then callbacks.onError("请求体编码失败") end
    return
  end
  local maxRetries = getRetryCount()
  local attempt = 0

  -- 可重试的错误：网络异常 / HTTP 5xx / 429（限流）；4xx 为参数或鉴权错误，不重试；用户取消不重试
  local function isRetryableError(msg)
    if tostring(msg):lower():match("cancel") then return false end
    if msg:match("^HTTP 429") then return true end
    if msg:match("^HTTP 4") then return false end
    return true
  end

  local function doRequest()
    attempt = attempt + 1
    getHttpClient().postJsonStream(
    baseUrl,
    bodyStr,
    headers,
    -- onChunk: 文本内容
    function(text)
      if callbacks.onChunk then callbacks.onChunk(tostring(text)) end
    end,
    -- onDone: (fullText, toolCallsJson) 成功，或 (error, errorBody) 失败
    function(arg1, arg2)
      local a1 = tostring(arg1 or "")
      -- 判断是否为错误（HTTP / Stream / java 异常）
      local isError = a1:match("^HTTP") or a1:match("^Stream") or a1:match("^ERROR:") or a1:match("^java")
      if isError then
        -- 自动重试：达到设置次数或不可重试错误时停止
        if attempt <= maxRetries and isRetryableError(a1) then
          if callbacks.onRetry then callbacks.onRetry() end
          Thread.sleep(math.min(1200, attempt * 300))
          doRequest()
          return
        end
        local errMsg = a1
        if arg2 and arg2 ~= "" then
          local eb = tostring(arg2)
          local ok2, decoded = pcall(json.decode, eb)
          if ok2 and decoded then
            local e = decoded.error or decoded.data
            local detail = decoded.message or ""
            if type(e) == "table" then
              if e.message then
                detail = e.message
              elseif e[1] and type(e[1]) == "table" then
                detail = e[1].message or e[1].type or detail
                if e[1].code then
                  errMsg = errMsg .. "\n错误码: " .. tostring(e[1].code)
                end
              else
                detail = e.type or detail
              end
              if e.code then errMsg = errMsg .. "\n错误码: " .. tostring(e.code) end
            end
            if detail ~= "" then errMsg = errMsg .. "\n" .. tostring(detail) end
            if decoded.code and not tostring(decoded.code):match("^HTTP") then
              errMsg = errMsg .. "\n错误码: " .. tostring(decoded.code)
            end
          else
            if #eb < 500 then errMsg = errMsg .. "\n响应: " .. eb
            else errMsg = errMsg .. "\n响应: " .. eb:sub(1, 500) .. "…" end
          end
        end
        errMsg = errMsg .. "\n模型: " .. getModel() .. "\n地址: " .. baseUrl
        errMsg = errMsg .. "\n请求大小: " .. #bodyStr .. " 字节"
        finish(callbacks.onError, errMsg)
        return
      end

      -- 解析 tool calls JSON（arg2）
      if arg2 and arg2 ~= "" then
        local ok2, tcArr = pcall(json.decode, tostring(arg2))
        if ok2 and type(tcArr) == "table" then
          local toolCalls = {}
          for index, tc in ipairs(tcArr) do
            local fn = tc["function"]
            local name = tc.name
            local arguments = tc.arguments
            if type(fn) == "table" then
              if not name or name == "" then name = fn.name end
              if not arguments or arguments == "" then arguments = fn.arguments end
            end
            local normalizedName = ToolExecutor.normalizeToolName(name)
            if normalizedName ~= "" then
              toolCalls[#toolCalls + 1] = {
                id = (tc.id and tc.id ~= "") and tc.id or ("call_" .. tostring(index)),
                name = normalizedName,
                arguments = type(arguments) == "table" and json.encode(arguments) or (arguments or "{}"),
              }
            end
          end
          if #toolCalls > 0 then
            finish(callbacks.onToolCalls, toolCalls, a1)
            return
          end
          if a1 ~= "" then
            finish(callbacks.onDone, a1)
            return
          end
        end
      end

      -- 纯文本
      if a1 == "" then
        finish(callbacks.onError, "AI 未返回内容\n模型: " .. getModel() .. "\n地址: " .. baseUrl)
        return
      end

      finish(callbacks.onDone, a1)
      end
    )
  end

  doRequest()
end

]]
-- 上下文策略集中在 ContextManager；这里保留公开入口，兼容现有调用方。
ContextManager.configure({
  getSystemPrompt = function() return _M.getSystemPrompt() end,
  getContextLength = getContextLength,
  getMaxTokens = getMaxTokens,
  sendStream = function(messages, callbacks) return _M.sendStream(messages, callbacks) end,
})
OpenAIClient.configure({
  getApiKey = getApiKey,
  getApiUrl = getApiUrl,
  getModel = getModel,
  getTemperature = getTemperature,
  getMaxTokens = getMaxTokens,
  getRetryCount = getRetryCount,
  getHttpClient = getHttpClient,
  getBuiltinTools = function() return _M.TOOLS end,
  getMcpTools = function() return MCPClient.getCachedOpenAiTools() end,
   normalizeToolName = function(name) return ToolExecutor.normalizeToolName(name) end,
  estimateRequestUsage = function(body)
    local used = 0
    for _, item in ipairs(body.messages or {}) do
      used = used + ContextManager.estimateTokens(json.encode(item))
    end
    for _, item in ipairs(body.tools or {}) do
      used = used + ContextManager.estimateTokens(json.encode(item))
    end
    return {
      used = used,
      budget = math.max(2000, getContextLength() - getMaxTokens() - 200),
    }
  end,
})
ToolExecutor.configure({
  normalizePath = normalizePath,
  getProjectDir = function() return Bean and Bean.Path and Bean.Path.this_dir or activity.getLuaDir() end,
  getSharedData = function(key, defaultValue) return this.getSharedData(key, defaultValue) end,
  findMcpServer = function(namespace) return MCPClient.findServer(namespace) end,
  callMcpToolAsync = function(server, tool, args, callback)
    return MCPClient.callToolAsync(server, tool, args, callback)
  end,
  callMcpTool = function(server, tool, args)
    return MCPClient.callTool(server, tool, args)
  end,
  platformExecute = legacyExecuteTool,
  changeSet = ChangeSet,
})
_M.testConnection = OpenAIClient.testConnection
_M.sendStream = OpenAIClient.sendStream
_M.normalizeToolName = ToolExecutor.normalizeToolName
_M.executeTool = ToolExecutor.executeTool
_M.executeToolAsync = ToolExecutor.executeToolAsync
_M.isDestructiveTool = ToolExecutor.isDestructiveTool
_M.isInProjectDir = ToolExecutor.isInProjectDir
_M.shouldAutoApprove = ToolExecutor.shouldAutoApprove
_M.undoFileChange = ChangeSet.undo
_M.redoFileChange = ChangeSet.redo
_M.hasFileUndo = ChangeSet.hasUndo
_M.hasFileRedo = ChangeSet.hasRedo
_M.clearFileChanges = ChangeSet.clear
_M.buildApiMessages = ContextManager.buildApiMessages
_M.buildCompressedApiMessages = ContextManager.buildCompressedApiMessages
_M.estimateContextUsage = ContextManager.estimateContextUsage
_M.estimateApiMessagesUsage = ContextManager.estimateApiMessagesUsage

return _M
