import "android.widget.LinearLayout"
import "com.google.android.material.textview.MaterialTextView";
import "vinx.material.textfield.MaterialTextField"
import "com.google.android.material.textfield.TextInputLayout"
import "com.google.android.material.chip.Chip"
import "com.google.android.material.chip.ChipGroup"
local ColorUtil = this.themeUtil

return {
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
        hint = "软件名称",
        layout_width = "fill",
        layout_height = "wrap",
        textSize = "12dp",
        TintColor = ColorUtil.getColorPrimary(),
        style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
        singleLine = true,
        id = "project_appName",
    },
    {
        MaterialTextField,
        layout_marginTop = "16dp",
        hint = "软件包名",
        layout_width = "fill",
        layout_height = "wrap",
        textSize = "12dp",
        TintColor = ColorUtil.getColorPrimary(),
        style = MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox,
        singleLine = true,
        id = "project_packageName",
    },
    {
        MaterialTextView,
        layout_marginTop = "6dp",
        text = res.string.modules,
        textColor = ColorUtil.getColorPrimary(),
        textSize = "18dp",
    },
    {
        ChipGroup,
        style = MDC_R.style.Widget_Material3_ChipGroup,
        {
            Chip,
            text = "TimeMeter",
            id = "module_time",
            TooltipText = "vinx",
            Checkable = true,
            CheckedIconEnabled = true,
            style = MDC_R.style.Widget_Material3_Chip,
        },
        {
            Chip,
            text = "Array",
            id = "module_array",
            TooltipText = "vinx",
            Checkable = true,
            CheckedIconEnabled = true,
            style = MDC_R.style.Widget_Material3_Chip,
        },
        {
            Chip,
            text = "Strings",
            id = "module_strings",
            TooltipText = "Vinx",
            Checkable = true,
            CheckedIconEnabled = true,
            style = MDC_R.style.Widget_Material3_Chip,
        },
        {
            Chip,
            text = "ObjectAnimator",
            id = "module_anim",
            TooltipText = "Vinx",
            Checkable = true,
            CheckedIconEnabled = true,
            style = MDC_R.style.Widget_Material3_Chip,
        },
        {
            Chip,
            text = "RxLua",
            id = "module_rxlua",
            TooltipText = "bjornbytes",
            Checkable = true,
            CheckedIconEnabled = true,
            style = MDC_R.style.Widget_Material3_Chip,
        },
    },
}
