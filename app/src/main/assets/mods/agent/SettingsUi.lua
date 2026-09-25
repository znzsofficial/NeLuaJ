--- 供应商 / 模型 / AI 设置的对话框集合：从 ChatUI 原样抽出（零行为改动）。
--- 依赖方向：本模块只 require AgentChat / MCPClient，不引用 ChatUI；
--- 模型标签刷新经 configure 注入回调。宿主装配处：
---   local SettingsUi = require("mods.agent.SettingsUi")
---   SettingsUi.configure({ updateModelLabel = ... })
local _M = {}

local AgentChat = require("mods.agent.AgentChat")
local MCPClient = require("mods.agent.MCPClient")

local ColorStateList = luajava.bindClass("android.content.res.ColorStateList")
local MaterialAlertDialogBuilder = luajava.bindClass("com.google.android.material.dialog.MaterialAlertDialogBuilder")
local MaterialButton = luajava.bindClass("com.google.android.material.button.MaterialButton")
local MaterialCardView = luajava.bindClass("com.google.android.material.card.MaterialCardView")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local ScrollView = luajava.bindClass("android.widget.ScrollView")
local EditText = luajava.bindClass("android.widget.EditText")
local GradientDrawable = luajava.bindClass("android.graphics.drawable.GradientDrawable")
local Typeface = luajava.bindClass("android.graphics.Typeface")
local Switch = luajava.bindClass("com.google.android.material.materialswitch.MaterialSwitch")

local ColorUtil = this.themeUtil
local ColorPrimary = ColorUtil.primary.main
local ColorOnPrimary = ColorUtil.primary.on
local ColorSecondaryContainer = ColorUtil.secondary.container
local ColorOnSecondaryContainer = ColorUtil.secondary.onContainer
local ColorOnSurface = ColorUtil.surface.on
local ColorText = ColorUtil.surface.onVariant
local ColorSurface = ColorUtil.surface.container
local ColorSurfaceContainerHigh = ColorUtil.surface.containerHigh
local ColorError = ColorUtil.error.main
local ColorErrorContainer = ColorUtil.error.container
local ColorOnErrorContainer = ColorUtil.error.onContainer

local res = res
local S = res.string

local injected = {}
local updateModelLabel = function() end

function _M.configure(options)
  options = options or {}
  if options.updateModelLabel then updateModelLabel = options.updateModelLabel end
end

local showProviderEditor, showModelEditor, showFetchedModels, showProviderManager
local showModelPicker, showModelManager, showSettings

local function fieldText(view)
  return tostring(view and view.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
end

local function fetchError(kind, detail)
  if kind == "need_key" then return S.ai_need_api_key end
  if kind == "need_url" then return S.ai_need_url end
  if kind == "empty" then return S.ai_fetch_models_empty end
  if kind == "unsupported" then return S.ai_balance_unsupported end
  return tostring(detail or kind or "")
end

local function formatBalance(parsed)
  if type(parsed) ~= "table" then return nil end
  if parsed.kind == "deepseek" then
    local lines = {}
    for _, info in ipairs(parsed.infos or {}) do
      lines[#lines + 1] = S.ai_balance_deepseek:format(info.currency, info.total, info.topped_up, info.granted)
    end
    if parsed.available == false then lines[#lines + 1] = S.ai_balance_unavailable end
    return #lines > 0 and table.concat(lines, "\n") or nil
  end
  if parsed.kind == "siliconflow" then
    return S.ai_balance_siliconflow:format(parsed.total, parsed.charge, parsed.gift)
  end
  if parsed.kind == "moonshot" then
    return S.ai_balance_moonshot:format(parsed.available, parsed.cash, parsed.voucher)
  end
  if parsed.kind == "openrouter" then
    return S.ai_balance_openrouter:format(parsed.remaining, parsed.total, parsed.used)
  end
  if parsed.kind == "subscription" then
    return S.ai_balance_subscription:format(parsed.amount)
  end
end

local function queryBalance(url, key, onDone)
  AgentChat.fetchBalance(url, key, function(ok, payload, detail)
    if onDone then onDone() end
    if not ok then
      print(fetchError(payload, detail))
      return
    end
    local text = formatBalance(payload)
    if not text then
      print(S.ai_balance_unsupported)
      return
    end
    MaterialAlertDialogBuilder(activity)
      .setTitle(S.ai_balance_title)
      .setMessage(text)
      .setPositiveButton(S.ai_ok, nil)
      .show()
  end)
end

local function fetchModels(url, key, onDone, onIds)
  AgentChat.fetchProviderModels(url, key, function(ok, payload, detail)
    if onDone then onDone() end
    if not ok then
      print(fetchError(payload, detail))
      return
    end
    onIds(payload)
  end)
end

local function providerLabel(provider)
  if not provider then return S.ai_missing_provider end
  local name = provider.name ~= "" and provider.name or provider.url
  return name
end

showFetchedModels = function(ids, ensureProvider)
  local rows = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    padding = "8dp",
  }
  for index, modelId in ipairs(ids) do
    rows[#rows + 1] = {
      MaterialCheckBox,
      id = "pick" .. index,
      text = modelId,
      layout_width = "match",
      layout_height = "wrap",
    }
  end
  local dialogViews = {}
  local content = loadlayout({
    ScrollView,
    layout_width = "match",
    layout_height = "360dp",
    rows,
  }, dialogViews)
  MaterialAlertDialogBuilder(activity)
    .setTitle(S.ai_pick_models)
    .setView(content)
    .setPositiveButton(S.ai_add, function()
      local provider = ensureProvider and ensureProvider() or nil
      if not provider then return end
      local selected = {}
      for index, modelId in ipairs(ids) do
        local box = dialogViews["pick" .. index]
        if box and box.isChecked() and not AgentChat.findModel(provider.id, modelId) then
          selected[#selected + 1] = modelId
        end
      end
      if #selected == 0 then
        print(S.ai_select_one)
        return
      end
      local indexes = AgentChat.addModels(provider.id, selected)
      if #indexes == 0 then
        print(S.ai_fetch_models_empty)
        return
      end
      if AgentChat.getCurrentModelIndex() == 0 then
        AgentChat.setCurrentModel(indexes[1])
      end
      updateModelLabel()
      print(S.ai_fetch_models_ok:format(#indexes))
      showModelPicker()
    end)
    .setNegativeButton(S.ai_cancel, nil)
    .show()
end

showProviderEditor = function(existing, onSaved)
  local providerId = existing and existing.id or nil
  local inputLayout = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    padding = "16dp",
    {
      MaterialTextView,
      text = S.ai_name,
      textSize = "14sp", textStyle = "bold", textColor = ColorOnSurface,
    },
    {
      EditText, id = "nameInput",
      layout_width = "match", layout_height = "wrap", minHeight = "48dp",
      textSize = "14sp", singleLine = true, hint = "DeepSeek",
      layout_marginTop = "8dp",
    },
    {
      MaterialTextView,
      text = S.ai_api_key,
      textSize = "14sp", textStyle = "bold", textColor = ColorOnSurface,
      layout_marginTop = "12dp",
    },
    {
      EditText, id = "keyInput",
      layout_width = "match", layout_height = "wrap", minHeight = "48dp",
      textSize = "14sp", singleLine = true, hint = "sk-...",
      layout_marginTop = "8dp",
    },
    {
      MaterialTextView,
      text = S.ai_api_url,
      textSize = "14sp", textStyle = "bold", textColor = ColorOnSurface,
      layout_marginTop = "12dp",
    },
    {
      EditText, id = "urlInput",
      layout_width = "match", layout_height = "wrap", minHeight = "48dp",
      textSize = "14sp", singleLine = true,
      hint = "https://api.deepseek.com/v1",
      layout_marginTop = "8dp",
    },
    {
      MaterialButton, id = "fetchButton",
      text = S.ai_fetch_models,
      textSize = "13sp",
      layout_width = "match", layout_marginTop = "12dp",
      includeFontPadding = false,
      BackgroundTintList = ColorStateList.valueOf(ColorPrimary),
      textColor = ColorOnPrimary,
    },
    {
      MaterialButton, id = "balanceButton",
      text = S.ai_fetch_balance,
      textSize = "13sp",
      layout_width = "match", layout_marginTop = "8dp",
      includeFontPadding = false,
      BackgroundTintList = ColorStateList.valueOf(ColorSecondaryContainer),
      textColor = ColorOnSecondaryContainer,
    },
  }
  local dialogViews = {}
  local content = loadlayout({
    ScrollView,
    layout_width = "match",
    layout_height = "wrap",
    fillViewport = true,
    inputLayout,
  }, dialogViews)
  local function ensureProvider()
    local name = fieldText(dialogViews.nameInput)
    local key = fieldText(dialogViews.keyInput)
    local url = fieldText(dialogViews.urlInput)
    if key == "" then print(S.ai_need_api_key) return nil end
    if url == "" then print(S.ai_need_url) return nil end
    if providerId then AgentChat.updateProvider(providerId, name, url, key)
    else
      local provider = AgentChat.addProvider(name, url, key)
      providerId = provider.id
    end
    return AgentChat.findProvider(providerId)
  end
  MaterialAlertDialogBuilder(activity)
    .setTitle(existing and S.ai_edit_provider or S.ai_add_provider)
    .setView(content)
    .setPositiveButton(S.ai_save, function()
      local provider = ensureProvider()
      if not provider then return end
      print(S.ai_saved)
      if onSaved then onSaved(provider) else showProviderManager() end
    end)
    .setNegativeButton(S.ai_cancel, nil)
    .show()
  dialogViews.nameInput.setText(existing and existing.name or "")
  dialogViews.keyInput.setText(existing and existing.key or "")
  dialogViews.urlInput.setText(existing and existing.url or "")
  dialogViews.fetchButton.onClick = function()
    local url = fieldText(dialogViews.urlInput)
    local key = fieldText(dialogViews.keyInput)
    local button = dialogViews.fetchButton
    local previous = tostring(button.getText())
    button.setEnabled(false)
    button.setText(S.ai_fetching)
    fetchModels(url, key, function()
      pcall(function()
        button.setEnabled(true)
        button.setText(previous)
      end)
    end, function(ids)
      showFetchedModels(ids, ensureProvider)
    end)
  end
  dialogViews.balanceButton.onClick = function()
    local url = fieldText(dialogViews.urlInput)
    local key = fieldText(dialogViews.keyInput)
    local button = dialogViews.balanceButton
    local previous = tostring(button.getText())
    button.setEnabled(false)
    button.setText(S.ai_fetching)
    queryBalance(url, key, function()
      pcall(function()
        button.setEnabled(true)
        button.setText(previous)
      end)
    end)
  end
end

showProviderManager = function()
  local providers = AgentChat.loadProviders()
  if #providers == 0 then
    showProviderEditor()
    return
  end
  local labels = {}
  for index, provider in ipairs(providers) do
    labels[index] = providerLabel(provider) .. "  (" .. S.ai_model_count:format(AgentChat.countModels(provider.id)) .. ")"
  end
  MaterialAlertDialogBuilder(activity)
    .setTitle(S.ai_providers)
    .setItems(labels, function(_, which)
      local provider = providers[which + 1]
      local extra = AgentChat.countModels(provider.id) > 0
        and ("\n" .. S.ai_provider_models:format(AgentChat.countModels(provider.id)))
        or ""
      MaterialAlertDialogBuilder(activity)
        .setTitle(providerLabel(provider))
        .setMessage(S.ai_api_url .. ": " .. provider.url .. extra)
        .setPositiveButton(S.ai_edit, function()
          showProviderEditor(provider)
        end)
        .setNegativeButton(S.ai_delete, function()
          MaterialAlertDialogBuilder(activity)
            .setTitle(S.ai_delete)
            .setMessage(S.ai_confirm_delete_provider:format(providerLabel(provider))
              .. (AgentChat.countModels(provider.id) > 0
                and ("\n" .. S.ai_provider_models:format(AgentChat.countModels(provider.id)))
                or ""))
            .setPositiveButton(S.ai_delete, function()
              AgentChat.removeProvider(provider.id)
              print(S.ai_deleted_name:format(providerLabel(provider)))
              updateModelLabel()
              showProviderManager()
            end)
            .setNegativeButton(S.ai_cancel, nil)
            .show()
        end)
        .setNeutralButton(S.ai_fetch_balance, function()
          queryBalance(provider.url, provider.key)
        end)
        .show()
    end)
    .setPositiveButton(S.ai_add, function()
      showProviderEditor()
    end)
    .setNegativeButton(S.ai_close, nil)
    .show()
end

showModelEditor = function(existingIndex)
  local existing = existingIndex and AgentChat.loadModels()[existingIndex] or nil
  local providers = AgentChat.loadProviders()
  if #providers == 0 then
    showProviderEditor(nil, function() showModelEditor(existingIndex) end)
    return
  end
  local selectedId = existing and existing.providerId or providers[1].id
  if not AgentChat.findProvider(selectedId) then selectedId = providers[1].id end
  local inputLayout = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    padding = "16dp",
    {
      MaterialTextView,
      text = S.ai_name,
      textSize = "14sp", textStyle = "bold", textColor = ColorOnSurface,
    },
    {
      EditText, id = "nameInput",
      layout_width = "match", layout_height = "wrap", minHeight = "48dp",
      textSize = "14sp", singleLine = true, hint = "DeepSeek V4 Flash",
      layout_marginTop = "8dp",
    },
    {
      MaterialTextView,
      text = S.ai_provider,
      textSize = "14sp", textStyle = "bold", textColor = ColorOnSurface,
      layout_marginTop = "12dp",
    },
    {
      MaterialButton, id = "providerButton",
      textSize = "13sp",
      layout_width = "match", layout_marginTop = "8dp",
      includeFontPadding = false,
      BackgroundTintList = ColorStateList.valueOf(ColorSecondaryContainer),
      textColor = ColorOnSecondaryContainer,
    },
    {
      MaterialTextView,
      text = S.ai_model_params,
      textSize = "14sp", textStyle = "bold", textColor = ColorOnSurface,
      layout_marginTop = "12dp",
    },
    {
      EditText, id = "modelInput",
      layout_width = "match", layout_height = "wrap", minHeight = "48dp",
      textSize = "14sp", singleLine = true, hint = "deepseek-v4-flash",
      layout_marginTop = "8dp",
    },
    {
      MaterialButton, id = "fetchButton",
      text = S.ai_fetch_models,
      textSize = "13sp",
      layout_width = "match", layout_marginTop = "8dp",
      includeFontPadding = false,
      BackgroundTintList = ColorStateList.valueOf(ColorPrimary),
      textColor = ColorOnPrimary,
    },
    {
      MaterialTextView,
      text = S.ai_context_len,
      textSize = "13sp", textColor = ColorText,
      layout_marginTop = "12dp",
    },
    {
      EditText, id = "contextInput",
      layout_width = "match", layout_height = "wrap", minHeight = "44dp",
      textSize = "14sp", singleLine = true, inputType = 0x0002,
      hint = S.ai_ctx_hint,
    },
    {
      MaterialTextView,
      text = S.ai_max_tokens,
      textSize = "13sp", textColor = ColorText,
      layout_marginTop = "8dp",
    },
    {
      EditText, id = "maxTokensInput",
      layout_width = "match", layout_height = "wrap", minHeight = "44dp",
      textSize = "14sp", singleLine = true, inputType = 0x0002,
    },
    {
      Switch, id = "responsesSwitch",
      text = S.ai_use_responses,
      layout_width = "match", layout_height = "wrap",
      layout_marginTop = "12dp",
    },
  }

  local dialogViews = {}
  local content = loadlayout({
    ScrollView,
    layout_width = "match",
    layout_height = "wrap",
    fillViewport = true,
    inputLayout,
  }, dialogViews)

  MaterialAlertDialogBuilder(activity)
    .setTitle(existingIndex and S.ai_edit_model or S.ai_add_model)
    .setView(content)
    .setPositiveButton(S.ai_save, function()
      local name = fieldText(dialogViews.nameInput)
      local model = fieldText(dialogViews.modelInput)
      local contextLength = fieldText(dialogViews.contextInput)
      local maxTokens = fieldText(dialogViews.maxTokensInput)
      local responses = dialogViews.responsesSwitch.isChecked()
      if model == "" then
        print(S.ai_need_model)
        return
      end
      if not AgentChat.findProvider(selectedId) then
        print(S.ai_need_provider)
        return
      end
      if name == "" then name = model end
      if existingIndex then
        AgentChat.updateModel(existingIndex, name, selectedId, model, responses, contextLength, maxTokens)
        AgentChat.setCurrentModel(existingIndex)
      else
        local newIndex = AgentChat.addModel(name, selectedId, model, responses, contextLength, maxTokens)
        AgentChat.setCurrentModel(newIndex)
      end
      updateModelLabel()
      print(S.ai_saved)
      showModelPicker()
    end)
    .setNegativeButton(S.ai_cancel, nil)
    .show()

  local function refreshProviderButton()
    dialogViews.providerButton.setText(providerLabel(AgentChat.findProvider(selectedId)))
  end
  dialogViews.providerButton.onClick = function()
    local labels = {}
    for index, provider in ipairs(providers) do
      labels[index] = providerLabel(provider)
    end
    MaterialAlertDialogBuilder(activity)
      .setTitle(S.ai_provider)
      .setItems(labels, function(_, which)
        selectedId = providers[which + 1].id
        refreshProviderButton()
      end)
      .setNeutralButton(S.ai_providers, function()
        showProviderManager()
      end)
      .setNegativeButton(S.ai_cancel, nil)
      .show()
  end
  dialogViews.fetchButton.onClick = function()
    local provider = AgentChat.findProvider(selectedId)
    if not provider then
      print(S.ai_need_provider)
      return
    end
    local button = dialogViews.fetchButton
    local previous = tostring(button.getText())
    button.setEnabled(false)
    button.setText(S.ai_fetching)
    fetchModels(provider.url, provider.key, function()
      pcall(function()
        button.setEnabled(true)
        button.setText(previous)
      end)
    end, function(ids)
      MaterialAlertDialogBuilder(activity)
        .setTitle(S.ai_pick_model)
        .setItems(ids, function(_, which)
          dialogViews.modelInput.setText(ids[which + 1])
          if fieldText(dialogViews.nameInput) == "" then
            dialogViews.nameInput.setText(ids[which + 1])
          end
        end)
        .setNegativeButton(S.ai_cancel, nil)
        .show()
    end)
  end
  dialogViews.nameInput.setText(existing and existing.name or "")
  dialogViews.modelInput.setText(existing and existing.model or "")
  dialogViews.contextInput.setText(tostring(existing and existing.contextLength or 30000))
  dialogViews.maxTokensInput.setText(tostring(existing and existing.maxTokens or 4096))
  dialogViews.responsesSwitch.setChecked(existing and existing.responses == true)
  refreshProviderButton()
end

showModelManager = function()
  local models = AgentChat.loadModels()
  if #models == 0 then
    showModelEditor()
    return
  end

  local labels = {}
  for i, m in ipairs(models) do
    labels[i] = m.name .. "  (" .. m.model .. ") · " .. providerLabel(AgentChat.findProvider(m.providerId))
  end

  MaterialAlertDialogBuilder(activity)
    .setTitle(S.ai_manage_model)
    .setItems(labels, function(_, which)
      local m = models[which + 1]
      local provider = AgentChat.findProvider(m.providerId)
      MaterialAlertDialogBuilder(activity)
        .setTitle(m.name)
        .setMessage(S.ai_provider .. ": " .. providerLabel(provider) .. "\n"
          .. S.ai_model .. ": " .. m.model .. "\n"
          .. S.ai_context_len .. ": " .. tostring(m.contextLength or 30000) .. "\n"
          .. S.ai_max_tokens .. ": " .. tostring(m.maxTokens or 4096))
        .setPositiveButton(S.ai_edit, function()
          showModelEditor(which + 1)
        end)
        .setNegativeButton(S.ai_delete, function()
          AgentChat.removeModel(which + 1)
          print(S.ai_deleted_name:format(m.name))
          updateModelLabel()
          showModelManager()
        end)
        .setNeutralButton(provider and S.ai_fetch_balance or S.ai_cancel, function()
          if provider then queryBalance(provider.url, provider.key) end
        end)
        .show()
    end)
    .setPositiveButton(S.ai_add, function()
      showModelEditor()
    end)
    .setNeutralButton(S.ai_providers, function()
      showProviderManager()
    end)
    .setNegativeButton(S.ai_close, nil)
    .show()
end

showModelPicker = function()
  local models = AgentChat.loadModels()
  local current = AgentChat.getCurrentModelIndex()

  if #models == 0 then
    showModelEditor()
    return
  end

  local labels = {}
  for i, m in ipairs(models) do
    local marker = (i == current) and " ✓ " or "    "
    labels[i] = marker .. m.name .. "  (" .. m.model .. ") · " .. providerLabel(AgentChat.findProvider(m.providerId))
  end
  labels[#labels + 1] = S.ai_add_model_item

  MaterialAlertDialogBuilder(activity)
    .setTitle(S.ai_switch_model)
    .setItems(labels, function(_, which)
      if which == #models then
        showModelEditor()
      else
        AgentChat.setCurrentModel(which + 1)
        updateModelLabel()
        print(S.ai_switched_to:format(models[which + 1].name))
      end
    end)
    .setNegativeButton(S.ai_manage, function()
      showModelManager()
    end)
    .setNeutralButton(S.ai_providers, function()
      showProviderManager()
    end)
    .setPositiveButton(S.ai_close, nil)
    .show()
end

showSettings = function()
  local autoApprove = this.getSharedData("ai_auto_approve", "0") == "1"

  local autoApproveNetwork = this.getSharedData("ai_auto_approve_network", "1") == "1"

  local projectPolicy = AgentChat.getProjectPolicy and AgentChat.getProjectPolicy() or nil
  local policyRestricted = type(projectPolicy) == "table" and projectPolicy.autoApprove == false
  local policyHosts = ""
  if type(projectPolicy) == "table" and type(projectPolicy.networkHosts) == "table" then
    policyHosts = table.concat(projectPolicy.networkHosts, " ")
  end
  local autoRunSandbox = this.getSharedData("ai_auto_run_sandbox", "1") == "1"
  local allowSelfSigned = this.getSharedData("ai_allow_selfsigned", "0") == "1"
  local temp = this.getSharedData("ai_temperature", "0.7")
  local retryCount = this.getSharedData("ai_retry_count", "2")
  local systemPrompt = this.getSharedData("ai_system_prompt", "")
  local dlgViews = {}
  local settingsDialog
  local mcpRenderGeneration = 0

  local function sectionTitle(text)
    return {
      MaterialTextView,
      text = text,
      textSize = "13sp", textStyle = "bold", textColor = ColorPrimary,
      layout_marginBottom = "8dp",
    }
  end

  local body = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    padding = "16dp",
    -- 生成参数
    {
      MaterialCardView,
      layout_width = "match",
      layout_height = "wrap",
      layout_marginBottom = "12dp",
      CardBackgroundColor = ColorSurface,
      CardElevation = 0,
      {
        LinearLayout,
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        padding = "16dp",
        sectionTitle(S.ai_gen_params),
        {
          MaterialTextView,
          text = S.ai_temperature,
          textSize = "13sp", textColor = ColorText,
        },
        {
          EditText,
          id = "tempInput",
          text = tostring(temp),
          layout_width = "match", layout_height = "wrap", minHeight = "40dp",
          textSize = "14sp", singleLine = true,
          inputType = 0x2002,
          layout_marginBottom = "8dp",
        },
        {
          MaterialTextView,
          text = S.ai_retry_count_label,
          textSize = "13sp", textColor = ColorText,
        },
        {
          EditText,
          id = "retryInput",
          text = tostring(retryCount),
          layout_width = "match", layout_height = "wrap", minHeight = "40dp",
          textSize = "14sp", singleLine = true,
          inputType = 0x0002,
          hint = S.ai_retry_hint,
        },
        {
          MaterialTextView,
          text = S.ai_aux_model,
          textSize = "13sp", textColor = ColorText,
          layout_marginTop = "12dp",
        },
        {
          MaterialTextView,
          text = S.ai_aux_model_desc,
          textSize = "11sp", textColor = ColorText,
        },
        {
          MaterialTextView,
          id = "auxModelValue",
          textSize = "14sp", textColor = ColorPrimary,
          padding = "8dp",
        },
      },
    },
    -- 行为
    {
      MaterialCardView,
      layout_width = "match",
      layout_height = "wrap",
      layout_marginBottom = "12dp",
      CardBackgroundColor = ColorSurface,
      CardElevation = 0,
      {
        LinearLayout,
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        padding = "16dp",
        sectionTitle(S.ai_security),
        {
          MaterialTextView,
          text = S.ai_security_desc,
          textSize = "12sp", textColor = ColorText,
          layout_marginBottom = "10dp",
        },
        {
          LinearLayout,
          orientation = "horizontal",
          gravity = "center_vertical",
          layout_width = "match",
          layout_height = "wrap",
          {
            LinearLayout,
            orientation = "vertical",
            layout_width = "0dp",
            layout_weight = 1,
            {
              MaterialTextView,
              text = S.ai_auto_run_sandbox,
              textSize = "14sp", textColor = ColorOnSurface,
            },
            {
              MaterialTextView,
              text = S.ai_auto_run_sandbox_desc,
              textSize = "12sp", textColor = ColorText,
              layout_marginTop = "2dp",
            },
          },
          {
            Switch,
            id = "autoRunSandboxSwitch",
            checked = autoRunSandbox,
            layout_marginLeft = "12dp",
          },
        },
        {
          LinearLayout,
          orientation = "horizontal",
          gravity = "center_vertical",
          layout_width = "match",
          layout_height = "wrap",
          layout_marginTop = "12dp",
          {
            LinearLayout,
            orientation = "vertical",
            layout_width = "0dp",
            layout_weight = 1,
            {
              MaterialTextView,
              text = S.ai_auto_approve_network,
              textSize = "14sp", textColor = ColorOnSurface,
            },
            {
              MaterialTextView,
              text = S.ai_auto_approve_network_desc,
              textSize = "12sp", textColor = ColorText,
              layout_marginTop = "2dp",
            },
          },
          {
            Switch,
            id = "autoApproveNetworkSwitch",
            checked = autoApproveNetwork,
            layout_marginLeft = "12dp",
          },
        },
        {
          LinearLayout,
          orientation = "horizontal",
          gravity = "center_vertical",
          layout_width = "match",
          layout_height = "wrap",
          layout_marginTop = "12dp",
          {
            LinearLayout,
            orientation = "vertical",
            layout_width = "0dp",
            layout_weight = 1,
            {
              MaterialTextView,
              text = S.ai_auto_approve,
              textSize = "14sp", textColor = ColorOnSurface,
            },
            {
              MaterialTextView,
              text = S.ai_auto_approve_desc,
              textSize = "12sp", textColor = ColorText,
              layout_marginTop = "2dp",
            },
          },
          {
            Switch,
            id = "autoApproveSwitch",
            checked = autoApprove,
            layout_marginLeft = "12dp",
          },
        },
        {
          LinearLayout,
          orientation = "horizontal",
          gravity = "center_vertical",
          layout_width = "match",
          layout_height = "wrap",
          layout_marginTop = "12dp",
          {
            LinearLayout,
            orientation = "vertical",
            layout_width = "0dp",
            layout_weight = 1,
            {
              MaterialTextView,
              text = S.ai_self_signed,
              textSize = "14sp", textColor = ColorOnSurface,
            },
            {
              MaterialTextView,
              text = S.ai_self_signed_desc,
              textSize = "12sp", textColor = ColorText,
              layout_marginTop = "2dp",
            },
          },
          {
            Switch,
            id = "selfSignedSwitch",
            checked = allowSelfSigned,
            layout_marginLeft = "12dp",
          },
        },
      },
    },
    -- 当前工程策略（只能收紧全局授权）
    {
      MaterialCardView,
      layout_width = "match",
      layout_height = "wrap",
      layout_marginBottom = "12dp",
      CardBackgroundColor = ColorSurface,
      CardElevation = 0,
      {
        LinearLayout,
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        padding = "16dp",
        sectionTitle(S.ai_policy_project),
        {
          LinearLayout,
          orientation = "horizontal",
          gravity = "center_vertical",
          layout_width = "match",
          layout_height = "wrap",
          {
            LinearLayout,
            orientation = "vertical",
            layout_width = "0dp",
            layout_weight = 1,
            {
              MaterialTextView,
              text = S.ai_policy_restrict,
              textSize = "14sp", textColor = ColorOnSurface,
            },
            {
              MaterialTextView,
              text = S.ai_policy_restrict_desc,
              textSize = "12sp", textColor = ColorText,
              layout_marginTop = "2dp",
            },
          },
          {
            Switch,
            id = "policyRestrictSwitch",
            checked = policyRestricted,
            layout_marginLeft = "12dp",
          },
        },
        {
          MaterialTextView,
          text = S.ai_policy_hosts,
          textSize = "14sp", textColor = ColorOnSurface,
          layout_marginTop = "12dp",
          layout_marginBottom = "2dp",
        },
        {
          MaterialTextView,
          text = S.ai_policy_hosts_desc,
          textSize = "12sp", textColor = ColorText,
          layout_marginBottom = "4dp",
        },
        {
          EditText,
          id = "policyHostsInput",
          text = policyHosts,
          layout_width = "match", layout_height = "wrap",
          textSize = "13sp", minLines = 1, maxLines = 4,
          hint = "api.example.com docs.example.org",
        },
      },
    },
    -- 系统提示词
    {
      MaterialCardView,
      layout_width = "match",
      layout_height = "wrap",
      layout_marginBottom = "12dp",
      CardBackgroundColor = ColorSurface,
      CardElevation = 0,
      {
        LinearLayout,
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        padding = "16dp",
        sectionTitle(S.ai_advanced),
        {
          MaterialTextView,
          text = S.ai_system_prompt,
          textSize = "14sp", textColor = ColorOnSurface,
          layout_marginBottom = "2dp",
        },
        {
          MaterialTextView,
          text = S.ai_sys_prompt_desc,
          textSize = "12sp", textColor = ColorText,
          layout_marginBottom = "4dp",
        },
        {
          EditText,
          id = "promptInput",
          text = systemPrompt,
          layout_width = "match", layout_height = "wrap",
          textSize = "13sp", minLines = 3, maxLines = 6,
          gravity = "top",
        },
      },
    },
    -- MCP 服务器
    {
      MaterialCardView,
      layout_width = "match",
      layout_height = "wrap",
      layout_marginBottom = "12dp",
      CardBackgroundColor = ColorSurface,
      CardElevation = 0,
      {
        LinearLayout,
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        padding = "16dp",
        sectionTitle(S.ai_mcp_servers),
        {
          MaterialTextView,
          text = S.ai_mcp_desc,
          textSize = "12sp", textColor = ColorText,
          layout_marginBottom = "6dp",
        },
        {
          LinearLayout,
          id = "mcpList",
          orientation = "vertical",
          layout_width = "match",
          layout_height = "wrap",
        },
        {
          MaterialButton,
          id = "btnAddMcp",
          text = S.ai_add_mcp,
          textSize = "13sp",
          layout_width = "match",
          layout_marginTop = "8dp",
          includeFontPadding = false,
          BackgroundTintList = ColorStateList.valueOf(ColorPrimary),
          textColor = ColorOnPrimary,
        },
        {
          LinearLayout,
          orientation = "horizontal",
          layout_width = "match",
          layout_height = "wrap",
          layout_marginTop = "8dp",
          {
            MaterialButton,
            id = "btnAddCtx7",
            text = S.ai_add_ctx7,
            textSize = "13sp",
            layout_width = "0dp", layout_weight = 1,
            layout_marginRight = "6dp",
            includeFontPadding = false,
            BackgroundTintList = ColorStateList.valueOf(ColorSecondaryContainer),
            textColor = ColorOnSecondaryContainer,
          },
          {
            MaterialButton,
            id = "btnAddDw",
            text = S.ai_add_dw,
            textSize = "13sp",
            layout_width = "0dp", layout_weight = 1,
            layout_marginLeft = "6dp",
            includeFontPadding = false,
            BackgroundTintList = ColorStateList.valueOf(ColorSecondaryContainer),
            textColor = ColorOnSecondaryContainer,
          },
        },
      },
    },
    {
      MaterialButton,
      id = "btnTestConn",
      text = S.ai_test_conn,
      textSize = "13sp",
      layout_width = "match",
      includeFontPadding = false,
      BackgroundTintList = ColorStateList.valueOf(ColorPrimary),
      textColor = ColorOnPrimary,
    },
  }

  local content = loadlayout({
    ScrollView,
    layout_width = "match",
    layout_height = "match",
    fillViewport = true,
    body,
  }, dlgViews)

  dlgViews.btnTestConn.onClick = function()
    AgentChat.testConnection(function(ok, msg)
      print(msg)
    end)
  end

  -- ─── MCP 服务器管理 ──

  local function renderMcpList()
    mcpRenderGeneration = mcpRenderGeneration + 1
    local renderGeneration = mcpRenderGeneration
    local mcpList = dlgViews.mcpList
    if not mcpList then return end
    mcpList.removeAllViews()
    local servers = MCPClient.getServers()
    for i, server in ipairs(servers) do
      local serverItem = server
      local sname = tostring(server.name or S.ai_unnamed)
      local surl = tostring(server.url or "")
      local row = LinearLayout(activity)
      row.setOrientation(1)
      row.setPadding(dp(12), dp(10), dp(12), dp(10))
      local lp = LinearLayout.LayoutParams(-1, -2)
      lp.bottomMargin = dp(8)
      row.setLayoutParams(lp)
      local bg = GradientDrawable()
      bg.setColor(ColorSurfaceContainerHigh)
      bg.setCornerRadius(dp(12))
      row.setBackground(bg)

      local txtCol = LinearLayout(activity)
      txtCol.setOrientation(1)
      txtCol.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
      local nameTv = MaterialTextView(activity)
      nameTv.setText(sname)
      nameTv.setTextSize(14)
      nameTv.setTypeface(Typeface.DEFAULT, 1)
      nameTv.setTextColor(ColorOnSurface)
      nameTv.setSingleLine(true)
      txtCol.addView(nameTv)
      local urlTv = MaterialTextView(activity)
      urlTv.setText(surl)
      urlTv.setTextSize(12)
      urlTv.setTextColor(ColorText)
      urlTv.setSingleLine(true)
      txtCol.addView(urlTv)
      local statusTv = MaterialTextView(activity)
      statusTv.setText("")
      statusTv.setTextSize(11)
      statusTv.setTextColor(ColorText)
      statusTv.setVisibility(GONE)
      txtCol.addView(statusTv)
      row.addView(txtCol)

      local function mcpBtn(text, bgColor, textColor)
        local btn = MaterialButton(activity)
        btn.setText(text)
        btn.setTextSize(12)
        btn.setAllCaps(false)
        btn.setMinWidth(0)
        btn.setMinHeight(0)
        btn.setPadding(dp(14), 0, dp(14), 0)
        btn.setBackgroundTintList(ColorStateList.valueOf(bgColor))
        btn.setTextColor(textColor)
        return btn
      end

      local actions = LinearLayout(activity)
      actions.setOrientation(0)
      actions.setGravity(5) -- Gravity.RIGHT
      local actionsLp = LinearLayout.LayoutParams(-1, -2)
      actionsLp.topMargin = dp(8)
      actions.setLayoutParams(actionsLp)

      local testBtn = mcpBtn(S.ai_test, ColorSecondaryContainer, ColorOnSecondaryContainer)
      local testLp = LinearLayout.LayoutParams(-2, dp(34))
      testLp.rightMargin = dp(8)
      testBtn.setLayoutParams(testLp)
      testBtn.setOnClickListener(function()
        testBtn.setEnabled(false)
        testBtn.setText(S.ai_mcp_testing)
        statusTv.setText(S.ai_mcp_testing)
        statusTv.setTextColor(ColorText)
        statusTv.setVisibility(VISIBLE)
        MCPClient.testServerAsync(serverItem, function(ok, msg)
          if renderGeneration ~= mcpRenderGeneration
              or not settingsDialog or not settingsDialog.isShowing() then return end
          pcall(function()
            testBtn.setEnabled(true)
            testBtn.setText(S.ai_test)
            statusTv.setText(ok and S.ai_mcp_connected or S.ai_mcp_failed)
            statusTv.setTextColor(ok and ColorPrimary or ColorError)
            local feedback = tostring(msg or (ok and S.ai_mcp_connected or S.ai_mcp_failed))
            print(sname .. ": " .. feedback)
          end)
        end)
      end)
      actions.addView(testBtn)

      local delBtn = mcpBtn(S.ai_delete, ColorErrorContainer, ColorOnErrorContainer)
      local delLp = LinearLayout.LayoutParams(-2, dp(34))
      delBtn.setLayoutParams(delLp)
      delBtn.setOnClickListener(function()
        local compact = {}
        for idx, s in ipairs(servers) do
          if idx ~= i then compact[#compact + 1] = s end
        end
        MCPClient.setServers(compact)
        MCPClient.refreshToolsAsync()
        renderMcpList()
      end)
      actions.addView(delBtn)
      row.addView(actions)
      mcpList.addView(row)
    end
  end

  dlgViews.btnAddMcp.onClick = function()
    local inViews = {}
    local form = {
      LinearLayout,
      orientation = "vertical",
      padding = "20dp",
      {
        EditText,
        id = "nameInput",
        hint = S.ai_name_hint,
        layout_width = "match", layout_height = "wrap", minHeight = "42dp",
        textSize = "14sp", singleLine = true,
      },
      {
        EditText,
        id = "urlInput",
        hint = S.ai_url_hint,
        layout_width = "match", layout_height = "wrap", minHeight = "42dp",
        textSize = "14sp", singleLine = true,
        layout_marginTop = "8dp",
      },
      {
        EditText,
        id = "headerInput",
        hint = S.ai_headers_hint,
        layout_width = "match", layout_height = "wrap",
        textSize = "13sp", minLines = 2, maxLines = 4,
        gravity = "top",
        layout_marginTop = "8dp",
      },
    }
    local formContent = loadlayout({
      ScrollView, layout_width = "match", layout_height = "wrap", fillViewport = true,
      form,
    }, inViews)
    local addDialog = MaterialAlertDialogBuilder(activity)
      .setTitle(S.ai_add_mcp)
      .setView(formContent)
      .setPositiveButton(S.ai_ok, nil)
      .setNegativeButton(S.ai_cancel, nil)
      .create()
    addDialog.setOnShowListener(function()
      local positive = addDialog.getButton(DialogInterface.BUTTON_POSITIVE)
      if not positive then return end
      positive.onClick = function()
        local sname = tostring(inViews.nameInput.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
        local surl = tostring(inViews.urlInput.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
        local sheaders = tostring(inViews.headerInput.getText() or "")
        if sname == "" or surl == "" then
          print(S.ai_name_url_required)
          return
        end
        local headers = {}
        for line in sheaders:gmatch("[^\r\n]+") do
          local k, v = line:match("^%s*([^:%s]+)%s*:%s*(.*)%s*$")
          if k then headers[k] = v end
        end
        local valid = MCPClient.validateServer({ url = surl, headers = headers })
        if not valid then
          print(S.ai_mcp_url_invalid)
          return
        end
        local servers = MCPClient.getServers()
        servers[#servers + 1] = { name = sname, url = surl, headers = headers }
        MCPClient.setServers(servers)
        MCPClient.refreshToolsAsync()
        renderMcpList()
        addDialog.dismiss()
      end
    end)
    addDialog.show()
  end

  local function addPresetServer(name, url)
    local servers = MCPClient.getServers()
    for _, s in ipairs(servers) do
      if tostring(s.name or "") == name then
        print(S.ai_exists:format(name))
        return
      end
    end
    servers[#servers + 1] = { name = name, url = url, headers = {} }
    MCPClient.setServers(servers)
    MCPClient.refreshToolsAsync()
    renderMcpList()
  end

  dlgViews.btnAddCtx7.onClick = function()
    addPresetServer("context7", "https://mcp.context7.com/mcp")
  end
  dlgViews.btnAddDw.onClick = function()
    addPresetServer("deepwiki", "https://mcp.deepwiki.com/mcp")
  end

  local function renderAuxModelValue()
    if not dlgViews.auxModelValue then return end
    local models = AgentChat.loadModels()
    local idx = AgentChat.getAuxModelIndex()
    if idx >= 1 and models[idx] then
      dlgViews.auxModelValue.setText(S.ai_aux_model_set:format(models[idx].name))
    else
      dlgViews.auxModelValue.setText(S.ai_aux_model_follow)
    end
  end
  renderAuxModelValue()

  dlgViews.auxModelValue.onClick = function()
    local models = AgentChat.loadModels()
    if #models == 0 then
      print(S.ai_need_config)
      return
    end
    local currentAux = AgentChat.getAuxModelIndex()
    local labels = {}
    for i, m in ipairs(models) do
      local marker = (i == currentAux) and " ✓ " or "    "
      labels[i] = marker .. m.name .. "  (" .. m.model .. ")"
    end
    labels[#labels + 1] = "    " .. S.ai_aux_model_clear
    MaterialAlertDialogBuilder(activity)
      .setTitle(S.ai_aux_model)
      .setItems(labels, function(_, which)
        if which == #models then
          AgentChat.setAuxModelIndex(0)
        else
          AgentChat.setAuxModelIndex(which + 1)
        end
        renderAuxModelValue()
      end)
      .setNegativeButton(S.ai_close, nil)
      .show()
  end

  renderMcpList()

  settingsDialog = MaterialAlertDialogBuilder(activity)
    .setTitle(S.ai_settings)
    .setView(content)
    .setPositiveButton(S.ai_ok, function()
      this.setSharedData("ai_auto_approve", dlgViews.autoApproveSwitch.isChecked() and "1" or "0")
      this.setSharedData("ai_auto_approve_network", dlgViews.autoApproveNetworkSwitch.isChecked() and "1" or "0")
      this.setSharedData("ai_auto_run_sandbox", dlgViews.autoRunSandboxSwitch.isChecked() and "1" or "0")
      this.setSharedData("ai_allow_selfsigned", dlgViews.selfSignedSwitch.isChecked() and "1" or "0")
      local tempVal = tostring(dlgViews.tempInput.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
      local retryVal = tostring(dlgViews.retryInput.getText() or ""):gsub("^%s*(.-)%s*$", "%1")
      local promptVal = tostring(dlgViews.promptInput.getText() or "")
      if tempVal ~= "" then this.setSharedData("ai_temperature", tempVal) end
      if retryVal ~= "" then this.setSharedData("ai_retry_count", retryVal) end
      this.setSharedData("ai_system_prompt", promptVal)
      if dlgViews.policyRestrictSwitch and dlgViews.policyHostsInput then
        local hosts = {}
        local hostsRaw = tostring(dlgViews.policyHostsInput.getText() or "")
        for token in hostsRaw:gmatch("[^,;%s]+") do hosts[#hosts + 1] = token end
        pcall(function()
          AgentChat.saveProjectPolicy({
            autoApprove = not dlgViews.policyRestrictSwitch.isChecked(),
            networkHosts = hosts,
          })
        end)
      end
      print(S.ai_settings_saved)
    end)
    .setNegativeButton(S.ai_cancel, nil)
    .show()
  settingsDialog.setOnDismissListener(function()
    mcpRenderGeneration = mcpRenderGeneration + 1
  end)
end

-- 公开入口：ChatUI 经 require + configure 装配后按需调用
_M.showProviderEditor = showProviderEditor
_M.showModelEditor = showModelEditor
_M.showProviderManager = showProviderManager
_M.showModelManager = showModelManager
_M.showModelPicker = showModelPicker
_M.showSettings = showSettings

return _M
