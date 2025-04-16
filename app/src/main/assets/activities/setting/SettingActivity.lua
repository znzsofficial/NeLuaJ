---@diagnostic disable: undefined-global
local ColorDrawable = luajava.bindClass "android.graphics.drawable.ColorDrawable"
local MaterialAlertDialogBuilder = luajava.bindClass "com.google.android.material.dialog.MaterialAlertDialogBuilder"
local GradientDrawable = luajava.bindClass "android.graphics.drawable.GradientDrawable"
local Color = luajava.bindClass "android.graphics.Color"
local View = luajava.bindClass "android.view.View"
local MDC_R = luajava.bindClass "com.google.android.material.R"
import "android.widget.LinearLayout"
import "vinx.material.textfield.MaterialTextField"
local ColorUtil = this.globalData.ColorUtil
this.dynamicColor()

activity {
    title = res.string.setting,
    ContentView = res.layout.setting_layout
}
    .supportActionBar {
        Elevation = 0,
        BackgroundDrawable = ColorDrawable(ColorUtil.getColorBackground()),
        DisplayShowTitleEnabled = true,
        DisplayHomeAsUpEnabled = true
    }

function onOptionsItemSelected(m)
    if m.getItemId() == android.R.id.home then
        this.finish()
    end
end

local input = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
    paddingLeft = "20dp",
    paddingTop = "20dp",
    paddingRight = "20dp",
    Focusable = true,
    FocusableInTouchMode = true,
    {
        MaterialTextField,
        layout_width = "fill",
        layout_height = "wrap",
        textSize = "16dp",
        hint = "#[aa]rrggbb",
        tintColor = ColorUtil.getColorPrimary(),
        style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
        singleLine = true,
        id = "inputField",
    },
}

local input_package = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
    paddingLeft = "20dp",
    paddingTop = "20dp",
    paddingRight = "20dp",
    Focusable = true,
    FocusableInTouchMode = true,
    {
        MaterialTextField,
        layout_width = "fill",
        layout_height = "wrap",
        textSize = "16dp",
        hint = res.string.package_name,
        tintColor = ColorUtil.getColorPrimary(),
        style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
        singleLine = true,
        id = "inputField",
    },
}

local defaultMap = {
    BaseWord = 0xff4477e0,
    KeyWord = 0xffb4002d,
    String = 0xffc2185b,
    UserWord = 0xff5c6bc0,
    Comment = 0xff71787E,
    Global = 0xff689f38,
    Local = 0xffb4b484,
    Upval = 0xff8080c0,
}

local resetColor = function(tag)
    local data = this.getSharedData()
    _G[tag .. "Circle"].background = GradientDrawable()
        .setShape(GradientDrawable.OVAL)
        .setColor(data[tag] and Color.parseColor(data[tag]) or defaultMap[tag])
        .setStroke(4, ColorUtil.getColorOutline())
end

local click = View.OnClickListener {
    onClick = function(view)
        local views = {}
        MaterialAlertDialogBuilder(this)
            .setTitle(view.tag)
            .setView(loadlayout(input, views))
            .setPositiveButton(android.R.string.ok, function()
                local inputColor = views.inputField.text
                local bool, _ = pcall(Color.parseColor, inputColor)
                if not bool then
                    print(res.string.invalid_format)
                    return
                end
                this.setSharedData(view.tag, inputColor)
                resetColor(view.tag)
            end)
            .setNegativeButton(android.R.string.cancel, nil)
            .setNeutralButton(res.string._default, function()
                this.setSharedData(view.tag, nil)
                resetColor(view.tag)
            end)
            .show()
    end
}
BaseWordItem.setOnClickListener(click)
KeyWordItem.setOnClickListener(click)
StringItem.setOnClickListener(click)
UserWordItem.setOnClickListener(click)
CommentItem.setOnClickListener(click)
GlobalItem.setOnClickListener(click)
LocalItem.setOnClickListener(click)
UpvalItem.setOnClickListener(click)

resetColor("BaseWord")
resetColor("KeyWord")
resetColor("String")
resetColor("UserWord")
resetColor("Comment")
resetColor("Global")
resetColor("Local")
resetColor("Upval")

CustomApp.onClick = function()
    local views = {}
    MaterialAlertDialogBuilder(this)
        .setTitle(res.string.debug_app)
        .setView(loadlayout(input_package, views))
        .setPositiveButton(android.R.string.ok, function()
            local package = views.inputField.text
            if this.packageManager.getLaunchIntentForPackage(package) then
                this.setSharedData("debug_app", views.inputField.text)
            else
                print(res.string.app_not_found)
            end
        end)
        .setNegativeButton(android.R.string.cancel, nil)
        .setNeutralButton(res.string.delete, function()
            this.setSharedData("debug_app", nil)
        end)
        .show()
    views.inputField.text = this.getSharedData("debug_app", "")
end
