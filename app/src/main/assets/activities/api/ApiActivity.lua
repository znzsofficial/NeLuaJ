require "environment"
import "android.widget.ArrayAdapter"
import "android.widget.Toast"
import "android.content.Context"
import "android.graphics.drawable.ColorDrawable"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"
import "android.view.View"
import "android.view.WindowManager"
this.dynamicColor()
local res = res
local ColorUtil = this.themeUtil
local table = table

local simpleList = ... or false
local SpannableString = bindClass "android.text.SpannableString"
local ForegroundColorSpan = bindClass "android.text.style.ForegroundColorSpan"

local primaryColor = ColorUtil.ColorPrimary

luadir = activity.getLuaDir()
local isDexMode = false

activity
.setTitle(res.string.api_title)
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

function onCreateOptionsMenu(menu)
  if not isDexMode then
    menu.add(res.string._switch).setShowAsAction(1)
  end
  menu.add(res.string.open).setShowAsAction(1)
end

function onOptionsItemSelected(m)
  if m.getItemId() == android.R.id.home then
    activity.finish()
   elseif m.title == res.string._switch then
    activity.newActivity(luadir .. "/activities/api/ApiActivity.lua", { not simpleList })
    activity.overridePendingTransition(android.R.anim.fade_in, android.R.anim.fade_out)
    activity.finish()
   elseif m.title == res.string.open then
    local sublayout = {}
    MaterialAlertDialogBuilder(activity)
    .setTitle(res.string.input_class)
    .setView(loadlayout(res.layout.dialog_fileinput, sublayout))
    .setPositiveButton(android.R.string.ok, function()
      activity.newActivity(activity.getLuaDir() .. "/activities/api/sub/main", { tostring(sublayout.file_name.getText()) })
    end)
    .setNegativeButton(android.R.string.cancel, nil)
    .show();
  end
end

local classList
local classCount

-- 检查是否是 dex 文件分析模式
if type(simpleList) == "string" and simpleList:sub(1, 4) == "dex:" then
  isDexMode = true
  local dexPath = simpleList:sub(5)
  local reader = luajava.newInstance("com.nekolaska.internal.ClassNamesReader", activity.applicationContext)
  classList = luajava.astable(reader.readDexTopClasses(dexPath))
  classCount = #classList
  activity.setContentView(res.layout.api_main)
  activity.setTitle(dexPath:match(".*/(.*)") or dexPath)
elseif simpleList then
  ClassesNames.ensure()
  classList = ClassesNames.classes
  activity.setContentView(res.layout.api_main)
  classCount = #classList
 else
  ClassesNames.ensure()
  classList = ClassesNames.top_classes
  activity.setContentView(res.layout.api_main)
  classCount = #classList
end

local function copyText(str)
  activity.getSystemService(Context.CLIPBOARD_SERVICE).setText(str)
  Toast.makeText(activity, tostring(str) .. res.string.copy_success, Toast.LENGTH_LONG).show()
end

clist.onItemLongClick = function(listView, itemView)
  copyText(itemView.Text)
  return true
end

clist.onItemClick = function(listView, itemView)
  activity.newActivity(activity.getLuaDir() .. "/activities/api/sub/main", { itemView.Text })
  return true
end

local function renderClassList(data, searchText)
  local adapter = ArrayAdapter(activity, R.layout.item_check)
  adapter.clear()
  if searchText then
    if isDexMode then
      for _, className in ipairs(data) do
        local matchStart, matchEnd = utf8.find(className:lower():gsub([[%$]], [[.]]), searchText, 1, true)
        adapter.add(SpannableString(className).setSpan(ForegroundColorSpan(primaryColor), matchStart - 1, matchEnd, 34))
      end
     else
      for _, className in (data) do
        local matchStart, matchEnd = utf8.find(className:lower():gsub([[%$]], [[.]]), searchText, 1, true)
        adapter.add(SpannableString(className).setSpan(ForegroundColorSpan(primaryColor), matchStart - 1, matchEnd, 34))
      end
    end
   else
    if isDexMode then
      for _, className in ipairs(data) do
        adapter.add(className)
      end
     else
      for _, className in data do
        adapter.add(className)
      end
    end
  end
  clist.setAdapter(adapter)
end

edit.addTextChangedListener {
  onTextChanged = function(text, start, before, count)
    local input = tostring(text)
    if (start == 0 and before == 1 and count == 0) or (start == 0 and before == 0 and count == 1) then
      return
    end

    local searchLower = input:gsub([[%$]], [[.]]):lower()
    local filtered = {}

    if searchLower:len() < 2 then
      renderClassList(classList)
      edit.Hint = classCount .. " " .. res.string.classes
     else
      xTask(function()
        if isDexMode then
          -- Lua table: 1-based ipairs
          for _, v in ipairs(classList) do
            if v:lower():gsub([[%$]], [[.]]):find(searchLower, 1, true) then
              filtered[#filtered + 1] = v
            end
          end
         else
          -- Java List: 0-based index
          for i = 0, classCount - 1 do
            local v = classList[i]
            if v:lower():gsub([[%$]], [[.]]):find(searchLower, 1, true) then
              filtered[#filtered + 1] = v
            end
          end
        end
      end, function()
        renderClassList(filtered, searchLower)
        edit.Hint = #filtered .. " " .. res.string.classes
      end)
    end
  end
}

local function resetList()
  renderClassList(classList)
  edit.Text = ""
  edit.Hint = classCount .. " " .. res.string.classes
end

resetList() -- 初始化列表

function onResult(name, text)
  edit.Text = text
  edit.setSelection(text:len())
end

