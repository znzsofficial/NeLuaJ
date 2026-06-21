package com.androlua.activity

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.PermissionInfo
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.androlua.CallLuaFunction
import com.androlua.LuaActivity

class LuaActivityPermissions(private val activity: LuaActivity) {
    
    companion object {
        private const val STORAGE_CALLBACK_FUNCTION = "onStorageRequestResult"
    }
    
    // Launcher 用于处理从 MANAGE_EXTERNAL_STORAGE 设置页返回的事件
    private val manageStoragePermissionLauncher: ActivityResultLauncher<Intent> =
        activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            // 当用户从设置页返回，我们检查权限的最终状态并回调Lua
            val isGranted = checkStoragePermission()
            activity.runFunc(STORAGE_CALLBACK_FUNCTION, isGranted)
        }
    
    // Launcher 用于处理 READ/WRITE_EXTERNAL_STORAGE 权限申请的回调
    private val requestLegacyPermissionsLauncher: ActivityResultLauncher<Array<String>> =
        activity.registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { permissions ->
            // 检查所有请求的权限是否都已被授予
            val isGranted = permissions.entries.all { it.value }
            activity.runFunc(STORAGE_CALLBACK_FUNCTION, isGranted)
        }
    
    fun checkAllPermissions(): Boolean {
        if (activity.checkCallingOrSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            try {
                // 获取应用在 Manifest 中声明的所有权限
                val requestedPermissions = activity.packageManager.getPackageInfo(
                    activity.packageName,
                    PackageManager.GET_PERMISSIONS
                ).requestedPermissions
                
                // 筛选出需要请求的危险权限
                val permissionsToRequest = requestedPermissions?.mapNotNull { permissionName ->
                    try {
                        val pInfo = activity.packageManager.getPermissionInfo(permissionName, 0)
                        val protection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            pInfo.protection
                        } else {
                            @Suppress("DEPRECATION")
                            pInfo.protectionLevel and PermissionInfo.PROTECTION_MASK_BASE
                        }
                        if (protection == PermissionInfo.PROTECTION_DANGEROUS) {
                            // 确认该权限当前是否尚未被授予
                            if (activity.checkCallingOrSelfPermission(permissionName) != PackageManager.PERMISSION_GRANTED) {
                                permissionName // 如果是需要请求的危险权限，则返回权限名
                            } else {
                                null // 如果已授予，则返回 null
                            }
                        } else {
                            null // 如果不是危险权限，则返回 null
                        }
                    } catch (e: PackageManager.NameNotFoundException) {
                        // 这个权限名在系统中找不到，忽略它
                        e.printStackTrace()
                        null
                    }
                } ?: emptyList() // 如果 requestedPermissions 为 null, 则返回一个空列表
                
                // 如果有需要请求的权限，则发起请求
                if (permissionsToRequest.isNotEmpty()) {
                    activity.requestPermissions(permissionsToRequest.toTypedArray(), 0)
                    return false // 返回 false，表示权限请求已发出，等待用户响应
                }
                
            } catch (e: Exception) {
                // 捕获 getPackageInfo 可能抛出的异常
                e.printStackTrace()
            }
        }
        // 如果所有权限都已满足，或没有需要请求的权限，返回 true
        return true
    }
    
    fun checkPermission(permission: String?) {
        if (activity.checkCallingOrSelfPermission(permission!!) != PackageManager.PERMISSION_GRANTED) {
            // 注意：这里需要访问LuaActivity的permissions字段，但为了保持封装性，我们暂时不处理
            // 实际上这个方法在原始代码中也没有被使用
        }
    }
    
    /**
     * 内部会自动判断Android版本，发起正确的权限申请流程。
     * 结果将通过全局Lua函数 onPermissionResult(isGranted) 异步返回。
     */
    @CallLuaFunction
    fun requestStoragePermission() {
        if (checkStoragePermission()) {
            // 如果已经有权限，直接同步回调成功
            activity.runFunc(STORAGE_CALLBACK_FUNCTION, true)
            return
        }
        
        // 根据版本选择不同的申请策略
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11+，申请 MANAGE_EXTERNAL_STORAGE
            requestManageStoragePermission()
        } else {
            // Android 6-10，申请 READ/WRITE_EXTERNAL_STORAGE
            requestLegacyStoragePermissions()
        }
    }
    
    fun checkStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11+
            Environment.isExternalStorageManager()
        } else {
            // Android 10 及以下
            val readPermission =
                ContextCompat.checkSelfPermission(activity, Manifest.permission.READ_EXTERNAL_STORAGE)
            val writePermission =
                ContextCompat.checkSelfPermission(activity, Manifest.permission.WRITE_EXTERNAL_STORAGE)
            readPermission == PackageManager.PERMISSION_GRANTED && writePermission == PackageManager.PERMISSION_GRANTED
        }
    }
    
    /**
     * 申请 Android 11+ 的 MANAGE_EXTERNAL_STORAGE 权限。
     */
    private fun requestManageStoragePermission() {
        try {
            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
            intent.data = Uri.parse("package:${activity.packageName}")
            manageStoragePermissionLauncher.launch(intent)
        } catch (e: Exception) {
            val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
            manageStoragePermissionLauncher.launch(intent)
        }
    }
    
    /**
     * 申请 Android 6-10 的 READ/WRITE 权限。
     */
    private fun requestLegacyStoragePermissions() {
        val permissions = arrayOf(
            Manifest.permission.READ_EXTERNAL_STORAGE,
            Manifest.permission.WRITE_EXTERNAL_STORAGE
        )
        requestLegacyPermissionsLauncher.launch(permissions)
    }
}