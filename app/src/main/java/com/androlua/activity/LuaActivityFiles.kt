package com.androlua.activity

import android.annotation.SuppressLint
import android.content.Intent
import android.content.res.XmlResourceParser
import android.net.Uri
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import com.androlua.LuaActivity
import org.luaj.LuaClosure
import org.luaj.LuaError
import org.luaj.LuaFunction
import org.luaj.compiler.DumpState
import org.luaj.lib.jse.JsePlatform
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream

class LuaActivityFiles(private val activity: LuaActivity) {
    
    private val dumpGlobals by lazy { JsePlatform.standardGlobals() }
    
    fun findResource(name: String): InputStream? {
        try {
            val file = File(name)
            if (file.exists()) return FileInputStream(file)
        } catch (_: Exception) {
        }
        try {
            val file = File(activity.luaDir, name)
            if (file.exists()) return FileInputStream(file)
        } catch (_: Exception) {
        }
        try {
            val file = File(activity.luaRootDir ?: activity.luaDir, name)
            if (file.exists()) return FileInputStream(file)
        } catch (_: Exception) {
        }
        try {
            return activity.assets.open(name)
        } catch (_: Exception) {
        }
        return null
    }
    
    fun checkResource(name: String): Boolean {
        try {
            if (File(name).exists()) return true
        } catch (_: Exception) {
        }
        try {
            if (File(activity.luaDir, name).exists()) return true
        } catch (_: Exception) {
        }
        try {
            return File(activity.luaRootDir ?: activity.luaDir, name).exists()
        } catch (_: Exception) {
        }
        try {
            val stream = activity.assets.open(name)
            stream.close()
            return true
        } catch (_: Exception) {
        }
        return false
    }
    
    fun findFile(filename: String): String {
        if (filename.startsWith("/")) return filename
        val scriptFile = File(activity.luaDir, filename)
        if (scriptFile.exists()) return scriptFile.absolutePath
        return File(activity.luaRootDir ?: activity.luaDir, filename).absolutePath
    }
    
    fun getUriForPath(path: String): Uri? {
        return FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", File(path))
    }
    
    fun getUriForFile(path: File): Uri? {
        return FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", path)
    }
    
    fun getPathFromUri(uri: Uri?): String? {
        var path: String? = null
        uri?.let { u ->
            val p = arrayOf(MediaStore.Images.Media.DATA)
            when (u.scheme) {
                "content" -> {
                    val cursor = activity.contentResolver.query(u, p, null, null, null)
                    cursor?.use {
                        val idx = it.getColumnIndexOrThrow(MediaStore.Images.Media.DATA)
                        if (idx >= 0) {
                            it.moveToFirst()
                            path = it.getString(idx)
                        }
                    }
                }
                "file" -> {
                    path = u.path
                }
            }
        }
        return path
    }
    
    private fun getType(file: File): String {
        val lastDot = file.getName().lastIndexOf(46.toChar())
        if (lastDot >= 0) {
            val extension = file.getName().substring(lastDot + 1)
            val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            if (mime != null) {
                return mime
            }
        }
        return "application/octet-stream"
    }
    
    @JvmOverloads
    fun openFile(path: String, callback: LuaFunction? = null) {
        val file = File(path)
        // 创建Intent并设置相关标志和类型
        val intent = Intent(Intent.ACTION_VIEW).apply {
            flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_ACTIVITY_NEW_TASK
            setDataAndType(getUriForFile(file), getType(file))
        }
        if (callback != null) {
            if (intent.resolveActivity(activity.packageManager) != null) {
                activity.startActivity(intent)
            } else {
                callback.call()
            }
        } else activity.startActivity(intent)
    }
    
    fun startPackage(pkg: String): Boolean {
        return activity.packageManager.getLaunchIntentForPackage(pkg)
            ?.let { activity.startActivity(it); true } == true
    }
    
    fun installApk(path: String) {
        val share = Intent(Intent.ACTION_VIEW)
        val file = File(path)
        share.setFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        share.setDataAndType(getUriForFile(file), getType(file))
        share.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        activity.startActivity(share)
    }
    
    fun shareFile(path: String) {
        val share = Intent(Intent.ACTION_SEND)
        val file = File(path)
        share.setType("*/*")
        share.setFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        share.putExtra(Intent.EXTRA_STREAM, getUriForFile(file))
        activity.startActivity(
            Intent.createChooser(share, file.getName()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }
    
    fun getMediaDir() = activity.externalMediaDirs[0]!!
    
    @SuppressLint("DiscouragedPrivateApi")
    @Suppress("PrivateApi")
    fun loadXmlView(file: File) =
        runCatching {
            val cls = Class.forName("android.content.res.XmlBlock")
            val declaredMethod = cls.getDeclaredMethod("newParser")
            declaredMethod.isAccessible = true
            activity.layoutInflater.inflate(
                declaredMethod.invoke(cls.getConstructor(ByteArray::class.java).apply {
                    isAccessible = true
                }.newInstance(file.readBytes())) as XmlResourceParser,
                null
            )
        }.getOrNull()
    
    private fun getByteArray(path: String?): ByteArray {
        val closure = dumpGlobals.loadfile(path).checkfunction(1) as LuaClosure
        val stream = ByteArrayOutputStream()
        return try {
            DumpState.dump(closure.c, stream, true)
            stream.toByteArray()
        } catch (e: Exception) {
            throw LuaError(e)
        }
    }
    
    fun dumpFile(input: String?, output: String?) {
        try {
            val fos = FileOutputStream(output)
            fos.write(getByteArray(input))
            fos.close()
        } catch (e: IOException) {
            activity.sendError("dumpFile", e)
        }
    }
}