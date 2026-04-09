require "environment"
import "android.content.Context"
import "android.widget.LinearLayout"
import "android.widget.ImageView"
import "android.widget.Toast"
import "android.graphics.drawable.ColorDrawable"
import "android.view.View"
import "android.view.WindowManager"
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.card.MaterialCardView"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"
import "com.google.android.material.chip.Chip"
import "android.text.SpannableString"
import "android.text.style.ForegroundColorSpan"
import "android.widget.ArrayAdapter"

this.dynamicColor()
local res = res
local table = table
local insert = table.insert
local string = string
local utf8 = utf8

local ColorUtil = this.themeUtil
local primaryColor = ColorUtil.ColorPrimary
local secondaryColor = ColorUtil.ColorSecondary

this.setContentView(loadlayout(res.layout.resource_browser))
.setTitle(res.string.resource_browser)
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

-- 自动扫描所有可用的 R 类
local knownRClasses = {
  -- 系统
  { name = "android",                          class = "android.R" },
  -- 本应用
  { name = "app",                              class = "github.znzsofficial.neluaj.R" },
  -- Material / AppCompat
  { name = "material",                         class = "com.google.android.material.R" },
  { name = "appcompat",                        class = "androidx.appcompat.R" },
  -- AndroidX 组件
  { name = "activity",                         class = "androidx.activity.R" },
  { name = "constraintlayout",                 class = "androidx.constraintlayout.widget.R" },
  { name = "coordinatorlayout",                class = "androidx.coordinatorlayout.R" },
  { name = "core",                             class = "androidx.core.R" },
  { name = "customview",                       class = "androidx.customview.R" },
  { name = "drawerlayout",                     class = "androidx.drawerlayout.R" },
  { name = "draganddrop",                      class = "androidx.draganddrop.R" },
  { name = "dynamicanimation",                 class = "androidx.dynamicanimation.R" },
  { name = "emoji2",                           class = "androidx.emoji2.R" },
  { name = "fragment",                         class = "androidx.fragment.R" },
  { name = "gridlayout",                       class = "androidx.gridlayout.R" },
  { name = "lifecycle",                        class = "androidx.lifecycle.R" },
  { name = "navigation",                       class = "androidx.navigation.R" },
  { name = "navigation.ui",                    class = "androidx.navigation.ui.R" },
  { name = "palette",                          class = "androidx.palette.R" },
  { name = "preference",                       class = "androidx.preference.R" },
  { name = "recyclerview",                     class = "androidx.recyclerview.R" },
  { name = "swiperefreshlayout",               class = "androidx.swiperefreshlayout.R" },
  { name = "transition",                       class = "androidx.transition.R" },
  { name = "viewpager",                        class = "androidx.viewpager.R" },
  { name = "viewpager2",                       class = "androidx.viewpager2.R" },
  -- 第三方
  { name = "collapsingtoolbar.subtitle",       class = "com.hendraanggrian.material.subtitlecollapsingtoolbarlayout.R" },
  { name = "lottie",                           class = "com.airbnb.lottie.R" },
  { name = "recyclerview-animators",           class = "jp.wasabeef.recyclerview.R" },
  { name = "fastscroll",                       class = "me.zhanghai.android.fastscroll.R" },
}

local sources = {}
local currentSource = nil
local currentSubClassName = nil
local currentFields = {}
local initialized = false

local function copyText(content)
  activity.getSystemService(Context.CLIPBOARD_SERVICE).setText(tostring(content))
  Toast.makeText(activity, tostring(content) .. res.string.copy_success, Toast.LENGTH_LONG).show()
end

-- 获取 R 类的所有子类名（有字段的）
local function getSubClassNames(rClass)
  local names = {}
  local classes = rClass.getClasses()
  for i = 0, #classes - 1 do
    if #classes[i].getDeclaredFields() > 0 then
      insert(names, classes[i].getSimpleName())
    end
  end
  table.sort(names)
  return names
end

-- 获取某个 R 子类的所有字段
local function getFieldList(rClass, subClassName)
  local fields = {}
  try
    local fullName = rClass.getName() .. "$" .. subClassName
    local subClass = bindClass(fullName)
    local declaredFields = subClass.getFields()
    for i = 0, #declaredFields - 1 do
      local field = declaredFields[i]
      insert(fields, {
        name = field.Name,
        fullRef = rClass.getName():gsub("%$", ".") .. "." .. subClassName .. "." .. field.Name,
        value = tostring(field.get(nil)),
      })
    end
    table.sort(fields, function(a, b) return a.name < b.name end)
   catch
  end
  return fields
end

-- 渲染字段列表
local function renderFieldList(fields, searchText)
  local adapter = ArrayAdapter(activity, R.layout.item_check)
  adapter.clear()
  for _, field in ipairs(fields) do
    local display = field.name
    if searchText then
      local matchStart, matchEnd = display:lower():find(searchText, 1, true)
      if matchStart then
        adapter.add(SpannableString(display).setSpan(ForegroundColorSpan(primaryColor), matchStart - 1, matchEnd, 34))
       else
        continue
      end
     else
      adapter.add(display)
    end
  end
  resourceList.setAdapter(adapter)
end

-- 刷新字段列表
local function refreshFieldList()
  if not currentSubClassName then
    return
  end
  currentFields = getFieldList(currentSource.rClass, currentSubClassName)
  renderFieldList(currentFields)
  searchEdit.Hint = #currentFields .. " " .. res.string.resource_items
end

-- 刷新子类 ChipGroup
local function refreshSubClassChips()
  -- 临时移除监听，避免 addView/setChecked 触发多次回调
  subClassChipGroup.setOnCheckedStateChangeListener(nil)
  subClassChipGroup.removeAllViews()
  currentSubClassName = nil
  local names = getSubClassNames(currentSource.rClass)
  for i, name in ipairs(names) do
    local chip = Chip(activity)
    chip.setText(name)
    chip.setCheckable(true)
    chip.setCheckedIconVisible(false)
    chip.setTextSize(0, this.spToPx(12))
    subClassChipGroup.addView(chip)
    if i == 1 then
      chip.setChecked(true)
      currentSubClassName = name
    end
  end
  -- 恢复监听
  subClassChipGroup.setOnCheckedStateChangeListener(onSubClassChipChanged)
  if currentSubClassName then
    refreshFieldList()
  end
end

-- 详情弹窗
local function showFieldDetail(fieldInfo)
  local detailLayout = {
    LinearLayout,
    orientation = "1",
    padding = "20dp",
    {
      MaterialCardView,
      id = "colorPreview",
      layout_height = "28dp",
      layout_width = "-1",
      Visibility = 8,
    },
    {
      ImageView,
      id = "drawablePreview",
      layout_height = "88dp",
      layout_width = "88dp",
      layout_gravity = "center",
      Visibility = 8,
    },
    {
      MaterialTextView,
      id = "detailText",
      textSize = "15sp",
      padding = "6dp",
      textIsSelectable = true,
    },
  }

  local dialog = MaterialAlertDialogBuilder(this)
  dialog.setTitle(fieldInfo.name)
  dialog.setView(loadlayout(detailLayout))

  local valueLabel = "ID"
  local displayValue = fieldInfo.value

  -- 根据子类类型做特殊展示
  if currentSubClassName == "color" then
    try
      local colorValue = activity.getResources().getColor(tonumber(fieldInfo.value))
      displayValue = tostring(colorValue)
      colorPreview.setVisibility(1)
      colorPreview.BackgroundColor = colorValue
      valueLabel = res.string.resource_color
     catch
    end
  elseif currentSubClassName == "drawable" then
    try
      drawablePreview.setVisibility(1)
      drawablePreview.setBackground(activity.getResources().getDrawable(tonumber(fieldInfo.value)))
      displayValue = fieldInfo.fullRef
      valueLabel = res.string.resource_drawable
     catch
    end
  elseif currentSubClassName == "string" then
    try
      displayValue = tostring(activity.getResources().getString(tonumber(fieldInfo.value)))
      valueLabel = res.string.resource_string
     catch
    end
  elseif currentSubClassName == "dimen" then
    try
      displayValue = tostring(activity.getResources().getDimension(tonumber(fieldInfo.value)))
      valueLabel = res.string.resource_dimen
     catch
    end
  end

  detailText.setText(fieldInfo.fullRef .. "\n\n" .. valueLabel .. ": " .. displayValue)

  dialog.setPositiveButton(res.string.copy_field, function()
    copyText(fieldInfo.fullRef)
  end)
  dialog.setNeutralButton(string.format(res.string.copy_value, valueLabel), function()
    copyText(displayValue)
  end)
  dialog.setNegativeButton(android.R.string.cancel, nil)
  dialog.show()
end

-- 异步扫描所有可用的 R 类
local function scanRClasses()
  local result = {}
  for _, entry in ipairs(knownRClasses) do
    try
      local cls = luajava.bindClass(entry.class)
      if cls and #cls.getClasses() > 0 then
        insert(result, { name = entry.name, rClass = cls })
      end
     catch
    end
  end
  if #result == 0 then
    result = {{ name = "android", rClass = luajava.bindClass "android.R" }}
  end
  return result
end

-- 子类 ChipGroup 选择回调（提取为变量，供 refreshSubClassChips 恢复监听用）
onSubClassChipChanged = function(group, checkedIds)
  if not initialized or checkedIds.size() == 0 then return end
  local checkedId = checkedIds.get(0)
  for i = 0, group.getChildCount() - 1 do
    local child = group.getChildAt(i)
    if child.getId() == checkedId then
      currentSubClassName = tostring(child.getText())
      searchEdit.Text = ""
      refreshFieldList()
      break
    end
  end
end

local function initSourceChips(scannedSources)
  sources = scannedSources
  currentSource = sources[1]
  initialized = true

  for i, source in ipairs(sources) do
    local chip = Chip(activity)
    chip.setText(source.name)
    chip.setCheckable(true)
    chip.setCheckedIconVisible(false)
    chip.setTextSize(0, this.spToPx(12))
    sourceChipGroup.addView(chip)
    if i == 1 then
      chip.setChecked(true)
    end
  end

  -- 初始化完成后再注册来源监听，避免 setChecked 触发多余回调
  sourceChipGroup.setOnCheckedStateChangeListener(function(group, checkedIds)
    if not initialized or checkedIds.size() == 0 then return end
    local checkedId = checkedIds.get(0)
    for i = 0, group.getChildCount() - 1 do
      local child = group.getChildAt(i)
      if child.getId() == checkedId then
        currentSource = sources[i + 1]
        searchEdit.Text = ""
        refreshSubClassChips()
        break
      end
    end
  end)

  -- 注册子类监听并加载首个来源
  subClassChipGroup.setOnCheckedStateChangeListener(onSubClassChipChanged)
  refreshSubClassChips()
end

xTask(scanRClasses, initSourceChips)

-- 搜索
searchEdit.addTextChangedListener {
  onTextChanged = function(text, start, before, count)
    local input = tostring(text):lower()
    if input:len() < 1 then
      renderFieldList(currentFields)
     else
      renderFieldList(currentFields, input)
    end
  end
}

-- 列表点击
resourceList.onItemClick = function(listView, itemView, position, id)
  -- 从当前过滤后的列表中找到对应的 fieldInfo
  local displayText = itemView.Text or tostring(itemView.getText())
  -- 去掉可能的 Spannable 格式，用纯文本匹配
  local plainText = tostring(displayText)
  for _, field in ipairs(currentFields) do
    if field.name == plainText then
      showFieldDetail(field)
      return true
    end
  end
  return true
end

-- 长按复制
resourceList.onItemLongClick = function(listView, itemView)
  local plainText = tostring(itemView.Text or itemView.getText())
  for _, field in ipairs(currentFields) do
    if field.name == plainText then
      copyText(field.fullRef)
      return true
    end
  end
  return true
end

function onOptionsItemSelected(m)
  if m.getItemId() == android.R.id.home
    activity.finish()
  end
end
