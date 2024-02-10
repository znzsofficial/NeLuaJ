require "environment"
import "android.content.Context"
import "android.widget.ImageView"
import "android.widget.LinearLayout"
import "android.widget.RelativeLayout"
import "android.widget.Toast"
import "android.graphics.Color"
import "android.graphics.drawable.ColorDrawable"
import "android.view.View"
import "android.view.WindowManager"
import "android.animation.ObjectAnimator"
import "android.animation.AnimatorSet"
local DecelerateInterpolator = luajava.newInstance "android.view.animation.DecelerateInterpolator"
import "com.androlua.adapter.LuaAdapter"
import "androidx.cardview.widget.CardView"
import "android.text.SpannableString"
import "android.text.style.ForegroundColorSpan"
import "android.text.style.UnderlineSpan"
import "android.text.style.ClickableSpan"
import "android.graphics.drawable.GradientDrawable"
import "android.text.method.LinkMovementMethod"
import "com.google.android.material.card.MaterialCardView"
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"
import "mods.utils.UiUtil"

local thisField

local ColorUtil = this.globalData.ColorUtil
local accentColor=ColorUtil.ColorAccent
local errorColor=ColorUtil.ColorError
local outlineColor=ColorUtil.ColorOutline
local surfaceColor=ColorUtil.ColorSurface
local surfaceColorVar=ColorUtil.ColorSurfaceVariant
local backgroundc=ColorUtil.ColorBackground
local onbackgroundc=ColorUtil.ColorOnBackground
local primaryColor=ColorUtil.ColorPrimary
local primaryOnColor=ColorUtil.ColorOnPrimary
local secondaryColor=ColorUtil.ColorSecondary
local tertiaryc=ColorUtil.ColorTertiary
local textc=ColorUtil.TextColor
local insert = table.insert
local:table
local:utf8
local:string

local clazz=...
import "activities.znzsofficial.api.sub.util"
activity.setContentView(loadlayout(res.layout.api_sub))
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
if UiUtil.isNightMode()
  window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_VISIBLE)
 else
  window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR)
end

eee,class = aas(clazz)

local function copyText(content)
  activity.getSystemService(Context.CLIPBOARD_SERVICE).setText(tostring(content))
end

--分离修饰类和方法类、简化。
function vvv(a,tag)
  local i=0
  for v a:gfind(" ")do
    i=v
  end
  local aa=a:sub(1,i)--修饰类
  local bb=a:sub(i+1,a:len())--方法类
  ----------------------------
  if tag=="bb" or tag=="cc"then
    -----本类显示简化-----
    local cc=class.getSimpleName()

    if bb:match("(.+)%("):find(cc)then
      bb=bb:sub(bb:find(cc),#bb)
    end

    --[[
    bb=bb:gsub("java.lang.Object","Object")
    bb=bb:gsub("java.lang.String","String")
    bb=bb:gsub("android.view.","")
    bb=bb:gsub("android.","")
]]
    --字段简化---
   elseif tag=="ee" then
    bb= bb:match("([^%p]+.[^.]+)$")
  end

  return aa,bb
end


CAdapter = (function(item)
  local tab = {}
  local tab2 = {{text="全部"}}
  for k,v in ipairs(eee.cc) do
    local aa = vvv(v,"cc")
    local bb = aa:gsub("public ","")
    if not table.find(tab,bb) then
      insert(tab,bb)
      insert(tab2,{text=bb})
    end
  end
  --字节小大排序
  table.sort(tab2,function(a,b)
    return utf8.len(a.text) < utf8.len(b.text)
  end)
  return LuaAdapter(activity,tab2,item)
end)

HAdapter = (function(item)
  local tab = {}
  local aab=android.R.getClasses()
  for i=0,#aab-1 do
    if #aab[i].getDeclaredFields() > 0 then
      insert(tab,{text=aab[i].getSimpleName()})
    end
  end
  --字母顺序排序
  table.sort(tab,function(a,b)
    return a.text < b.text
  end)
  return LuaAdapter(activity,tab,item)
end)
--________________________________________________


function adp()
  local item={
    LinearLayout,
    orientation="vertical",
    layout_height="wrap";
    layout_width="match",
    {
      MaterialTextView,
      id="text",
      layout_margin="15dp",
      textColor=textc;
      textStyle="bold",
    },
  }

  spc.Adapter = CAdapter(item)

  sph.Adapter = HAdapter(item)

end

adp()

aaa={"aa","bb","cc","dd","ee","ff","gg","hh"}

--分类按钮点击函数

function ll(a)
  tag=a.Tag
  ec=eee[tag]

  if tag == "cc" then
    spc.setVisibility(1)
    sph.setVisibility(8)
    ed.setWidth(activity.getWidth()/1.8)
    ec=ecc or eee[tag]
   elseif tag == "hh" then
    sph.setVisibility(1)
    spc.setVisibility(8)
    ed.setWidth(activity.getWidth()/1.5)
   else
    spc.setVisibility(8)
    sph.setVisibility(8)
    ed.setWidth(activity.getWidth())
  end

  local Anim = AnimatorSet()
  local X=ObjectAnimator.ofFloat(li, "translationY", {50, 0})
  local A=ObjectAnimator.ofFloat(li, "alpha", {0, 1})
  Anim.play(A).with(X)
  Anim.setDuration(500)
  .setInterpolator(DecelerateInterpolator)
  .start()

  for i=1,#aaa do
    load(aaa[i]..".setCardElevation(0)")()--未选择的按钮颜色
  end
  a.setCardElevation(4)--当前选择的按钮颜色

  ed.Text=""
end

--设置分类按钮点击函数和标签
for i=1,#aaa do
  load(aaa[i]..".Tag=aaa["..i.."]")()
  load(aaa[i]..".onClick=function(a)ll(a) end")()
end

--分类列表为0时按钮显示灰色并禁用
for k,v in pairs(eee)
  if table.size(v)==0 then
    local a = table.find(aaa,k)
    local _k = aaa[a]
    if _k ~= "hh" then
      --load(aaa[a]..".BackgroundColor = 0x00FFFFFF")()
      load(_k..".setVisibility(8)")()
      table.remove(aaa,a)
    end
  end
end

function 切换cc(a,b)
  local aa = "public " .. b
  local bb = aa:gsub("%p","^")
  local tab = {}
  for k,v in ipairs(eee.cc) do
    local cc=v:gsub("%p","^")
    if cc:find(bb) then
      insert(tab,v)
    end
  end
  if b == "全部" then
    ecc=eee.cc
   else
    ecc=tab
  end
  cc.performClick()
end

local function 切换R类(a,b)
  eee.hh={}
  local R=load("return android.R."..b..".getFields()")()
  for k,v in pairs(luajava.astable(R)) do
    local RR="android.R."..b.."."..v.Name
    insert(eee.hh,RR)
  end
  hh.performClick()
end


--R类资源切换监听

spc.setOnItemSelectedListener{
  onItemSelected=function(a,b,c,d)
    if b then
      b.BackgroundColor=0x00000000
      local e=b.Tag.text.Text--切换项名
      切换cc(d,e)
    end
  end
}

sph.setOnItemSelectedListener{
  onItemSelected=function(a,b,c,d)
    if b then
      b.BackgroundColor=0x00000000
      local e=b.Tag.text.Text--切换项名
      切换R类(d,e)
    end
  end
}



function 列表(a,s)

  local function vv(a)
    local i=0
    for v a:gfind(" ")do
      i=v
    end
    return a:sub(i,a:len())
  end

  table.sort(a,function(a,b)
    return (vv(a):lower()) < (vv(b):lower())
  end)

  item={
    LinearLayout,
    orientation="vertical",
    layout_height="wrap";
    layout_width="match";
    { RelativeLayout,
      {
        MaterialTextView,--修饰类、翻译
        id="ep",
        textSize="10sp",
        textColor=primaryColor;
        layout_marginTop="2dp",
        layout_marginLeft="6dp";
      },
      {
        MaterialTextView,--列表序号
        id="js",
        textSize="8sp",
        textColor=secondaryColor;
        layout_marginRight="8dp";
        layout_alignParentRight="true";
      },
    },
    {
      MaterialTextView,--主要内容
      id="ez",
      singleLine=false;
      layout_margin="2dp",
      textColor=textc;
      layout_marginLeft="6dp";
    },
  }

  adp=LuaAdapter(activity,item)
  li.setAdapter(adp)
  adp.clear()
  if s then--搜索时
    publictable={}
    for k,v in ipairs(a) do
      local cc,dd=vvv(v,tag)
      insert(publictable,cc)
      local aa,bb= dd:lower():find(s,1,true)
      adp.add({ep=cc,ez=SpannableString(dd).setSpan(ForegroundColorSpan(primaryColor),aa-1,bb,34),js=k})
    end
   else--未搜索时
    publictable={}
    count=0
    for k,v in ipairs(a) do
      local aa,bb=vvv(v,tag)
      insert(publictable,aa)
      adp.add({ep=aa,ez=bb,js=k})
      --判断类库是否存在该子类
      --[[
      if tag=="aa" and not cl.containsValue(bb) then
        cl.put(cl.size()+1,bb)
        tabadd=true
        count=count+1
      end]]

    end
  end
  --转table保存
  --[[
  if tabadd then
    tabadd=false
    io.open(vl,"w"):write(dump(luajava.astable(cl))):close()
    print("已自动添加"..count.."项新的类,重启后更新类列表")
    count=0
  end
]]
  adp.notifyDataSetChanged()
  li.smoothScrollToPosition(0)
end

ed.addTextChangedListener{
  onTextChanged=function(a,b,c,d)

    if tostring(a):len()<=2 and ((b==0 and c ==1 and d==0) or (b==0 and c==0 and d==1))then
      return
    end

    local e=tostring(a)
    local s=e:lower()
    if s:len() < 2 then
      列表(ec)
     else
      local t={}
      if tag == "cc" then
        local data={set=".set",get=".get",is=".is",add=".add",li="listener",bo="boolean"}--快捷搜索
        for k,v in pairs(data) do
          if s==k then
            s=v
          end
        end
      end
      for k,v in ipairs(ec) do
        local aa,bb=vvv(v,tag)

        if bb:lower():find(s,1,true) then
          insert(t,v)
        end
      end
      列表(t,s)
    end
  end
}

--长按
li.onItemLongClick=function(l,v)
  thisField=v.Tag.ez.Text
  Toast.makeText(activity,thisField.."复制成功", Toast.LENGTH_LONG).show()
  copyText(tostring(thisField))
  return true
end

--弹窗布局
ass={
  LinearLayout;
  orientation="1";
  padding="20dp",
  {
    CardView;
    id="asf",
    layout_height="28dp";
    layout_width="-1";
    Visibility=8;
  };
  {
    ImageView;
    id="asg",
    layout_height="88dp";
    layout_width="88dp";
    layout_gravity="center";
    Visibility=8;
  };
  {
    MaterialTextView;
    id="asd",
    textSize="15sp",
    padding="6dp";
    textIsSelectable=true
  };
  {
    MaterialTextView;
    id="ase",
    textSize="0sp",
    textIsSelectable=true
  };

};
local function cvv(a)
  a=a:match("(.-)%(")
  local i=0
  for v a:gfind("%.(.-)")do
    i=v
  end
  return a:sub(i+1,a:len())
end

li.onItemClick=function(l,v,a,b)

  bu1="全部复制"
  bu2="无参复制"
  bu3="选中查询"
  fff="参值"
  v.BackgroundColor = 0xFFFFFFFF
  nnn=publictable[b]
  thisField=v.Tag.ez.Text
  local dialog=MaterialAlertDialogBuilder(this)

  dialog.setOnDismissListener{
    onDismiss= function()
      v.BackgroundColor = 0x00000000
  end}

  dialog.setView(loadlayout(ass))
  dialog.setTitle(nnn)
  ase.Text=nnn

  if tag=="aa" or tag=="bb"or tag=="cc"or tag=="gg"or tag=="ff" then
    local a,b=utf8.find(thisField,"%((.+)%)")
    local c = utf8.match(thisField,"%((.+)%)")

    SpanField=nil
    asd.setText(SpanField or thisField)
    if a then--有参数时
      SpanField=SpannableString(thisField)

      local ss=c:gsub("%,","\f")
      for k,v ss:gfind("%g+") do
        SpanField.setSpan(ForegroundColorSpan(tertiaryc),a+k-1,a+v,34)
      end


      asd.setHighlightColor(primaryColor);

      asd.setText(SpanField)
    end

    dialog.setNegativeButton(bu1,{onClick=function(v)
        copyText(thisField)
    end})
    if tag=="ff"or tag=="gg" then
    end
    if tag=="bb" or tag=="cc" then
      dialog.setNeutralButton(bu2,{onClick=function(v)
          -- local aa= thisField:sub(1,thisField:find("(",1,true)-1)
          local aa =cvv(thisField)
          copyText(aa)
      end})
    end


    dialog.setPositiveButton(bu3,{onClick=function(v)
        local aa=asd.getSelectionStart()
        local bb= asd.getSelectionEnd()
        local cc=ase.getSelectionStart()
        local dd= ase.getSelectionEnd()
        local a=utf8.sub(thisField,aa+1,bb)
        local b=utf8.sub(nnn,cc+1,dd)
        local c= a .. b
        if #c == 0 then
          print("未选择内容")
         else
          if pcall(function()luajava.bindClass(c)end) then
            activity.newActivity(activity.getLuaDir().."/activities/znzsofficial/api/sub/main",{c})
            return
          end

          activity.result({c})
        end
    end})
  end


  if tag=="ee" or tag=="hh"then

    local p = string.match(tostring(thisField), "%.([^%.]+)$")
    try
      value = tostring(luajava.bindClass(clazz).getDeclaredField(p).setAccessible(true).get(nil))
      catch
      try
        load("value=tostring("..thisField..")")()
        catch
        try
          load("value="..thisField..".toString()")()
          catch
          value="获取失败"
        end
      end
    end


    if tag=="hh"then
      fff="资源ID"
      if sph.getSelectedView().Tag.text.Text == "color" then
        load("value=tostring(activity.getResources().getColor("..value.."))")()
        asf.setVisibility(1)
        asf.BackgroundColor=tonumber(value)
        fff="色码"
      end
      if sph.getSelectedView().Tag.text.Text == "drawable" then
        asg.setVisibility(1)
        asd.setVisibility(8)
        asg.setBackground(activity.getResources().getDrawable(tonumber(value)))
        value="ImageView.setBackground(activity.getResources().getDrawable("..tonumber(value).."))"
        fff="方法"
      end
      if sph.getSelectedView().Tag.text.Text == "string" then
        load("value=tostring(activity.getResources().getString("..value.."))")()
        fff="字符"
      end
    end
    asd.setText(thisField.."\n\n"..fff..": "..value)
    dialog.setNegativeButton("复制字段",{onClick=function(v)
        copyText(thisField)
    end})
    dialog.setNeutralButton("复制"..fff,{onClick=function(v)
        copyText(value)
    end})

  end
  if tag=="aa"or tag=="dd"then
    asd.setText(thisField)
    dialog.setNegativeButton(bu1,{onClick=function(v)
        copyText(thisField)
    end})
  end

  dialog.show()

  return true
end
--初始显示列表
function 初始显示()
  if #eee.cc ~= 0 then
    cc.performClick()
   else
    for i=1,#aaa do
      if #eee[aaa[i]] > 0 then
        load(aaa[i]..".performClick()")()
        return
      end
    end
    hh.performClick()
  end
end

初始显示()

function onOptionsItemSelected(m)
if m.getItemId() == android.R.id.home
activity.finish()
end
end