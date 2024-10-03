local ColorStateList = bindClass "android.content.res.ColorStateList";
local MaterialTextView = bindClass "com.google.android.material.textview.MaterialTextView";
local MaterialButton = bindClass "com.google.android.material.button.MaterialButton"
local MaterialDivider = bindClass "com.google.android.material.divider.MaterialDivider"
local LinearLayout = bindClass "android.widget.LinearLayout"

local ColorUtil = this.globalData.ColorUtil
--local ColorBackground = ColorUtil.getColorSurfaceVariant();
local ColorPrimary = ColorUtil.getColorPrimary();
local ColorText = ColorUtil.getColorOnSurfaceVariant();

import "androidx.core.graphics.ColorUtils";
local ColorRipple = ColorUtils.blendARGB(ColorPrimary, 0x00ffffff, 0.4)
local res = res

return {
    LinearLayout,
    layout_width = "match",
    layout_height = "wrap",
    orientation = "vertical",
    padding = "20dp",
    {
        MaterialTextView,
        textSize = "18sp",
        textStyle = "bold",
        id = "nameText",
    },
    {
        MaterialTextView,
        textSize = "14sp",
        id = "pathText",
    },
    {
        MaterialDivider,
        layout_marginTop = "6dp",
        layout_marginBottom = "6dp",
        dividerColor = ColorText,
    },
    {
        MaterialButton,
        layout_width = "match",
        layout_height = "wrap",
        BackgroundTintList = ColorStateList.valueOf(0),
        id = "button_delete",
        text = res.string.delete,
        textColor = ColorText,
        icon = this.getResDrawable("delete"),
        iconTint = ColorStateList.valueOf(ColorPrimary),
        RippleColor = ColorStateList.valueOf(ColorRipple),
    },
    {
        MaterialButton,
        layout_width = "match",
        layout_height = "wrap",
        BackgroundTintList = ColorStateList.valueOf(0),
        id = "button_rename",
        text = res.string.rename,
        textColor = ColorText,
        icon = this.getResDrawable("rename"),
        iconTint = ColorStateList.valueOf(ColorPrimary),
        RippleColor = ColorStateList.valueOf(ColorRipple),
    },
    {
        MaterialButton,
        layout_width = "match",
        layout_height = "wrap",
        BackgroundTintList = ColorStateList.valueOf(0),
        id = "button_cdir",
        text = "新建同级文件夹",
        textColor = ColorText,
        icon = this.getResDrawable("new_folder"),
        iconTint = ColorStateList.valueOf(ColorPrimary),
        RippleColor = ColorStateList.valueOf(ColorRipple),
    },
    {
        MaterialButton,
        layout_width = "match",
        layout_height = "wrap",
        BackgroundTintList = ColorStateList.valueOf(0),
        id = "button_cfile",
        text = "新建同级文件",
        textColor = ColorText,
        icon = this.getResDrawable("new_file"),
        iconTint = ColorStateList.valueOf(ColorPrimary),
        RippleColor = ColorStateList.valueOf(ColorRipple),
    },
}
