--[[
  工程主题目录：与 res/values/themes.xml 中 Theme.NeLuaJ.* 对应（点号 → 下划线）。
  创建项目 chip 与设置页列表共用，避免两处文案/取值漂移。
]]
local _M = {}

-- 完整可选主题（设置页）
-- groupKey / labelKey 对应 res.string
_M.OPTIONS = {
  {
    value = "Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay",
    groupKey = "project_theme_group_m3",
    labelKey = "project_theme_m3_noab_overlay",
    recommended = true,
  },
  {
    value = "Theme_NeLuaJ_Material3_NoActionBar",
    groupKey = "project_theme_group_m3",
    labelKey = "project_theme_m3_noab",
  },
  {
    value = "Theme_NeLuaJ_Material3_ActionOverlay",
    groupKey = "project_theme_group_m3",
    labelKey = "project_theme_m3_overlay",
  },
  {
    value = "Theme_NeLuaJ_Material3",
    groupKey = "project_theme_group_m3",
    labelKey = "project_theme_m3_ab",
  },
  {
    value = "Theme_NeLuaJ_Material3_DynamicColors_NoActionBar_ActionOverlay",
    groupKey = "project_theme_group_dyn",
    labelKey = "project_theme_dyn_noab_overlay",
  },
  {
    value = "Theme_NeLuaJ_Material3_DynamicColors_NoActionBar",
    groupKey = "project_theme_group_dyn",
    labelKey = "project_theme_dyn_noab",
  },
  {
    value = "Theme_NeLuaJ_Material3_DynamicColors_ActionOverlay",
    groupKey = "project_theme_group_dyn",
    labelKey = "project_theme_dyn_overlay",
  },
  {
    value = "Theme_NeLuaJ_Material3_DynamicColors",
    groupKey = "project_theme_group_dyn",
    labelKey = "project_theme_dyn_ab",
  },
  {
    value = "Theme_NeLuaJ_MaterialComponent_NoActionBar",
    groupKey = "project_theme_group_mc",
    labelKey = "project_theme_mc_noab",
  },
  {
    value = "Theme_NeLuaJ_MaterialComponent",
    groupKey = "project_theme_group_mc",
    labelKey = "project_theme_mc_ab",
  },
  {
    value = "Theme_NeLuaJ_MaterialComponent_Light_NoActionBar",
    groupKey = "project_theme_group_mc",
    labelKey = "project_theme_mc_light_noab",
  },
  {
    value = "Theme_NeLuaJ_MaterialComponent_Light",
    groupKey = "project_theme_group_mc",
    labelKey = "project_theme_mc_light_ab",
  },
  {
    value = "Theme_NeLuaJ_MaterialComponent_Dark_NoActionBar",
    groupKey = "project_theme_group_mc",
    labelKey = "project_theme_mc_dark_noab",
  },
  {
    value = "Theme_NeLuaJ_MaterialComponent_Dark",
    groupKey = "project_theme_group_mc",
    labelKey = "project_theme_mc_dark_ab",
  },
  {
    value = "Theme_NeLuaJ_Compat_NoActionBar",
    groupKey = "project_theme_group_compat",
    labelKey = "project_theme_compat_noab",
  },
  {
    value = "Theme_NeLuaJ_Compat",
    groupKey = "project_theme_group_compat",
    labelKey = "project_theme_compat_ab",
  },
}

-- 创建工程快捷 chip（常用子集）
_M.CREATE_CHIPS = {
  {
    chip = "theme_m3",
    value = "Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay",
    titleKey = "project_theme_chip_m3",
  },
  {
    chip = "theme_m3_ab",
    value = "Theme_NeLuaJ_Material3",
    titleKey = "project_theme_chip_m3_ab",
  },
  {
    chip = "theme_dyn",
    value = "Theme_NeLuaJ_Material3_DynamicColors_NoActionBar_ActionOverlay",
    titleKey = "project_theme_chip_dyn",
  },
  {
    chip = "theme_dyn_ab",
    value = "Theme_NeLuaJ_Material3_DynamicColors",
    titleKey = "project_theme_chip_dyn_ab",
  },
  {
    chip = "theme_mc",
    value = "Theme_NeLuaJ_MaterialComponent_NoActionBar",
    titleKey = "project_theme_chip_mc",
  },
  {
    chip = "theme_mc_ab",
    value = "Theme_NeLuaJ_MaterialComponent",
    titleKey = "project_theme_chip_mc_ab",
  },
  {
    chip = "theme_compat",
    value = "Theme_NeLuaJ_Compat_NoActionBar",
    titleKey = "project_theme_chip_compat",
  },
  {
    chip = "theme_compat_ab",
    value = "Theme_NeLuaJ_Compat",
    titleKey = "project_theme_chip_compat_ab",
  },
}

_M.DEFAULT = _M.OPTIONS[1].value

function _M.find(value)
  for _, opt in ipairs(_M.OPTIONS) do
    if opt.value == value then return opt end
  end
  return nil
end

function _M.label(opt, res)
  if not opt then return "" end
  local t = res and res.string and res.string[opt.labelKey]
  if t and t ~= "" then return t end
  return opt.value
end

--- 展示用：分组 + 名称（设置列表）
function _M.displayLabel(opt, res)
  if not opt then return "" end
  local name = _M.label(opt, res)
  local group = res and res.string and res.string[opt.groupKey]
  if group and group ~= "" then
    local s = group .. " · " .. name
    if opt.recommended and res.string.project_theme_recommended then
      s = s .. " " .. res.string.project_theme_recommended
    end
    return s
  end
  return name
end

--- 系统 ActionBar 主题：布局勿再塞 Toolbar
function _M.hasSystemActionBar(themeName)
  if type(themeName) ~= "string" or themeName == "" then return false end
  return not themeName:find("NoActionBar", 1, true)
end

--- AppCompat 轻量：无 Material 组件模板
function _M.isCompat(themeName)
  return type(themeName) == "string" and themeName:find("Compat", 1, true) ~= nil
end

--- Material Components（MD2）模板
function _M.isMaterialComponent(themeName)
  return type(themeName) == "string" and themeName:find("MaterialComponent", 1, true) ~= nil
end

--- 动态色主题（与 M3 共用脚手架）
function _M.isDynamic(themeName)
  return type(themeName) == "string" and themeName:find("DynamicColors", 1, true) ~= nil
end

--- 返回 res.string 中 main / layout 模板键
function _M.templateKeys(themeName, useSample)
  local ab = _M.hasSystemActionBar(themeName)
  if _M.isCompat(themeName) then
    if ab then
      return useSample and "mcode_compat_ab" or "mcode_compat_ab_minimal",
        useSample and "lcode_compat_ab" or "lcode_compat_ab_minimal"
    end
    return useSample and "mcode_compat" or "mcode_compat_minimal",
      useSample and "lcode_compat" or "lcode_compat_minimal"
  end
  if _M.isMaterialComponent(themeName) then
    if ab then
      return useSample and "mcode_mc_ab" or "mcode_mc_ab_minimal",
        useSample and "lcode_mc_ab" or "lcode_mc_ab_minimal"
    end
    return useSample and "mcode_mc" or "mcode_mc_minimal",
      useSample and "lcode_mc" or "lcode_mc_minimal"
  end
  -- M3 / DynamicColors
  if ab then
    return useSample and "mcode_ab" or "mcode_ab_minimal",
      useSample and "lcode_ab" or "lcode_ab_minimal"
  end
  return useSample and "mcode" or "mcode_minimal",
    useSample and "lcode" or "lcode_minimal"
end

return _M
