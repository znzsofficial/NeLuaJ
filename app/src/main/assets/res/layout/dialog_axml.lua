import "android.widget.LinearLayout"
import "vinx.material.textfield.MaterialTextField"
import "com.google.android.material.checkbox.MaterialCheckBox"
import "res"

local colorPrimary = ColorUtil.getColorPrimary()

return {
  LinearLayout,
  orientation="vertical",
  layout_width="match",
  layout_height="match",
  paddingLeft="20dp",
  paddingTop="20dp",
  paddingRight="20dp",
  Focusable=true,
  FocusableInTouchMode=true,
  {
    MaterialTextField,
    hint="项目路径",
    TintColor=colorPrimary,
    layout_width="fill",
    layout_height="wrap",
    textSize="12dp",
    id="path",
    style=MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox_Dense,
    text=Bean.Path.app_root_pro_dir.."/",
  },
  {
    MaterialTextField,
    layout_marginTop="16dp",
    hint="android:minSdkVersion",
    TintColor=colorPrimary,
    layout_width="fill",
    layout_height="wrap",
    textSize="12dp",
    singleLine=true,
    style=MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox_Dense,
    text="24",
    id="mSDK",
  },
  {
    MaterialTextField,
    layout_width="fill",
    layout_height="wrap",
    layout_marginTop="16dp",
    hint="android:targetSdkVersion",
    TintColor=colorPrimary,
    style=MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox_Dense,
    textSize="12dp",
    singleLine=true,
    text="31",
    id="tSDK",
  },
  {
    MaterialCheckBox,
    layout_marginTop="8dp",
    text="Debug",
    id="isDebug",
    checked=true,
  },
  {
    MaterialCheckBox,
    text="ImportProject",
    id="isImp",
    checked=false,
  },
  {
    MaterialCheckBox,
    text="Service",
    id="isSer",
    checked=false,
  },
  {
    MaterialCheckBox,
    text="DynamicPermission",
    id="isDyn",
    checked=false,
  },
}
