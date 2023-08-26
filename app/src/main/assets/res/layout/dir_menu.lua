local ColorStateList = bindClass "android.content.res.ColorStateList";
local MaterialCardView = bindClass "com.google.android.material.card.MaterialCardView"
local MaterialTextView = bindClass "com.google.android.material.textview.MaterialTextView";
local MaterialButton = bindClass "com.google.android.material.button.MaterialButton"
local MaterialDivider = bindClass "com.google.android.material.divider.MaterialDivider"
local GradientDrawable = bindClass "android.graphics.drawable.GradientDrawable"
local LinearLayout = bindClass "android.widget.LinearLayout";

local ColorBackground = ColorUtil.getColorSurfaceVariant();
local ColorPrimary = ColorUtil.getColorPrimary();
local ColorText = ColorUtil.getColorOnSurfaceVariant();
local ColorRipple = ColorUtil.getColorSecondaryVariant();
local:res

local function dp2px(dpValue)
  local scale = activity.getResources().getDisplayMetrics().scaledDensity
  return dpValue * scale + 0.5
end

local p20=dp2px(20)

return {
  MaterialCardView,
  layout_width="match",
  layout_height="wrap",
  strokeWidth=0,
  backgroundDrawable=GradientDrawable().setShape(0).setColor(ColorUtil.getColorSurfaceVariant()).setCornerRadii{p20,p20,p20,p20,0,0,0,0};
  {
    LinearLayout,
    layout_width="match",
    layout_height="match",
    orientation="vertical",
    padding="20dp",
    {
      MaterialTextView,
      textSize="18sp",
      textStyle="bold",
      id="nameText",
    },
    {
      MaterialTextView,
      textSize="14sp",
      id="pathText",
    },
    {
      MaterialDivider,
      layout_marginTop="6dp",
      layout_marginBottom="6dp",
      dividerColor=ColorText,
    },
    {
      MaterialButton,
      layout_width="match",
      layout_height="wrap",
      BackgroundTintList=ColorStateList.valueOf(ColorBackground),
      id="button_delete",
      text=res.string.delete,
      textColor=ColorText,
      icon=DrawableUtil.getDrawable("delete"),
      iconTint=ColorStateList.valueOf(ColorPrimary),
      RippleColor=ColorStateList.valueOf(ColorRipple),
    },
    {
      MaterialButton,
      layout_width="match",
      layout_height="wrap",
      BackgroundTintList=ColorStateList.valueOf(ColorBackground),
      id="button_rename",
      text=res.string.rename,
      textColor=ColorText,
      icon=DrawableUtil.getDrawable("rename"),
      iconTint=ColorStateList.valueOf(ColorPrimary),
      RippleColor=ColorStateList.valueOf(ColorRipple),
    },
    {
      MaterialButton,
      layout_width="match",
      layout_height="wrap",
      BackgroundTintList=ColorStateList.valueOf(ColorBackground),
      id="button_cdir",
      text="新建子文件夹",
      textColor=ColorText,
      icon=DrawableUtil.getDrawable("new_folder"),
      iconTint=ColorStateList.valueOf(ColorPrimary),
      RippleColor=ColorStateList.valueOf(ColorRipple),
    },
    {
      MaterialButton,
      layout_width="match",
      layout_height="wrap",
      BackgroundTintList=ColorStateList.valueOf(ColorBackground),
      id="button_cfile",
      text="新建子文件",
      textColor=ColorText,
      icon=DrawableUtil.getDrawable("new_file"),
      iconTint=ColorStateList.valueOf(ColorPrimary),
      RippleColor=ColorStateList.valueOf(ColorRipple),
    },
  },
}
