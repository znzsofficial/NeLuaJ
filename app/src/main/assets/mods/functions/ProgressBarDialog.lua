local MaterialAlertDialogBuilder = bindClass "com.google.android.material.dialog.MaterialAlertDialogBuilder"
local ProgressBar = bindClass "android.widget.ProgressBar"
local ColorDrawable = bindClass "android.graphics.drawable.ColorDrawable"

local function ProgressBarDialog()
  local d = MaterialAlertDialogBuilder(activity)
  .setView(loadlayout({
    ProgressBar;
    style=android.R.attr.progressBarStyleLarge;
    layout_width="56dp";
    layout_height="56dp";
  }))

  d = d.show()

  d.getWindow()
  .setBackgroundDrawable(ColorDrawable(0x00000000))

  return d
end

return ProgressBarDialog