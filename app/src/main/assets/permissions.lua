return function()
  local permission = android.Manifest.permission
    activity.requestPermissions({
        permission.WRITE_EXTERNAL_STORAGE,
        permission.READ_EXTERNAL_STORAGE,
        permission.INTERNET,
        permission.ACCESS_NETWORK_STATE,
        permission.ACCESS_WIFI_STATE,
        permission.READ_PHONE_STATE,
        permission.CAMERA,
        permission.RECORD_AUDIO,
        permission.MODIFY_AUDIO_SETTINGS,
        permission.WAKE_LOCK,
        permission.VIBRATE,
        permission.REQUEST_INSTALL_PACKAGES,
        permission.BLUETOOTH_SCAN,
        permission.BLUETOOTH_CONNECT,
        permission.BLUETOOTH_ADVERTISE,
    }, 0)

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