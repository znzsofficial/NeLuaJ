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
        val permissionsToRequest = try {
            val requestedPermissions = activity.packageManager.getPackageInfo(
                activity.packageName,
                PackageManager.GET_PERMISSIONS
            ).requestedPermissions.orEmpty()
            
            requestedPermissions.filter { permissionName ->
                isDangerousPermission(permissionName) && !checkPermission(permissionName)
            }
        } catch (e: Exception) {
            activity.sendError("checkAllPermissions", e)
            emptyList()
        }
        
        if (permissionsToRequest.isNotEmpty()) {
            activity.requestPermissions(permissionsToRequest.toTypedArray(), 0)
            return false
        }
        return true
    }
    
    fun checkPermission(permission: String?): Boolean {
        if (permission.isNullOrBlank()) return false
        return ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED
    }
    
    /**
     * 内部会自动判断Android版本，发起正确的权限申请流程。
     * 结果将通过全局Lua函数 onStorageRequestResult(isGranted) 异步返回。
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
        val permissions = buildList {
            add(Manifest.permission.READ_EXTERNAL_STORAGE)
            if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P) {
                add(Manifest.permission.WRITE_EXTERNAL_STORAGE)
            }
        }.filter { !checkPermission(it) }.toTypedArray()
        if (permissions.isEmpty()) {
            activity.runFunc(STORAGE_CALLBACK_FUNCTION, true)
            return
        }
        requestLegacyPermissionsLauncher.launch(permissions)
    }
    
    private fun isDangerousPermission(permissionName: String): Boolean {
        return try {
            val permissionInfo = activity.packageManager.getPermissionInfo(permissionName, 0)
            val protection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                permissionInfo.protection
            } else {
                @Suppress("DEPRECATION")
                permissionInfo.protectionLevel and PermissionInfo.PROTECTION_MASK_BASE
            }
            protection == PermissionInfo.PROTECTION_DANGEROUS
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }
}
