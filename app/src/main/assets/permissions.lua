return function()
  local PackageManager=luajava.bindClass"android.content.pm.PackageManager"
  local String=luajava.bindClass"java.lang.String"
  local ArrayList=luajava.bindClass"java.util.ArrayList"
  local mAppPermissions = ArrayList()

  local mAppPermissionsTable = luajava.astable(activity.getPackageManager().getPackageInfo(activity.getPackageName(),PackageManager.GET_PERMISSIONS).requestedPermissions)

  for k,v in pairs(mAppPermissionsTable) do

    mAppPermissions.add(v)

  end

  local size = mAppPermissions.size()

  local mArray = mAppPermissions.toArray(String[size])

  activity.requestPermissions(mArray,0)

  local Build = bindClass "android.os.Build"
  local Environment = bindClass "android.os.Environment"
  if (Build.VERSION.SDK_INT >= 30) then
    try
      if not (Environment.isExternalStorageManager()) then
        import "com.google.android.material.dialog.MaterialAlertDialogBuilder"
        MaterialAlertDialogBuilder(activity)
        .setTitle(res.string.tip)
        .setMessage(res.string.need_manage_permission)
        .setPositiveButton(android.R.string.ok, function()
          local Intent = bindClass "android.content.Intent"
          local Uri = bindClass "android.net.Uri"
          local Settings = bindClass "android.provider.Settings"
          local intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
          intent.setData(Uri.parse("package:" .. activity.getPackageName()));
          activity.startActivityForResult(intent, 2296);
        end)
        .setNegativeButton(android.R.string.cancel, nil)
        .show();
      end
    end
  end
end