local ASSETS = ASSETS or "app/src/main/assets/"

-- ModelRegistry 行为测试：表驱动存储桩 + 序列化 shim，独立 LuaJ 运行时
local PATH = ASSETS .. "mods/agent/ModelRegistry.lua"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("PASS  " .. name)
  else
    failures = failures + 1
    print("FAIL  " .. name .. (detail ~= nil and ("  [" .. tostring(detail) .. "]") or ""))
  end
end

-- 序列化 shim：记录为“字符串键对象”组成的数组，%q 转义保证可回读
local function serValue(v)
  local t = type(v)
  if t == "string" then return string.format("%q", v) end
  if t == "number" or t == "boolean" then return tostring(v) end
  if t == "table" then
    local parts = {}
    for i = 1, #v do parts[i] = serValue(v[i]) end
    if #v == 0 then
      for k, val in pairs(v) do
        parts[#parts + 1] = "[" .. string.format("%q", k) .. "] = " .. serValue(val)
      end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "nil"
end
local jsonShim = {
  encode = function(v) return "return " .. serValue(v) end,
  decode = function(s)
    local f = loadstring(s)
    if not f then return nil end
    local ok, r = pcall(f)
    return ok and r or nil
  end,
}

local function makeInstance(storeData)
  local inst = assert(loadfile(PATH))()
  inst.configure({
    getSharedData = function(key, defaultValue)
      local v = storeData[key]
      if v == nil then return defaultValue end
      return v
    end,
    setSharedData = function(key, value) storeData[key] = value end,
    json = jsonShim,
  })
  return inst, storeData
end

local MR, store = makeInstance({})

-- ── 1. 空状态 ──
check("empty providers", type(MR.loadProviders()) == "table" and #MR.loadProviders() == 0)
check("empty models", #MR.loadModels() == 0)
check("empty index", MR.getCurrentModelIndex() == 0)
check("empty config nil", MR.getCurrentModelConfig() == nil)
check("no api key", MR.hasApiKey() == false)
check("context default", MR.getContextLength() == 30000)
check("maxTokens bound", MR.getMaxTokens() <= 29500 and MR.getMaxTokens() >= 256)
check("temperature default", MR.getTemperature() == 0.7)
check("retry default", MR.getRetryCount() == 2)
check("aux unset", MR.getAuxModelIndex() == 0 and MR.getAuxModelConfig() == nil)

-- ── 2. 供应商 CRUD ──
local p1 = MR.addProvider("  DeepSeek  ", "https://api.deepseek.com/v1", "sk-1")
check("provider trim", p1.name == "DeepSeek" and p1.id ~= "")
check("provider persisted", store["ai_providers"] ~= nil and #MR.loadProviders() == 1)
check("findProvider", MR.findProvider(p1.id) == p1)
local p2 = MR.addProvider("", "https://x.example/v1", "sk-2")
check("provider name fallback url", p2.name == "https://x.example/v1")
check("updateProvider", MR.updateProvider(p2.id, "X", "https://y.example/v1", "sk-2b") == true
  and MR.findProvider(p2.id).name == "X")
check("updateProvider missing", MR.updateProvider("nope", "n", "u", "k") == false)

-- ── 3. 模型 CRUD ──
check("addModel", MR.addModel("  Chat  ", p1.id, " deepseek-chat ", false, 30000, 4096) == 1)
local m1 = MR.findModel(p1.id, "deepseek-chat")
check("findModel trims", m1 ~= nil and m1.model == "deepseek-chat" and m1.name == "Chat")
check("countModels", MR.countModels(p1.id) == 1)
MR.addModel("GPT", p2.id, "gpt-x", true, 2000, 99999)
local m2 = MR.findModel(p2.id, "gpt-x")
check("maxTokens clamped ctx-500", m2.maxTokens == 1500 and m2.contextLength == 2000, m2.maxTokens)
check("responses normalized", m2.responses == true)
check("addModels dedup", #MR.addModels(p1.id, { "m1", " m1 ", "m2" }, false, 30000, 4096) == 2)
check("models total 4", #MR.loadModels() == 4, #MR.loadModels())

-- ── 4. 当前模型解析 ──
check("current index 1", MR.getCurrentModelIndex() == 1)
local cfg = MR.getCurrentModelConfig()
check("config url from provider", cfg.url == "https://api.deepseek.com/v1", cfg.url)
check("config key from provider", cfg.key == "sk-1")
check("config providerName", cfg.providerName == "DeepSeek")
check("getModel", MR.getModel() == "deepseek-chat")
check("getApiKey", MR.getApiKey() == "sk-1")
check("hasApiKey", MR.hasApiKey() == true)
check("getContextLength", MR.getContextLength() == 30000)
check("getMaxTokens", MR.getMaxTokens() == 4096)
MR.setCurrentModel(2)
check("setCurrentModel", MR.getCurrentModelIndex() == 2)
MR.setCurrentModel(99)
check("setCurrentModel clamps", MR.getCurrentModelIndex() == 1)

-- ── 5. 辅助模型路由 ──
MR.setAuxModelIndex(2)
check("aux resolves via provider", MR.getAuxModelConfig() ~= nil
  and MR.getAuxModelConfig().model == "gpt-x" and MR.getAuxModelConfig().key == "sk-2b",
  MR.getAuxModelConfig() and MR.getAuxModelConfig().key)
check("aux persisted", MR.getAuxModelIndex() == 2
  and store["ai_aux_provider_id"] == p2.id and store["ai_aux_model_id"] == "gpt-x")
MR.setAuxModelIndex(0)
check("aux explicit clear", MR.getAuxModelIndex() == 0)
MR.setAuxModelIndex(99)
check("aux out of range clears", MR.getAuxModelIndex() == 0 and MR.getAuxModelConfig() == nil)
MR.setAuxModelIndex(2)
MR.removeModel(2)
check("aux invalidates on removal", MR.getAuxModelIndex() == 0 and MR.getAuxModelConfig() == nil)

-- ── 6. removeModel 索引修正 ──
-- 当前模型列表：deepseek-chat(1) m1(2) m2(3)（gpt-x 已删）
MR.setCurrentModel(3)
MR.removeModel(1)
check("removeModel shifts current", MR.getCurrentModelIndex() == 2, MR.getCurrentModelIndex())
check("removeModel out of range", MR.removeModel(99) == false)

-- ── 7. removeProvider 级联 ──
MR.setCurrentModel(1)
check("removeProvider cascade", MR.removeProvider(p1.id) == true)
check("cascade removed models", MR.countModels(p1.id) == 0 and #MR.loadModels() == 0, #MR.loadModels())
check("index zero after cascade", MR.getCurrentModelIndex() == 0)
check("removeProvider missing", MR.removeProvider(p1.id) == false)

-- ── 8. 持久化往返（新实例同一存储）──
local keepP = MR.addProvider("Keep", "https://keep.example/v1", "sk-keep")
MR.addModel("Keeper", keepP.id, "keep-model", false, 30000, 4096)
MR.setAuxModelIndex(1)
local MRr = assert(loadfile(PATH))()
MRr.configure({
  getSharedData = function(key, defaultValue)
    local v = store[key]
    if v == nil then return defaultValue end
    return v
  end,
  setSharedData = function(key, value) store[key] = value end,
  json = jsonShim,
})
check("persist providers", MRr.findProvider(keepP.id) ~= nil)
check("persist models", MRr.findModel(keepP.id, "keep-model") ~= nil)
check("persist aux by identity", MRr.getAuxModelIndex() == 1 and MRr.getAuxModelConfig().key == "sk-keep",
  MRr.getAuxModelIndex())

-- ── 9. 旧版迁移（新实例新存储）──
local MR3 = assert(loadfile(PATH))()
local legacyStore = {
  ai_api_key = "sk-legacy",
  ai_api_url = "https://legacy.example/v1",
  ai_model = "legacy-model",
  ai_context_length = "500",
  ai_max_tokens = "99999",
}
MR3.configure({
  getSharedData = function(key, defaultValue)
    local v = legacyStore[key]
    if v == nil then return defaultValue end
    return v
  end,
  setSharedData = function(key, value) legacyStore[key] = value end,
  json = jsonShim,
})
local migrated = MR3.loadModels()
check("legacy one model", #migrated == 1 and migrated[1].model == "legacy-model")
check("legacy ctx floor", migrated[1].contextLength == 1000, migrated[1].contextLength)
check("legacy max clamped", migrated[1].maxTokens == 500, migrated[1].maxTokens)
-- attachProviders 把 url/key 挪到供应商，模型只留 providerId
check("legacy model slim", migrated[1].key == nil and migrated[1].providerId ~= nil)
check("legacy provider attached", MR3.getCurrentModelConfig().url == "https://legacy.example/v1"
  and MR3.getCurrentModelConfig().key == "sk-legacy")
check("legacy persisted", legacyStore["ai_models"] ~= nil and legacyStore["ai_providers"] ~= nil)
check("legacy hasApiKey", MR3.hasApiKey() == true)

-- ── 10. 全局配置钳制 ──
store["ai_temperature"] = "5"
check("temperature clamp high", MR.getTemperature() == 2)
store["ai_temperature"] = "-1"
check("temperature clamp low", MR.getTemperature() == 0)
store["ai_retry_count"] = "99"
check("retry clamp", MR.getRetryCount() == 5)
store["ai_retry_count"] = "-3"
check("retry floor", MR.getRetryCount() == 0)
check("trim export", MR.trim("  x  ") == "x" and MR.trim(nil) == "")

if failures == 0 then print("ALL-PASS") else print("FAILURES: " .. failures) end
