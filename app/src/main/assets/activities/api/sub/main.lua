require "environment"
import "android.content.Context"
import "android.widget.ImageView"
import "android.widget.LinearLayout"
import "android.widget.RelativeLayout"
import "android.widget.Toast"
import "android.graphics.drawable.ColorDrawable"
import "android.view.View"
import "android.view.WindowManager"
import "android.animation.ObjectAnimator"
import "android.animation.AnimatorSet"
import "com.androlua.adapter.LuaAdapter"
import "androidx.cardview.widget.CardView"
import "com.google.android.material.card.MaterialCardView"
import "android.text.SpannableString"
import "android.text.style.ForegroundColorSpan"

import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"
local DecelerateInterpolator = luajava.newInstance "android.view.animation.DecelerateInterpolator"

local table = table
local insert = table.insert
local utf8 = utf8
local string = string

local clazz = ...
import "activities.api.sub.util"

this.setTheme(R.style.Theme_NeLuaJ_Material3_DynamicColors)

local ColorUtil = this.themeUtil
local primaryColor = ColorUtil.ColorPrimary
local secondaryColor = ColorUtil.ColorSecondary
local tertiaryColor = ColorUtil.ColorTertiary

this.setContentView(loadlayout(res.layout.api_sub))
.setTitle(clazz)
.getSupportActionBar()
.setElevation(0)
.setBackgroundDrawable(ColorDrawable(ColorUtil.getColorBackground()))
.setDisplayShowHomeEnabled(true)
.setDisplayHomeAsUpEnabled(true)

local window = activity.getWindow()
.setNavigationBarColor(0)
.setStatusBarColor(ColorUtil.getColorBackground())
.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
if this.isNightMode() then
  window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_VISIBLE)
 else
  window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR)
end

local classInfo, targetClass = assignClass(clazz)

local function copyText(content)
  activity.getSystemService(Context.CLIPBOARD_SERVICE).setText(tostring(content))
end

-- 分离修饰符和方法体，并根据分类做简化
local function splitModifierAndBody(raw, category)
  local lastSpace = 0
  for pos raw:gfind(" ") do
    lastSpace = pos
  end
  local modifier = raw:sub(1, lastSpace)
  local body = raw:sub(lastSpace + 1, raw:len())

  if category == "bb" or category == "cc" then
    -- 本类方法简化：去掉包名前缀
    local simpleName = targetClass.getSimpleName()
    local beforeParen = body:match("(.+)%(")
    if beforeParen and beforeParen:find(simpleName) then
      body = body:sub(body:find(simpleName), #body)
    end
   elseif category == "ee" then
    -- 字段简化：只保留类型和字段名
    body = body:match("([^%p]+.[^.]+)$")
  end

  return modifier, body
end

-- 构建方法分类过滤器的 Spinner 适配器
local function createMethodFilterAdapter(itemLayout)
  local seen = {}
  local items = { { text = "全部" } }
  for _, v in ipairs(classInfo.cc) do
    local modifier = splitModifierAndBody(v, "cc")
    local label = modifier:gsub("public ", "")
    if not table.find(seen, label) then
      insert(seen, label)
      insert(items, { text = label })
    end
  end
  table.sort(items, function(a, b)
    return utf8.len(a.text) < utf8.len(b.text)
  end)
  return LuaAdapter(activity, items, itemLayout)
end

-- 构建 android.R 子类的 Spinner 适配器
local function createRClassAdapter(itemLayout)
  local items = {}
  local rClasses = android.R.getClasses()
  for i = 0, #rClasses - 1 do
    if #rClasses[i].getDeclaredFields() > 0 then
      insert(items, { text = rClasses[i].getSimpleName() })
    end
  end
  table.sort(items, function(a, b)
    return a.text < b.text
  end)
  return LuaAdapter(activity, items, itemLayout)
end

-- 初始化两个 Spinner 的适配器
local function initSpinnerAdapters()
  local itemLayout = {
    LinearLayout,
    orientation = "vertical",
    layout_height = "wrap",
    layout_width = "match",
    {
      MaterialTextView,
      id = "text",
      layout_margin = "15dp",
      textStyle = "bold",
    },
  }
  spc.Adapter = createMethodFilterAdapter(itemLayout)
  sph.Adapter = createRClassAdapter(itemLayout)
end

initSpinnerAdapters()

-- 分类按钮名称列表和 name→view 映射
local categoryNames = { "aa", "bb", "cc", "dd", "ee", "ff", "gg", "hh" }
local categoryViews = { aa = aa, bb = bb, cc = cc, dd = dd, ee = ee, ff = ff, gg = gg, hh = hh }

local currentCategory   -- 当前选中的分类标签
local currentList       -- 当前分类的数据列表
local filteredMethods   -- cc 分类的过滤子集
local modifierList = {} -- 每行对应的修饰符文本

-- 分类按钮点击
local function onCategoryClick(cardView)
  currentCategory = cardView.Tag
  currentList = classInfo[currentCategory]

  if currentCategory == "cc" then
    spc.setVisibility(1)
    sph.setVisibility(8)
    ed.setWidth(activity.getWidth() / 1.8)
    currentList = filteredMethods or classInfo[currentCategory]
   elseif currentCategory == "hh" then
    sph.setVisibility(1)
    spc.setVisibility(8)
    ed.setWidth(activity.getWidth() / 1.5)
   else
    spc.setVisibility(8)
    sph.setVisibility(8)
    ed.setWidth(activity.getWidth())
  end

  local anim = AnimatorSet()
  local translateY = ObjectAnimator.ofFloat(li, "translationY", { 50, 0 })
  local fadeIn = ObjectAnimator.ofFloat(li, "alpha", { 0, 1 })
  anim.play(fadeIn).with(translateY)
  anim.setDuration(500)
  .setInterpolator(DecelerateInterpolator)
  .start()

  -- 重置所有分类按钮为未选中样式
  for _, name in ipairs(categoryNames) do
    local v = categoryViews[name]
    if v then
      v.setCardElevation(0)
      v.setCardBackgroundColor(0x00000000)
      v.setStrokeColor(ColorUtil.getColorOutline())
    end
  end
  -- 选中按钮高亮
  cardView.setCardElevation(2)
  cardView.setCardBackgroundColor(ColorUtil.getColorSecondaryContainer())
  cardView.setStrokeColor(ColorUtil.getColorSecondary())

  ed.Text = ""
end

-- 设置分类按钮点击函数和标签
for _, name in ipairs(categoryNames) do
  local v = categoryViews[name]
  if v then
    v.Tag = name
    v.onClick = function(card) onCategoryClick(card) end
  end
end

-- 分类列表为空时隐藏按钮
for k, v in pairs(classInfo) do
  if table.size(v) == 0 then
    local idx = table.find(categoryNames, k)
    if idx and categoryNames[idx] ~= "hh" then
      local view = categoryViews[categoryNames[idx]]
      if view then view.setVisibility(8) end
      table.remove(categoryNames, idx)
    end
  end
end

-- 切换 cc 分类的方法过滤
local function switchMethodFilter(position, filterName)
  local prefix = "public " .. filterName
  local escaped = prefix:gsub("%p", "^")
  local filtered = {}
  for _, v in ipairs(classInfo.cc) do
    local escapedMethod = v:gsub("%p", "^")
    if escapedMethod:find(escaped) then
      insert(filtered, v)
    end
  end
  if filterName == "全部" then
    filteredMethods = classInfo.cc
   else
    filteredMethods = filtered
  end
  cc.performClick()
end

-- 切换 R 类资源子类
local function switchRClass(position, className)
  classInfo.hh = {}
  local rClass = luajava.bindClass("android.R$" .. className)
  local fields = rClass.getFields()
  for _, field in (fields) do
    insert(classInfo.hh, "android.R." .. className .. "." .. field.Name)
  end
  hh.performClick()
end

-- Spinner 监听
spc.setOnItemSelectedListener {
  onItemSelected = function(adapter, view, position, id)
    if view then
      view.BackgroundColor = 0x00000000
      switchMethodFilter(id, view.Tag.text.Text)
    end
  end
}

sph.setOnItemSelectedListener {
  onItemSelected = function(adapter, view, position, id)
    if view then
      view.BackgroundColor = 0x00000000
      switchRClass(id, view.Tag.text.Text)
    end
  end
}

-- 渲染列表
local function renderList(dataList, searchText)
  -- 提取方法体用于排序
  local function extractBody(raw)
    local lastSpace = 0
    for pos raw:gfind(" ") do
      lastSpace = pos
    end
    return raw:sub(lastSpace, raw:len())
  end

  table.sort(dataList, function(a, b)
    return extractBody(a):lower() < extractBody(b):lower()
  end)

  local listItemLayout = {
    LinearLayout,
    orientation = "vertical",
    layout_height = "wrap",
    layout_width = "match",
    paddingTop = "8dp",
    paddingBottom = "8dp",
    paddingLeft = "12dp",
    paddingRight = "12dp",
    {
      RelativeLayout,
      layout_width = "match",
      {
        MaterialTextView, -- 修饰符
        id = "ep",
        textSize = "11sp",
        textColor = primaryColor,
        layout_alignParentLeft = "true",
      },
      {
        MaterialTextView, -- 序号
        id = "js",
        textSize = "10sp",
        textColor = secondaryColor,
        layout_alignParentRight = "true",
      },
    },
    {
      MaterialTextView, -- 主要内容
      id = "ez",
      singleLine = false,
      layout_marginTop = "2dp",
      textSize = "14sp",
    },
  }

  local listAdapter = LuaAdapter(activity, listItemLayout)
  li.setAdapter(listAdapter)
  listAdapter.clear()
  modifierList = {}

  if searchText then
    -- 搜索模式
    for k, v in ipairs(dataList) do
      local modifier, body = splitModifierAndBody(v, currentCategory)
      insert(modifierList, modifier)
      local matchStart, matchEnd = body:lower():find(searchText, 1, true)
      listAdapter.add({
        ep = modifier,
        ez = SpannableString(body).setSpan(ForegroundColorSpan(primaryColor), matchStart - 1, matchEnd, 34),
        js = k,
      })
    end
   else
    -- 正常模式
    for k, v in ipairs(dataList) do
      local modifier, body = splitModifierAndBody(v, currentCategory)
      insert(modifierList, modifier)
      listAdapter.add({ ep = modifier, ez = body, js = k })
    end
  end

  listAdapter.notifyDataSetChanged()
  li.smoothScrollToPosition(0)
end

-- 搜索框监听
ed.addTextChangedListener {
  onTextChanged = function(text, start, before, count)
    local input = tostring(text)
    if input:len() <= 2 and ((start == 0 and before == 1 and count == 0) or (start == 0 and before == 0 and count == 1)) then
      return
    end

    local searchLower = input:lower()
    if searchLower:len() < 2 then
      renderList(currentList)
     else
      -- cc 分类的快捷搜索别名
      if currentCategory == "cc" then
        local shortcuts = { set = ".set", get = ".get", is = ".is", add = ".add", li = "listener", bo = "boolean" }
        searchLower = shortcuts[searchLower] or searchLower
      end
      local filtered = {}
      for _, v in ipairs(currentList) do
        local _, body = splitModifierAndBody(v, currentCategory)
        if body:lower():find(searchLower, 1, true) then
          insert(filtered, v)
        end
      end
      renderList(filtered, searchLower)
    end
  end
}

-- 长按复制
li.onItemLongClick = function(listView, itemView)
  local fieldText = itemView.Tag.ez.Text
  Toast.makeText(activity, fieldText .. res.string.copy_success, Toast.LENGTH_LONG).show()
  copyText(tostring(fieldText))
  return true
end

-- 详情弹窗布局
local detailDialogLayout = {
  LinearLayout,
  orientation = "vertical",
  padding = "24dp",
  {
    MaterialCardView,
    id = "colorPreview",
    layout_height = "32dp",
    layout_width = "match",
    layout_marginBottom = "12dp",
    radius = "12dp",
    Visibility = 8,
  },
  {
    ImageView,
    id = "drawablePreview",
    layout_height = "96dp",
    layout_width = "96dp",
    layout_gravity = "center",
    layout_marginBottom = "12dp",
    Visibility = 8,
  },
  {
    MaterialTextView,
    id = "detailText",
    textSize = "14sp",
    padding = "4dp",
    textIsSelectable = true,
  },
  {
    MaterialTextView,
    id = "detailModifier",
    textSize = "0sp",
    textIsSelectable = true,
  },
}

-- 从方法签名中提取不带参数的方法名
local function extractMethodName(raw)
  raw = raw:match("(.-)%(")
  local lastDot = 0
  for pos raw:gfind("%.(.-)") do
    lastDot = pos
  end
  return raw:sub(lastDot + 1, raw:len())
end

-- 列表项点击 → 详情弹窗
li.onItemClick = function(listView, itemView, position, index)
  local btnCopyAll = "全部复制"
  local btnCopyNoArgs = "无参复制"
  local btnQuerySelected = "选中查询"
  itemView.BackgroundColor = 0xFFFFFFFF
  local modifierText = modifierList[index]
  local fieldText = itemView.Tag.ez.Text
  local dialog = MaterialAlertDialogBuilder(this)

  dialog.setOnDismissListener {
    onDismiss = function()
      itemView.BackgroundColor = 0x00000000
    end
  }

  dialog.setView(loadlayout(detailDialogLayout))
  dialog.setTitle(modifierText)
  detailModifier.Text = modifierText

  if currentCategory == "aa" or currentCategory == "bb" or currentCategory == "cc"
      or currentCategory == "gg" or currentCategory == "ff" then

    local paramStart, paramEnd = utf8.find(fieldText, "%((.+)%)")
    local paramContent = utf8.match(fieldText, "%((.+)%)")

    local spanField = nil
    detailText.setText(fieldText)
    if paramStart then
      spanField = SpannableString(fieldText)
      local separated = paramContent:gsub("%,", "\f")
      for matchStart, matchEnd separated:gfind("%g+") do
        spanField.setSpan(ForegroundColorSpan(tertiaryColor), paramStart + matchStart - 1, paramStart + matchEnd, 34)
      end
      detailText.setHighlightColor(primaryColor)
      detailText.setText(spanField)
    end

    dialog.setNegativeButton(btnCopyAll, { onClick = function()
      copyText(fieldText)
    end })

    if currentCategory == "bb" or currentCategory == "cc" then
      dialog.setNeutralButton(btnCopyNoArgs, { onClick = function()
        copyText(extractMethodName(fieldText))
      end })
    end

    dialog.setPositiveButton(btnQuerySelected, { onClick = function()
      local selStart = detailText.getSelectionStart()
      local selEnd = detailText.getSelectionEnd()
      local modSelStart = detailModifier.getSelectionStart()
      local modSelEnd = detailModifier.getSelectionEnd()
      local selectedField = utf8.sub(fieldText, selStart + 1, selEnd)
      local selectedModifier = utf8.sub(modifierText, modSelStart + 1, modSelEnd)
      local combined = selectedField .. selectedModifier
      if #combined == 0 then
        print("未选择内容")
       else
        if pcall(function() luajava.bindClass(combined) end) then
          activity.newActivity(activity.getLuaDir() .. "/activities/api/sub/main", { combined })
          return
        end
        activity.result({ combined })
      end
    end })
  end

  if currentCategory == "ee" or currentCategory == "hh" then
    local fieldName = string.match(tostring(fieldText), "%.([^%.]+)$")
    local value
    try
      value = tostring(luajava.bindClass(clazz).getDeclaredField(fieldName).setAccessible(true).get(nil))
     catch
      try
        local fn = load("return tostring(" .. fieldText .. ")")
        value = fn and fn() or "获取失败"
       catch
        try
          local fn = load("return " .. fieldText .. ".toString()")
          value = fn and fn() or "获取失败"
         catch
          value = "获取失败"
        end
      end
    end

    local valueLabel = res.string.parameter_value
    if currentCategory == "hh" then
      valueLabel = "资源ID"
      local rType = sph.getSelectedView().Tag.text.Text
      if rType == "color" then
        value = tostring(activity.getResources().getColor(tonumber(value)))
        colorPreview.setVisibility(1)
        colorPreview.BackgroundColor = tonumber(value)
        valueLabel = "色码"
      elseif rType == "drawable" then
        drawablePreview.setVisibility(1)
        detailText.setVisibility(8)
        drawablePreview.setBackground(activity.getResources().getDrawable(tonumber(value)))
        value = "ImageView.setBackground(activity.getResources().getDrawable(" .. tonumber(value) .. "))"
        valueLabel = res.string.method
      elseif rType == "string" then
        value = tostring(activity.getResources().getString(tonumber(value)))
        valueLabel = "字符"
      end
    end
    detailText.setText(fieldText .. "\n\n" .. valueLabel .. ": " .. value)
    dialog.setNegativeButton(res.string.copy_field, function()
      copyText(fieldText)
    end)
    dialog.setNeutralButton(string.format(res.string.copy_value, valueLabel), function()
      copyText(value)
    end)
  end

  if currentCategory == "aa" or currentCategory == "dd" then
    detailText.setText(fieldText)
    dialog.setNegativeButton(btnCopyAll, { onClick = function()
      copyText(fieldText)
    end })
  end

  dialog.show()
  return true
end

-- 初始显示列表
local function showInitialCategory()
  if #classInfo.cc ~= 0 then
    cc.performClick()
   else
    for _, name in ipairs(categoryNames) do
      if #classInfo[name] > 0 then
        local v = categoryViews[name]
        if v then v.performClick() end
        return
      end
    end
    hh.performClick()
  end
end

showInitialCategory()

function onOptionsItemSelected(m)
  if m.getItemId() == android.R.id.home
    activity.finish()
  end
end
