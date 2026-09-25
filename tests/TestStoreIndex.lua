local ASSETS = ASSETS or "app/src/main/assets/"

-- ConversationStore.loadIndex + getData 回退 + InitReader.readFields 行为测试
package.preload["mods.agent.ConversationStore"] = assert(loadfile(ASSETS .. "mods/agent/ConversationStore.lua"))
local CS = assert(loadfile(ASSETS .. "mods/agent/ConversationStore.lua"))()
local IR = assert(loadfile(ASSETS .. "mods/project/InitReader.lua"))()

local failures = 0
local function check(name, cond)
  if cond then
    print("PASS  " .. name)
  else
    failures = failures + 1
    print("FAIL  " .. name)
  end
end

-- ── 1. 未 configure 时的默认回退（this 不存在 → 返回空，不崩溃）──
local plain = CS.load()
check("unconfigured load returns empty table", type(plain) == "table" and #plain == 0)
local idx = CS.loadIndex()
check("unconfigured loadIndex returns empty table", type(idx) == "table" and #idx == 0)

-- ── 2. configure：encode/decode 用引用注册表旁路（真实环境为 json）──
local data = {}
local registry = {}
local nextRef = 0
CS.configure({
  getData = function(key, def) return data[key] ~= nil and data[key] or def end,
  setData = function(key, value) data[key] = value; return true end,
  encode = function(v)
    nextRef = nextRef + 1
    registry[nextRef] = v
    return "REF:" .. nextRef
  end,
  decode = function(s)
    local n = tonumber(tostring(s or ""):match("REF:(%d+)"))
    return n and registry[n] or nil
  end,
  getProjectPath = function() return "/sdcard/LuaJ/Projects/Demo" end,
  normalizeProjectPath = function(p) return tostring(p or ""):gsub("/+$", "") end,
})

local rec = CS.create("测试会话", "/sdcard/LuaJ/Projects/Demo")
check("create returns record", rec ~= nil and rec.id ~= nil)
check("create assigned path", rec.projectPath == "/sdcard/LuaJ/Projects/Demo")

CS.save(rec.id, { { role = "user", content = "你好" }, { role = "assistant", content = "在" } }, rec.projectPath)
CS.save(rec.id, { { role = "user", content = "你好" }, { role = "assistant", content = "在" }, { role = "user", content = "继续" } }, rec.projectPath, { usage = { tokens = 1234 } })

-- ── 3. loadIndex：仅元数据 + messageCount ──
local list = CS.load()
check("load returns full record with messages", list[1] ~= nil and type(list[1].messages) == "table" and #list[1].messages == 3)

local index = CS.loadIndex()
check("loadIndex returns one row", #index == 1)
check("loadIndex row has id", index[1].id == rec.id)
check("loadIndex row has name", index[1].name == "测试会话")
check("loadIndex row has projectPath", index[1].projectPath == "/sdcard/LuaJ/Projects/Demo")
check("loadIndex row has messageCount", index[1].messageCount == 3)
check("loadIndex row has no messages table", index[1].messages == nil)
check("loadIndex row keeps usage", type(index[1].usage) == "table" and tonumber(index[1].usage.tokens) == 1234)

-- 深隔离：改 index 行不影响 store 内部
index[1].name = "被篡改"
check("loadIndex rows are isolated from store", CS.loadIndex()[1].name == "测试会话")

-- loadIndex(force) 与 load 一致
local index2 = CS.loadIndex(true)
check("loadIndex force returns same count", #index2 == 1 and index2[1].messageCount == 3)

-- ── 4. 多会话排序无关性 + rename 后 loadIndex 同步 ──
local rec2 = CS.create("第二个会话", "/sdcard/LuaJ/Projects/Other")
CS.save(rec2.id, { { role = "user", content = "hi" } }, rec2.projectPath)
local index3 = CS.loadIndex()
check("loadIndex two rows", #index3 == 2)
CS.rename(rec2.id, "改名后", rec2.projectPath)
local index4 = CS.loadIndex()
local found = false
for _, row in ipairs(index4) do
  if row.id == rec2.id then found = (row.name == "改名后") end
end
check("rename reflected in loadIndex", found)

-- 删除后 loadIndex 同步
CS.delete(rec.id, "/sdcard/LuaJ/Projects/Demo")
local index5 = CS.loadIndex()
check("delete reflected in loadIndex", #index5 == 1 and index5[1].id == rec2.id)

-- ── 5. InitReader.readFields 批量读取 ──
-- readFields(path) 期望 path 为工程目录（内部拼接 /init.lua）；
-- 直接以 opencode 目录作为临时工程目录，结束后清理 init.lua
local tmpDir = (os.getenv("TEMP") or "/tmp"):gsub("\\", "/")
local tmpPath = tmpDir .. "/init.lua"
os.remove(tmpPath)
file = {
  readall = function(p)
    local h = io.open(p, "rb")
    if not h then return nil end
    local c = h:read("*a")
    h:close()
    return c
  end,
}
local h = io.open(tmpPath, "wb")
h:write('app_name = "我的应用"\npackage_name = "com.demo.app"\nversion_code = "11"\n')
h:close()

local fields = IR.readFields(tmpDir, { "app_name", "package_name" })
check("readFields returns table", type(fields) == "table")
check("readFields app_name", fields.app_name == "我的应用")
check("readFields package_name", fields.package_name == "com.demo.app")
check("readFields omits unrequested keys", fields.version_code == nil)

local single = IR.readField(tmpDir, "app_name")
check("readField delegates to readFields", single == "我的应用")
local missing = IR.readField(tmpDir, "no_such_key")
check("readField missing key returns nil", missing == nil)

-- 单引号字符串
local h2 = io.open(tmpPath, "wb")
h2:write("app_name = '单引号'\n")
h2:close()
check("readFields single quotes", IR.readFields(tmpDir, { "app_name" }).app_name == "单引号")

-- 文件不存在（目录存在但无 init.lua）
check("readFields missing file returns nil", IR.readFields(tmpDir .. "/nope_dir", { "app_name" }) == nil)
os.remove(tmpPath)

if failures == 0 then
  print("ALL-PASS")
else
  print("FAILURES: " .. failures)
  os.exit(1)
end
