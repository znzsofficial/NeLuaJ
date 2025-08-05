require "environment"
import "com.androlua.Ticker"
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

local errorColor = ColorUtil.ColorError
local outlineColor = ColorUtil.ColorOutline
local surfaceColor = ColorUtil.ColorSurface
local surfaceColorVar = ColorUtil.ColorSurfaceVariant
local backgroundc = ColorUtil.ColorBackground
local onbackgroundc = ColorUtil.ColorOnBackground
local primaryColor = ColorUtil.ColorPrimary
local primaryOnColor = ColorUtil.ColorOnPrimary
local secondaryColor = ColorUtil.ColorSecondary
local tertiaryc = ColorUtil.ColorTertiary

luadir = activity.getLuaDir()

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
    menu.add(res.string._switch).setShowAsAction(1)
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

--沉浸栏背景色、标题背景色、主背景色
--local co = { primaryColor, onbackgroundc, primaryOnColor }
local ClassesLen
local cls

if simpleList then
    cls = ClassesNames.classes
    activity.setContentView(res.layout.api_main)
    ClassesLen = #cls
else
    cls = ClassesNames.top_classes
    activity.setContentView(res.layout.api_main)
    ClassesLen = #cls
end

function copyText(str)
    activity.getSystemService(Context.CLIPBOARD_SERVICE).setText(str)
    Toast.makeText(activity, tostring(str) .. res.string.copy_success, Toast.LENGTH_LONG).show()
end

clist.onItemLongClick = function(l, v)
    copyText(v.Text)
    return true
end

clist.onItemClick = function(l, v)
    activity.newActivity(activity.getLuaDir() .. "/activities/api/sub/main", { v.Text })
    return true
end

local Executors = bindClass "java.util.concurrent.Executors"
local HandlerCompat = bindClass "androidx.core.os.HandlerCompat"
local Looper = bindClass "android.os.Looper"
local mainLooper = Looper.getMainLooper()
local handler = HandlerCompat.createAsync(mainLooper)

function 列表(t, s)
    local ar = ArrayAdapter(activity, R.layout.item_check)
    if s then
        ar.clear()
        for k, v in (t) do
            local aa, bb = utf8.find(v:lower():gsub([[%$]], [[.]]), s, 1, true)
            ar.add(SpannableString(v).setSpan(ForegroundColorSpan(primaryColor), aa - 1, bb, 34))
        end
    else
        ar.clear()
        for k, v in t do
            ar.add(v)
        end
    end
    clist.setAdapter(ar)
end

edit.addTextChangedListener {

    onTextChanged = function(a, b, c, d)
        local a = tostring(a)
        if a:len() <= 2 and ((b == 0 and c == 1 and d == 0) or (b == 0 and c == 0 and d == 1)) then
            return
        end

        local s = a:gsub([[%$]], [[.]]):lower()
        local t = {}

        if s:len() < 2 then
            列表(cls)
        else
            local executor = Executors.newSingleThreadExecutor()
            executor.execute(function()
                for i = 0, ClassesLen-1 do
                    local v = cls[i]
                    if v:lower():gsub([[%$]], [[.]]):find(s, 1, true) then
                        t[#t + 1] = v
                    end
                end
                handler.post(function()
                    列表(t, s)
                    edit.Hint = #t .. " " .. res.string.classes
                end)
            end)
            executor.shutdown()
        end
    end
}

function ChangeList()
    列表(cls)
    edit.Text = ""
    edit.Hint = ClassesLen .. " " .. res.string.classes
end

ChangeList()--初始化列表

function onResult(a, b)
    edit.Text = b
    edit.setSelection(b:len())
end