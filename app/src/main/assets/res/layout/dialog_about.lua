---@diagnostic disable: undefined-global
import "com.google.android.material.textview.MaterialTextView";
import "android.widget.LinearLayout";
local ColorUtil = this.globalData.ColorUtil

return {
    LinearLayout,
    layout_width = 'match_parent',
    layout_height = 'wrap',
    orientation = "vertical",
    {
        MaterialTextView,
        id = "author",
        layout_gravity = "center",
        layout_height = "wrap",
        layout_width = "wrap",
        text = "https://github.com/znzsofficial/NeLuaJ\n@智商封印official\n当前版本：" .. this.getVersionName("获取失败"),
        textColor = ColorUtil.getColorPrimary(),
        textIsSelectable = true,
    },
};
