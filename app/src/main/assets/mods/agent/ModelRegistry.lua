--- 模型注册表：供应商与模型的 CRUD、当前模型解析、配置读取与旧版迁移。
--- 存储与 JSON 编解码经 configure 注入（生产环境注入 this.getSharedData/setSharedData，
--- 全局 json 作为兜底），因此本模块可在独立 LuaJ 运行时中做行为测试。
local _M = {}

local getStore, setStore
local jsonLib

function _M.configure(options)
  options = options or {}
  getStore = options.getSharedData
  setStore = options.setSharedData
  jsonLib = options.json
end

local function shared(key, defaultValue)
  if not getStore then return defaultValue end
  return getStore(key, defaultValue)
end

local function persist(key, value)
  if not setStore then return end
  setStore(key, value)
end

local function decode(raw)
  local lib = jsonLib or json
  if not lib or not lib.decode then return nil end
  local ok, decoded = pcall(lib.decode, raw)
  if ok then return decoded end
  return nil
end

local function encode(value)
  local lib = jsonLib or json
  if not lib or not lib.encode then return nil end
  local ok, encoded = pcall(lib.encode, value)
  if ok then return encoded end
  return nil
end

-- ─── 配置读取 ──

local function getLegacyApiKey()
  return shared("ai_api_key", "")
end

local function getLegacyApiUrl()
  return shared("ai_api_url", "https://api.deepseek.com/v1")
end

local function getLegacyModel()
  return shared("ai_model", "deepseek-v4-flash")
end

function _M.getApiKey()
  local current = _M.getCurrentModelConfig()
  return current and tostring(current.key or "") or ""
end

function _M.getApiUrl()
  local current = _M.getCurrentModelConfig()
  return current and tostring(current.url or "") or ""
end

function _M.getModel()
  local current = _M.getCurrentModelConfig()
  return current and tostring(current.model or "") or ""
end

function _M.getTemperature()
  local v = tonumber(shared("ai_temperature", "0.7"))
  if not v then return 0.7 end
  return math.max(0, math.min(2, v))
end

local DEFAULT_CONTEXT_LENGTH = 30000
local DEFAULT_MAX_TOKENS = 4096

local function normalizeContextLength(value, fallback)
  local parsed = tonumber(value) or fallback or DEFAULT_CONTEXT_LENGTH
  return math.max(1000, math.floor(parsed))
end

local function normalizeMaxTokens(value, fallback)
  local parsed = tonumber(value) or fallback or DEFAULT_MAX_TOKENS
  return math.max(256, math.min(32768, math.floor(parsed)))
end

local function normalizeModelLimits(contextLength, maxTokens, fallbackContext, fallbackMaxTokens)
  local normalizedContext = normalizeContextLength(contextLength, fallbackContext)
  local normalizedMax = normalizeMaxTokens(maxTokens, fallbackMaxTokens)
  normalizedMax = math.min(normalizedMax, math.max(256, normalizedContext - 500))
  return normalizedContext, normalizedMax
end

-- 模型上下文长度（context window），用于历史消息截断预算
function _M.getContextLength()
  local current = _M.getCurrentModelConfig()
  return normalizeContextLength(current and current.contextLength, DEFAULT_CONTEXT_LENGTH)
end

function _M.getMaxTokens()
  local current = _M.getCurrentModelConfig()
  local v = normalizeMaxTokens(current and current.maxTokens, DEFAULT_MAX_TOKENS)
  -- 输出不能超过上下文窗口（至少留 500 token 余量）
  local ctx = _M.getContextLength()
  return math.min(v, math.max(256, ctx - 500))
end

-- 失败自动重试次数（0 = 不重试）
function _M.getRetryCount()
  local v = tonumber(shared("ai_retry_count", "2"))
  if not v then return 2 end
  if v < 0 then return 0 end
  return math.min(5, math.floor(v))
end

function _M.hasApiKey()
  return _M.getApiKey() ~= ""
end

-- ─── 供应商与模型 ──

local PROVIDERS_KEY = "ai_providers"
local MODELS_KEY = "ai_models"
local MODEL_INDEX_KEY = "ai_model_index"
local providersCache = nil
local modelsCache = nil
local idSerial = 0

function _M.trim(value)
  return tostring(value or ""):gsub("^%s*(.-)%s*$", "%1")
end

local function newId(prefix)
  idSerial = idSerial + 1
  return prefix .. tostring(os.time()) .. tostring(idSerial)
end

local function resolvedModel(model)
  if type(model) ~= "table" then return nil end
  local copy = {
    name = model.name,
    providerId = model.providerId,
    model = model.model,
    responses = model.responses == true,
    contextLength = model.contextLength,
    maxTokens = model.maxTokens,
    url = model.url,
    key = model.key,
  }
  local provider = _M.findProvider(model.providerId)
  if provider then
    copy.url = provider.url
    copy.key = provider.key
    copy.providerName = provider.name
  end
  return copy
end

function _M.loadProviders()
  if providersCache then return providersCache end
  local raw = shared(PROVIDERS_KEY, "")
  if raw == "" or raw == nil then
    providersCache = {}
    return providersCache
  end
  local decoded = decode(raw)
  providersCache = type(decoded) == "table" and decoded or {}
  return providersCache
end

function _M.saveProviders(providers)
  providersCache = providers
  local encoded = encode(providers)
  if encoded then persist(PROVIDERS_KEY, encoded) end
end

function _M.findProvider(id)
  if id == nil or id == "" then return nil end
  for _, provider in ipairs(_M.loadProviders()) do
    if provider.id == id then return provider end
  end
end

function _M.addProvider(name, url, key)
  local providers = _M.loadProviders()
  name, url, key = _M.trim(name), _M.trim(url), _M.trim(key)
  local provider = {
    id = newId("p"),
    name = name ~= "" and name or url,
    url = url,
    key = key,
  }
  providers[#providers + 1] = provider
  _M.saveProviders(providers)
  return provider
end

function _M.updateProvider(id, name, url, key)
  local providers = _M.loadProviders()
  name, url, key = _M.trim(name), _M.trim(url), _M.trim(key)
  for index, provider in ipairs(providers) do
    if provider.id == id then
      providers[index] = {
        id = id,
        name = name ~= "" and name or url,
        url = url,
        key = key,
      }
      _M.saveProviders(providers)
      return true
    end
  end
  return false
end

local function attachProviders(models)
  local providers = _M.loadProviders()
  local changedProviders, changedModels = false, false
  local function findOrCreate(url, key, name)
    url, key, name = _M.trim(url), _M.trim(key), _M.trim(name)
    for _, provider in ipairs(providers) do
      if provider.url == url and provider.key == key then return provider.id end
    end
    local provider = {
      id = newId("p"),
      name = name ~= "" and name or (url ~= "" and url or "Provider"),
      url = url,
      key = key,
    }
    providers[#providers + 1] = provider
    changedProviders = true
    return provider.id
  end
  for _, model in ipairs(models) do
    if type(model) == "table" then
      if _M.findProvider(model.providerId) then
        if model.url ~= nil or model.key ~= nil then
          model.url = nil
          model.key = nil
          changedModels = true
        end
      elseif _M.trim(model.url) ~= "" or _M.trim(model.key) ~= "" then
        model.providerId = findOrCreate(model.url, model.key, model.name)
        model.url = nil
        model.key = nil
        changedModels = true
      end
    end
  end
  if changedProviders then _M.saveProviders(providers) end
  return changedModels
end

function _M.loadModels()
  if modelsCache then return modelsCache end
  local raw = shared(MODELS_KEY, "")
  if raw == "" or raw == nil then
    local key = getLegacyApiKey()
    if key ~= "" then
      local model = getLegacyModel()
      local contextLength, maxTokens = normalizeModelLimits(
        shared("ai_context_length", "30000"),
        shared("ai_max_tokens", "4096"),
        DEFAULT_CONTEXT_LENGTH,
        DEFAULT_MAX_TOKENS
      )
      modelsCache = { {
        name = model, url = getLegacyApiUrl(), key = key, model = model, responses = false,
        contextLength = contextLength,
        maxTokens = maxTokens,
      } }
      attachProviders(modelsCache)
      _M.saveModels(modelsCache)
      return modelsCache
    end
    modelsCache = {}
    return modelsCache
  end
  local decoded = decode(raw)
  if type(decoded) == "table" then
    local legacyContextLength = normalizeContextLength(
      shared("ai_context_length", tostring(DEFAULT_CONTEXT_LENGTH)),
      DEFAULT_CONTEXT_LENGTH
    )
    local legacyMaxTokens = normalizeMaxTokens(
      shared("ai_max_tokens", tostring(DEFAULT_MAX_TOKENS)),
      DEFAULT_MAX_TOKENS
    )
    local migrated = false
    for _, modelConfig in ipairs(decoded) do
      if type(modelConfig) == "table" then
        local contextLength, maxTokens = normalizeModelLimits(
          modelConfig.contextLength,
          modelConfig.maxTokens,
          legacyContextLength,
          legacyMaxTokens
        )
        if contextLength ~= modelConfig.contextLength or maxTokens ~= modelConfig.maxTokens then migrated = true end
        modelConfig.contextLength = contextLength
        modelConfig.maxTokens = maxTokens
      end
    end
    modelsCache = decoded
    if attachProviders(modelsCache) or migrated then _M.saveModels(modelsCache) end
    return modelsCache
  end
  modelsCache = {}
  return modelsCache
end

function _M.saveModels(models)
  modelsCache = models
  local encoded = encode(models)
  if encoded then persist(MODELS_KEY, encoded) end
end

function _M.getCurrentModelIndex()
  local idx = tonumber(shared(MODEL_INDEX_KEY, "0")) or 0
  local models = _M.loadModels()
  if idx < 1 or idx > #models then idx = 1 end
  if #models == 0 then idx = 0 end
  return idx
end

function _M.setCurrentModel(index)
  local models = _M.loadModels()
  if #models == 0 then index = 0
  elseif index < 1 or index > #models then index = 1 end
  persist(MODEL_INDEX_KEY, tostring(index))
end

function _M.getCurrentModelName()
  local models = _M.loadModels()
  local idx = _M.getCurrentModelIndex()
  if idx >= 1 and idx <= #models then
    return models[idx].name
  end
  return ""
end

function _M.getCurrentModelConfig()
  local models = _M.loadModels()
  local index = _M.getCurrentModelIndex()
  return index >= 1 and resolvedModel(models[index]) or nil
end

function _M.findModel(providerId, modelId)
  modelId = _M.trim(modelId)
  for index, model in ipairs(_M.loadModels()) do
    if model.providerId == providerId and model.model == modelId then
      return model, index
    end
  end
end

function _M.countModels(providerId)
  local count = 0
  for _, model in ipairs(_M.loadModels()) do
    if model.providerId == providerId then count = count + 1 end
  end
  return count
end

local function appendModel(models, name, providerId, modelId, responses, contextLength, maxTokens)
  contextLength, maxTokens = normalizeModelLimits(
    contextLength, maxTokens, DEFAULT_CONTEXT_LENGTH, DEFAULT_MAX_TOKENS
  )
  name, modelId = _M.trim(name), _M.trim(modelId)
  models[#models + 1] = {
    name = name ~= "" and name or modelId,
    providerId = providerId,
    model = modelId,
    responses = responses == true,
    contextLength = contextLength,
    maxTokens = maxTokens,
  }
  return #models
end

function _M.addModel(name, providerId, model, responses, contextLength, maxTokens)
  local models = _M.loadModels()
  local index = appendModel(models, name, providerId, model, responses, contextLength, maxTokens)
  _M.saveModels(models)
  return index
end

function _M.addModels(providerId, ids, responses, contextLength, maxTokens)
  local models = _M.loadModels()
  local indexes = {}
  for _, modelId in ipairs(ids or {}) do
    modelId = _M.trim(modelId)
    if modelId ~= "" and not _M.findModel(providerId, modelId) then
      indexes[#indexes + 1] = appendModel(models, modelId, providerId, modelId, responses, contextLength, maxTokens)
    end
  end
  if #indexes > 0 then _M.saveModels(models) end
  return indexes
end

function _M.updateModel(index, name, providerId, model, responses, contextLength, maxTokens)
  local models = _M.loadModels()
  if index >= 1 and index <= #models then
    contextLength, maxTokens = normalizeModelLimits(
      contextLength, maxTokens, DEFAULT_CONTEXT_LENGTH, DEFAULT_MAX_TOKENS
    )
    name, model = _M.trim(name), _M.trim(model)
    models[index] = {
      name = name ~= "" and name or model,
      providerId = providerId,
      model = model,
      responses = responses == true,
      contextLength = contextLength,
      maxTokens = maxTokens,
    }
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

function _M.removeProvider(id)
  local providers = _M.loadProviders()
  local removed = false
  for index, provider in ipairs(providers) do
    if provider.id == id then
      table.remove(providers, index)
      removed = true
      break
    end
  end
  if not removed then return false end
  _M.saveProviders(providers)
  local models = _M.loadModels()
  local current = _M.getCurrentModelIndex()
  local kept, removedBefore, removedCurrent = {}, 0, false
  for index, model in ipairs(models) do
    if model.providerId == id then
      if index < current then removedBefore = removedBefore + 1
      elseif index == current then removedCurrent = true end
    else
      kept[#kept + 1] = model
    end
  end
  _M.saveModels(kept)
  if #kept == 0 then _M.setCurrentModel(0)
  elseif removedCurrent then _M.setCurrentModel(math.max(1, math.min(current - removedBefore, #kept)))
  else _M.setCurrentModel(math.max(1, current - removedBefore)) end
  return true
end

-- ─── 辅助模型路由 ──
-- 压缩摘要、标题生成等后台任务使用的轻量模型。
-- 以“供应商 ID + 模型 ID”的身份方式存储而非索引：删除/重排模型后
-- 引用自然失效并回退主模型，不会静默漂移指向其他模型。

local AUX_PROVIDER_KEY = "ai_aux_provider_id"
local AUX_MODEL_KEY = "ai_aux_model_id"

local function auxIdentity()
  return tostring(shared(AUX_PROVIDER_KEY, "")), tostring(shared(AUX_MODEL_KEY, ""))
end

function _M.getAuxModelIndex()
  local providerId, modelId = auxIdentity()
  if providerId == "" or modelId == "" then return 0 end
  local _, index = _M.findModel(providerId, modelId)
  return index or 0
end

function _M.setAuxModelIndex(index)
  index = tonumber(index) or 0
  local model = index >= 1 and _M.loadModels()[index] or nil
  if model and model.providerId and model.model and model.model ~= "" then
    persist(AUX_PROVIDER_KEY, tostring(model.providerId))
    persist(AUX_MODEL_KEY, tostring(model.model))
  else
    persist(AUX_PROVIDER_KEY, "")
    persist(AUX_MODEL_KEY, "")
  end
end

--- 辅助模型配置（含供应商 url/key 解析）；未配置或引用失效返回 nil
function _M.getAuxModelConfig()
  local idx = _M.getAuxModelIndex()
  if idx < 1 then return nil end
  return resolvedModel(_M.loadModels()[idx])
end

return _M
