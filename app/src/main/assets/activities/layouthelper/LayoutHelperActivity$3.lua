local _M = {}
local bindClass = luajava.bindClass
local newInstance = luajava.newInstance
local table = table
local find = table.find
local remove = table.remove
local insert = table.insert
local sort = table.sort
local concat = table.concat
local old_res = old_res
local type = type
local ipairs = ipairs
local tostring = tostring
local tonumber = tonumber
local loadlayout2 = require "activities.layouthelper.LayoutHelperActivity$loadlayout"
-- require 会从已经载入的里面取，所以不用担心卡顿
local MaterialAlertDialogBuilder = bindClass "com.google.android.material.dialog.MaterialAlertDialogBuilder"
local String = bindClass "java.lang.String"
local ExpandableListView = newInstance("android.widget.ExpandableListView",activity)
local ExpandableListDialog = MaterialAlertDialogBuilder(activity)
local ArrayExpandableListAdapter = bindClass "com.androlua.adapter.ArrayExpandableListAdapter"

import "androidx.appcompat.widget.*"

local dialog = MaterialAlertDialogBuilder(activity)
local dialog_title

setmetatable(_M,{
  __newindex = function(self,key,value)
    local f = function(...)
      dialog.setTitle(key)
      dialog_title = key
      value(...)
    end
    rawset(self,key,f)
  end,
  __index = function(self,key)
    dialog.setTitle(key)
    dialog_title = key
    return ChooseTypeSetMethodParameterDialog(key)
  end
})

local getCurrentView = function()
  return LayoutHelperActivity.data.current_view
end

local getCurrentViewTag = function()
  return getCurrentView().Tag
end

local showErrorDialog = function(e)
  return MaterialAlertDialogBuilder(activity)
  .setTitle(old_res.string.tip)
  .setMessage(e)
  .setPositiveButton(android.R.string.ok,nil)
  .setNegativeButton(android.R.string.cancel,nil)
  .show()
end

local setMethod = function(method,parameter)
  local tag = getCurrentViewTag()
  local o = tag[method]
  try
    tag[method] = parameter
    activity.setContentView(loadlayout2(
    LayoutHelperActivity.data.current_layout_table,{}
    ))
   catch(e)
    if tag[method] != nil then
      tag[method] = o
    end
    showErrorDialog(e)
  end
end

local removeMethod = function()
  setMethod(dialog_title)
end

local setStringParameterMethod = function(method)

  method = method == nil and dialog_title or method

  local dialog_layout = {}
  local dialog = MaterialAlertDialogBuilder(activity)

  dialog.setTitle(dialog_title)
  dialog.setView(loadlayout(old_res.layout.dialog_parameterinput,dialog_layout))
  .setPositiveButton(android.R.string.ok,function()
    local text = tostring(dialog_layout.parameter.getText())
    setMethod(method,text)
  end)
  .setNegativeButton(android.R.string.cancel,nil)
  .setNeutralButton(old_res.string.no,removeMethod)
  .show()

  local tag = getCurrentViewTag()
  dialog_layout.parameter.setHint("string")
  dialog_layout.parameter.setText(tag[method])

end

local setNumberParameterMethod = function(method)

  method = method == nil and dialog_title or method

  local dialog_layout = {}
  local dialog = MaterialAlertDialogBuilder(activity)

  dialog.setTitle(dialog_title)
  dialog.setView(loadlayout(old_res.layout.dialog_parameterinput,dialog_layout))
  .setPositiveButton(android.R.string.ok,function()
    local text = tostring(dialog_layout.parameter.getText())
    setMethod(method,tonumber(text))
  end)
  .setNegativeButton(android.R.string.cancel,nil)
  .setNeutralButton(old_res.string.no,removeMethod)
  .show()

  local tag = getCurrentViewTag()
  dialog_layout.parameter.setHint("number")
  local text = tostring(tag[method])
  dialog_layout.parameter.setText(text=="nil" and "" or text)
end

local setBooleanParameterMethod = function(method)

  method = method == nil and dialog_title or method

  local b_t = {
    "true",
    "false",
    "nil"
  }

  dialog.setItems(b_t,function(dialog,position)

    local item = b_t[position+1]

    switch item
     case "true"

      setMethod(method,true)

     case "false"

      setMethod(method,false)

     default

      removeMethod()

    end

  end)
  .show()

end

local notSupported = function()
  print(old_res.string.not_support)
end

local unknownType

ChooseTypeSetMethodParameterDialog = function(method)

  local t = {
    "string",
    "number",
    "boolean"
  }

  local func = {
    string = setStringParameterMethod,
    number = setNumberParameterMethod,
    boolean = setBooleanParameterMethod
  }

  setmetatable(func,{
    __index = function(self,key)
      if key=="nil" then

        unknownType = function()
          dialog.setItems(t,function(dialog,position)
            func[t[position+1]](dialog_title)
          end)
          .show()
        end

        return unknownType

       else
        return notSupported
      end
    end
  })

  local tag = type(getCurrentViewTag()[method])

  return func[tag]

end

--------------------

local w_h = function()

  local t = {
    "match_parent",
    "wrap_content",
    "Fixed size..."
  }

  dialog.setItems(t,function(alert_dialog,position)

    local tag = getCurrentViewTag()
    local item = t[position+1]

    if item == "Fixed size..." then
      setStringParameterMethod(dialog_title)
     else
      setMethod(dialog_title,item)
    end

  end)
  .show()

end

--
local gravity_t = {
  "left",
  "top",
  "right",
  "bottom",
  "start",
  "center",
  "end",
  "vertical",
  "horizontal",
}
sort(gravity_t)

local gravity = function()

  local gravity_b = {false,false,false,false,false,false,false,false,false}
  local tag = getCurrentViewTag()[dialog_title]

  if tag != nil then

    for k,v : String(tag).split("\\|") do

      local i = find(gravity_t,v)
      if i then
        gravity_b[i] = true
      end

    end

  end

  local d = MaterialAlertDialogBuilder(activity)
  .setTitle(dialog_title)
  .setMultiChoiceItems(gravity_t,gravity_b,function(dialog,position,boolean)
    gravity_b[position+1] = boolean
  end)
  .setPositiveButton(android.R.string.ok,function()

    local newTable = {}

    for k,v in ipairs(gravity_b) do

      if v==true then
        insert(newTable,gravity_t[k])
      end

    end

    setMethod(dialog_title,concat(newTable,"|"))

  end)
  .setNegativeButton(android.R.string.cancel,nil)
  .setNeutralButton(old_res.string.no,removeMethod)
  .show()

end
--
local setItemsDialog = function(t)
  return function()
    dialog.setItems(t,function(dialog,position)
      local item = t[position+1]
      if item == "nil" then
        removeMethod()
       else
        setMethod(dialog_title,item)
      end
    end)
    .show()
  end
end
--
_M.layout_width = w_h
_M.layout_height = w_h
_M.layout_gravity = gravity
_M.gravity = gravity
_M.onClick = setStringParameterMethod
_M.onLongClick = setStringParameterMethod
_M.background = setStringParameterMethod
_M.backgroundColor = setStringParameterMethod
_M.alpha = setStringParameterMethod
_M.layout_margin = setStringParameterMethod
_M.layout_marginLeft = setStringParameterMethod
_M.layout_marginTop = setStringParameterMethod
_M.layout_marginRight = setStringParameterMethod
_M.layout_marginBottom = setStringParameterMethod
_M.padding = setStringParameterMethod
_M.paddingLeft = setStringParameterMethod
_M.paddingTop = setStringParameterMethod
_M.paddingRight = setStringParameterMethod
_M.paddingButtom = setStringParameterMethod
_M.Ration = setStringParameterMethod
_M.RationX = setStringParameterMethod
_M.RationY = setStringParameterMethod
_M.layout_x = setStringParameterMethod
_M.layout_y = setStringParameterMethod
_M.Elevation = setStringParameterMethod
_M.text = setStringParameterMethod
_M.Clickable = setBooleanParameterMethod
_M.Enabled = setBooleanParameterMethod
_M.LayoutTransition = notSupported
_M.orientation = setItemsDialog({
  "vertical",
  "horizontal",
})
_M.visibility = setNumberParameterMethod
_M.id = setStringParameterMethod
_M.hint = setStringParameterMethod
_M.hintTextColor = setStringParameterMethod
_M.error = setStringParameterMethod
_M.singleLine = setBooleanParameterMethod
_M.textColor = setStringParameterMethod
_M.textSize = setStringParameterMethod
_M.textStyle = setItemsDialog({
  "bold",
  "normal",
  "italic",
  "bold|italic",
  "nil",
})
_M.ellipsize = setItemsDialog({
  "start",
  "end",
  "middle",
  "marquee"
})
_M.scaleType = setItemsDialog({
  "matrix",
  "fitXY",
  "fitStart",
  "fitCenter",
  "fitEnd",
  "center",
  "centerCrop",
  "centerInside"
})
_M.src = setStringParameterMethod -- LuaJ 填的是绝对路径，就不自动识别了（
_M.ColorFilter = setStringParameterMethod
_M.MaxWidth = setStringParameterMethod
_M.MaxHeight = setStringParameterMethod
_M.ImageAlpha = setStringParameterMethod
--
_M["•"..old_res.string.delete] = function()

  local view = getCurrentView()

  local dialog = MaterialAlertDialogBuilder(activity)
  .setTitle(old_res.string.tip)
  .setMessage(
  old_res.string.confirm_delete:format(view.class.getSimpleName())
  )
  .setPositiveButton(old_res.string.delete,function()
    local gp=view.getParent().Tag
    if gp==nil then
      print(old_res.string.already_topview)
      return
    end
    for k,v in ipairs(gp) do
      if v==view.Tag then
        remove(gp,k)
        break
      end
    end
    activity.setContentView(loadlayout2(LayoutHelperActivity.data.current_layout_table,{}))
  end)
  .setNegativeButton(android.R.string.cancel,nil)
  .show()

end

_M["•"..old_res.string.add] = function()
  ExpandableListDialog = ExpandableListDialog.setTitle(dialog_title)
  .setView(ExpandableListView)
  .show()
  .create()
end
--

local ns={
  "Widget","Check view","Adapter view",
  "Advanced Widget","Layout","Advanced Layout",
  "Material Design",
}

local wds={
  {"AppCompatButton","AppCompatEditText","AppCompatTextView",
    "AppCompatImageButton","AppCompatImageView"},
  {"AppCompatCheckBox","AppCompatRadioButton","AppCompatToggleButton",
    "SwitchMaterial"},
  {"ListView","GridView","ViewPager",
    "ExpandableListView","AppCompatSpinner","RecyclerView"},
  {"SeekBar","ProgressBar","RatingBar",
    "DatePicker","TimePicker","NumberPicker",
    "LuaEditor","LuaWebView"},
  {"LinearLayout","LinearLayoutCompat","AbsoluteLayout",
    "FrameLayout","RelativeLayout","CoordinatorLayout",
    "ConstraintLayout"},
  {"CardView","RadioGroup","GridLayout",
    "ScrollView","HorizontalScrollView","NestedScrollView"},
  {"MaterialButton","MaterialTextView","MaterialTextField",
    "MaterialCardView","MaterialSwitch","MaterialCheckBox",
    "TabLayout","ExtendedFloatingActionButton","FloatingActionButton",
    "MaterialDivider","Chip","ChipGroup",
    "CircularProgressIndicator"}
}

local classes = {
  SwitchMaterial = bindClass "com.google.android.material.switchmaterial.SwitchMaterial",
  ViewPager = bindClass "androidx.viewpager.widget.ViewPager",
  RecyclerView = bindClass "androidx.recyclerview.widget.RecyclerView",
  LuaEditor = bindClass "com.androlua.LuaEditor",
  LuaWebView = bindClass "com.androlua.LuaWebView",
  ConstraintLayout = bindClass "androidx.constraintlayout.widget.ConstraintLayout",
  CoordinatorLayout = bindClass "androidx.coordinatorlayout.widget.CoordinatorLayout",
  CardView = bindClass "androidx.cardview.widget.CardView",
  NestedScrollView = bindClass "androidx.core.widget.NestedScrollView",
  TabLayout = bindClass "com.google.android.material.tabs.TabLayout",
  MaterialCheckBox = bindClass "com.google.android.material.checkbox.MaterialCheckBox",
  MaterialSwitch = bindClass "com.google.android.material.materialswitch.MaterialSwitch",
  MaterialCardView = bindClass "com.google.android.material.card.MaterialCardView",
  MaterialTextField = bindClass "vinx.material.textfield.MaterialTextField",
  MaterialTextView = bindClass "com.google.android.material.textview.MaterialTextView",
  MaterialButton = bindClass "com.google.android.material.button.MaterialButton" ,
  CircularProgressIndicator = bindClass "com.google.android.material.progressindicator.CircularProgressIndicator",
  ChipGroup = bindClass "com.google.android.material.chip.ChipGroup",
  MaterialDivider = bindClass "com.google.android.material.divider.MaterialDivider",
  Chip = bindClass "com.google.android.material.chip.Chip",
  ExtendedFloatingActionButton = bindClass "com.google.android.material.floatingactionbutton.ExtendedFloatingActionButton",
  FloatingActionButton = bindClass "com.google.android.material.floatingactionbutton.FloatingActionButton",
}

setmetatable(classes,{
  __index = function(self,key)
    local class
    try
      class = bindClass("androidx.appcompat.widget."..key)
     catch(e)
      try
        class = bindClass("android.widget."..key)
       catch(e)
        print(e)
      end
    end
    return class
  end
})


local mAdapter=ArrayExpandableListAdapter(activity)
for k,v in ipairs(ns) do
  mAdapter.add(v,wds[k])
end
ExpandableListView.setAdapter(mAdapter)

ExpandableListView.onChildClick=function(view,item,parent_position,child_position)
  local class = classes[wds[parent_position+1][child_position+1]]
  local tag = getCurrentViewTag()
  insert(tag,{class})
  try
    activity.setContentView(loadlayout2(LayoutHelperActivity.data.current_layout_table,{}))
   catch(e)
    remove(tag)
    showErrorDialog(e)
  end
  ExpandableListDialog.hide()
end
--
_M["•"..old_res.string.parent_view] = function()
  local view = getCurrentView().getParent()
  if view.Tag == nil then
    print(old_res.string.already_topview)
   else
    LayoutHelperActivity.mods.showEditViewDialog(view)
    LayoutHelperActivity.data.current_view = view
  end
end
--
_M["•"..old_res.string.child_view] = function()
  local view = getCurrentView()
  local chids={}
  local chids_name={}
  for n=0,view.ChildCount-1 do
    local chid=view.getChildAt(n)
    chids[n]=chid
    insert(chids_name,chid.class.getSimpleName())
  end
  dialog.setItems(chids_name,function(dialog,position)
    view = chids[position]
    LayoutHelperActivity.mods.showEditViewDialog(view)
    LayoutHelperActivity.data.current_view = view
  end)
  .show()
end
--
--[[_M["•"..old_res.string.other_methods] = function()
  
end]]
--
collectgarbage("collect")

return _M