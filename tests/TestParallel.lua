local ASSETS = ASSETS or "app/src/main/assets/"

-- 并行工具批次分类测试：ToolExecutor 独立加载 + 全局 json 桩 + 最小工程配置
local TE = assert(loadfile(ASSETS .. "mods/agent/ToolExecutor.lua"))()

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("PASS  " .. name)
  else
    failures = failures + 1
    print("FAIL  " .. name .. (detail ~= nil and ("  [" .. tostring(detail) .. "]") or ""))
  end
end

-- json 桩：arguments 用 Lua 表源码字符串，encode/decode 闭环
local jsonShim = {
  encode = function(v)
    local parts = {}
    for i = 1, #v do parts[i] = tostring(v[i]) end
    if #v == 0 then
      for k, val in pairs(v) do
        parts[#parts + 1] = "[" .. string.format("%q", k) .. "] = " .. string.format("%q", tostring(val))
      end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end,
  decode = function(s)
    local f = loadstring("return " .. tostring(s))
    if not f then return nil end
    local ok, r = pcall(f)
    return ok and r or nil
  end,
}
json = jsonShim

TE.configure({
  getProjectDir = function() return "/proj" end,
  normalizePath = function(p) return tostring(p or "") end,
  canonicalPath = function(p) return tostring(p or "") end,
  getPathType = function(p) return "file" end,
  getSharedData = function(key, defaultValue) return defaultValue end,
  getProjectPolicy = function() return nil end,
})

local function tc(id, name, argsSrc)
  return { id = id, name = name, arguments = argsSrc }
end
local A = '{["path"]="/proj/a.lua"}'
local B = '{["path"]="/proj/b.lua"}'
local OUT = '{["path"]="/etc/passwd"}'

-- 1. 数量门槛
check("single call not parallel", TE.classifyParallelBatch({ tc("1", "read_file", A) }) == nil)
check("non-table rejected", TE.classifyParallelBatch("nope") == nil)

-- 2. 纯只读批次可并行
local calls = TE.classifyParallelBatch({ tc("1", "read_file", A), tc("2", "read_file", B) })
check("two reads parallel", type(calls) == "table" and #calls == 2
  and calls[1].name == "read_file" and calls[2].name == "read_file", calls)
check("ids preserved", calls and calls[1].id == "1" and calls[2].id == "2")

calls = TE.classifyParallelBatch({
  tc("1", "read_file", A),
  tc("2", "list_dir", '{["path"]="/proj"}'),
  tc("3", "check_lua_syntax", '{["code"]="print(1)"}'),
  tc("4", "get_env_info", "{}"),
})
check("mixed read-only batch ok", type(calls) == "table" and #calls == 4)

-- 3. 别名与规范化
calls = TE.classifyParallelBatch({ tc("1", "ReadFile", A), tc("2", "list_files", '{["path"]="/proj"}') })
check("aliases normalized", type(calls) == "table" and calls[1].name == "read_file"
  and calls[2].name == "list_dir", calls)

-- 4. 非白名单 / 需确认的调用整批回退串行
check("apply_patch blocks batch",
  TE.classifyParallelBatch({ tc("1", "read_file", A), tc("2", "apply_patch", "{}") }) == nil)
check("run_lua blocks batch",
  TE.classifyParallelBatch({ tc("1", "read_file", A), tc("2", "run_lua", "{}") }) == nil)
check("update_todos blocks batch",
  TE.classifyParallelBatch({ tc("1", "read_file", A), tc("2", "update_todos", "{}") }) == nil)
check("run_subtask blocks batch",
  TE.classifyParallelBatch({ tc("1", "read_file", A), tc("2", "run_subtask", "{}") }) == nil)
check("fetch_url blocks batch",
  TE.classifyParallelBatch({ tc("1", "read_file", A), tc("2", "fetch_url", "{}") }) == nil)
check("run_project blocks batch",
  TE.classifyParallelBatch({ tc("1", "read_file", A), tc("2", "run_project", "{}") }) == nil)

-- 5. 工程外路径需要确认 → 回退
check("out-of-project read blocks batch",
  TE.classifyParallelBatch({ tc("1", "read_file", OUT), tc("2", "read_file", B) }) == nil)

-- 6. 参数 JSON 无效 → 回退（串行路径负责报 JSON 错误）
check("bad json args block batch",
  TE.classifyParallelBatch({ tc("1", "read_file", "{bad json"), tc("2", "read_file", B) }) == nil)

-- 7. 曾失败的同参调用 → 回退串行短路
local failedArgs = jsonShim.encode({ path = "/proj/a.lua" })
local failedKey = "read_file\n" .. failedArgs
local failedCalls = {}
failedCalls[failedKey] = "上次的错误"
check("failed-dup blocks batch",
  TE.classifyParallelBatch({ tc("1", "read_file", A), tc("2", "read_file", B) }, { failedToolCalls = failedCalls }) == nil)
check("no deps passes",
  type(TE.classifyParallelBatch({ tc("1", "read_file", A), tc("2", "read_file", B) })) == "table")

-- 8. isParallelSafe 白名单
check("isParallelSafe read_file", TE.isParallelSafe("read_file", {}) == true)
check("isParallelSafe get_env_info", TE.isParallelSafe("get_env_info", {}) == true)
check("isParallelSafe blocks run_lua", TE.isParallelSafe("run_lua", {}) == false)
check("isParallelSafe blocks fetch", TE.isParallelSafe("fetch_url", {}) == false)
check("isParallelSafe blocks write", TE.isParallelSafe("create_file", {}) == false)
check("isParallelSafe blocks subtask", TE.isParallelSafe("run_subtask", {}) == false)

if failures == 0 then print("ALL-PASS") else print("FAILURES: " .. failures) end
