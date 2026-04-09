require "environment"
import "android.content.Context"
import "android.widget.LinearLayout"
import "android.widget.ImageView"
import "android.widget.Toast"
import "android.graphics.drawable.ColorDrawable"
import "android.view.View"
import "android.view.WindowManager"
import "com.androlua.adapter.LuaAdapter"
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.card.MaterialCardView"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"
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

-- 资源来源定义
local sources = {
  { name = "android.R",  rClass = bindClass "android.R" },
  { name = "Material",   rClass = MDC_R },
  { name = "AppCompat",  rClass = Compat_R },
}

local currentSource = sources[1]
local currentSubClassName = nil
local currentFields = {}

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

-- 刷新子类 Spinner
local function refreshSubClassSpinner()
  local names = getSubClassNames(currentSource.rClass)
  local spinnerItem = {
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
  local items = {}
  for _, name in ipairs(names) do
    insert(items, { text = name })
  end
  subClassSpinner.Adapter = LuaAdapter(activity, items, spinnerItem)
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

-- 初始化来源 Tab
for _, source in ipairs(sources) do
  sourceTab.addTab(sourceTab.newTab().setText(source.name))
end

sourceTab.addOnTabSelectedListener {
  onTabSelected = function(tab)
    currentSource = sources[tab.getPosition() + 1]
    refreshSubClassSpinner()
    searchEdit.Text = ""
  end,
  onTabUnselected = function() end,
  onTabReselected = function() end,
}

-- Spinner 监听
subClassSpinner.setOnItemSelectedListener {
  onItemSelected = function(adapter, view, position, id)
    if view then
      view.BackgroundColor = 0x00000000
      currentSubClassName = view.Tag.text.Text
      searchEdit.Text = ""
      refreshFieldList()
    end
  end
}

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

-- 初始加载
refreshSubClassSpinner()

function onOptionsItemSelected(m)
  if m.getItemId() == android.R.id.home
    activity.finish()
  end
end
