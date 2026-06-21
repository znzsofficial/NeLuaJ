package com.androlua.activity

import android.content.ComponentName
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import androidx.core.net.toUri
import com.androlua.CallLuaFunction
import com.androlua.LuaActivity
import com.androlua.LuaService
import org.luaj.LuaError
import java.io.File
import java.io.FileNotFoundException

class LuaActivityServices(private val activity: LuaActivity) {
    
    companion object {
        private const val ARG = "arg"
        private const val NAME = "name"
    }
    
    fun bindService(flag: Int) =
        activity.bindService(object : ServiceConnection {
            @CallLuaFunction
            override fun onServiceConnected(comp: ComponentName?, binder: IBinder) {
                activity.runFunc("onServiceConnected", comp, (binder as LuaService.LuaBinder).service)
            }
            
            @CallLuaFunction
            override fun onServiceDisconnected(comp: ComponentName?) {
                activity.runFunc("onServiceDisconnected", comp)
            }
        }, flag)
    
    
    fun bindService(conn: ServiceConnection, flag: Int): Boolean {
        val service = Intent(activity, LuaService::class.java)
        var path = "service.lua"
        service.putExtra(NAME, path)
        if (activity.luaRootDir != null) path = "${activity.luaRootDir}/$path"
        val f = File(path)
        if (f.isDirectory() && File("$path/service.lua").exists()) path += "/service.lua"
        else if ((f.isDirectory() || !f.exists()) && !path.endsWith(".lua")) path += ".lua"
        if (!File(path).exists()) throw LuaError(FileNotFoundException(path))
        
        service.setData("file://$path".toUri())
        
        return activity.bindService(service, conn, flag)
    }
    
    fun stopService(): Boolean {
        return activity.stopService(Intent(activity, LuaService::class.java))
    }
    
    @JvmOverloads
    fun startService(
        path: String? = null,
        arg: Array<Any?>? = null
    ): ComponentName? {
        if (path == null) {
            // 如果 path 为 null，直接创建不带文件路径的 Intent
            val intent = Intent(activity, LuaService::class.java)
            arg?.let { intent.putExtra(ARG, it) } // 如果 arg 不为 null，则添加它
            return activity.startService(intent)
        }
        
        // path 不为 null 的情况，执行原始的文件逻辑
        var finalPath = path
        val intent = Intent(activity, LuaService::class.java)
        intent.putExtra(NAME, finalPath) // 使用原始 path 作为 NAME
        
        // 路径处理逻辑
        if (finalPath[0] != '/' && activity.luaRootDir != null) {
            finalPath = "${activity.luaRootDir}/$finalPath"
        }
        
        val f = File(finalPath)
        if (f.isDirectory && File("$finalPath/service.lua").exists()) {
            finalPath += "/service.lua"
        } else if ((f.isDirectory || !f.exists()) && !finalPath.endsWith(".lua")) {
            finalPath += ".lua"
        }
        
        if (!File(finalPath).exists()) {
            throw LuaError(FileNotFoundException("Service file not found: $finalPath"))
        }
        
        // 使用处理后的 finalPath 设置 URI
        intent.setData("file://$finalPath".toUri())
        
        arg?.let { intent.putExtra(ARG, it) }
        
        return activity.startService(intent)
    }
}