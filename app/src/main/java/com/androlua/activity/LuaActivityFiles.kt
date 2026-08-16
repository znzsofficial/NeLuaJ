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
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.compiler.DumpState
import org.luaj.lib.jse.JsePlatform
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.FileAlreadyExistsException
import java.nio.file.StandardCopyOption

class LuaActivityFiles(private val activity: LuaActivity) {

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
    
    fun dumpFile(input: String?, output: String?): LuaTable =
        LuaBytecodeCompiler.compile(input, output).toLuaTable()
}

internal data class LuaBytecodeCompileResult(
    val ok: Boolean,
    val output: String,
    val error: String = "",
    val line: Int? = null
) {
    fun toLuaTable() = LuaTable().apply {
        set("ok", LuaValue.valueOf(ok))
        set("output", LuaValue.valueOf(output))
        set("error", LuaValue.valueOf(error))
        line?.takeIf { it > 0 }?.let { set("line", LuaValue.valueOf(it)) }
    }
}

internal object LuaBytecodeCompiler {
    private val globals by lazy { JsePlatform.standardGlobals() }
    private val syntaxError = Regex("(\\d+):\\s*syntax error:\\s*([^\\r\\n]*)", RegexOption.IGNORE_CASE)

    @Synchronized
    fun compile(inputPath: String?, outputPath: String?): LuaBytecodeCompileResult {
        if (inputPath.isNullOrBlank() || outputPath.isNullOrBlank()) {
            return LuaBytecodeCompileResult(false, outputPath.orEmpty(), "Input or output path is empty")
        }

        val input = File(inputPath)
        val output = File(outputPath)
        if (!input.isFile) {
            return LuaBytecodeCompileResult(false, output.absolutePath, "Source file does not exist: ${input.absolutePath}")
        }
        if (input.canonicalFile == output.canonicalFile) {
            return LuaBytecodeCompileResult(false, output.absolutePath, "Output path must differ from source path")
        }

        val bytecode = try {
            compileBytecode(input.absolutePath)
        } catch (error: Exception) {
            val diagnostic = diagnostic(error)
            return LuaBytecodeCompileResult(false, output.absolutePath, diagnostic.first, diagnostic.second)
        }

        val parent = output.absoluteFile.parentFile
            ?: return LuaBytecodeCompileResult(false, output.absolutePath, "Output directory is unavailable")
        if (!parent.exists() && !parent.mkdirs()) {
            return LuaBytecodeCompileResult(false, output.absolutePath, "Cannot create output directory: ${parent.absolutePath}")
        }

        val temp = File(parent, ".luac-${System.nanoTime()}.tmp")
        return try {
            FileOutputStream(temp).use { stream ->
                stream.write(bytecode)
                stream.fd.sync()
            }
            replaceOutput(temp, output)
            LuaBytecodeCompileResult(true, output.absolutePath)
        } catch (error: Exception) {
            LuaBytecodeCompileResult(
                false,
                output.absolutePath,
                error.message?.trim().orEmpty().ifEmpty { error.javaClass.simpleName }
            )
        } finally {
            temp.delete()
        }
    }

    private fun compileBytecode(path: String): ByteArray {
        val closure = globals.loadfile(path).checkfunction(1) as LuaClosure
        return ByteArrayOutputStream().use { stream ->
            try {
                DumpState.dump(closure.c, stream, true)
                stream.toByteArray()
            } catch (error: Exception) {
                throw LuaError(error)
            }
        }
    }

    private fun replaceOutput(temp: File, output: File) {
        try {
            Files.move(
                temp.toPath(),
                output.toPath(),
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING
            )
        } catch (_: AtomicMoveNotSupportedException) {
            Files.move(temp.toPath(), output.toPath(), StandardCopyOption.REPLACE_EXISTING)
        } catch (_: UnsupportedOperationException) {
            Files.move(temp.toPath(), output.toPath(), StandardCopyOption.REPLACE_EXISTING)
        } catch (_: FileAlreadyExistsException) {
            Files.move(temp.toPath(), output.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }

    private fun diagnostic(error: Throwable): Pair<String, Int?> {
        val messages = generateSequence(error) { it.cause }
            .mapNotNull { it.message?.trim() }
            .filter { it.isNotEmpty() }
            .toList()
        for (message in messages.asReversed()) {
            val match = syntaxError.find(message) ?: continue
            val line = match.groupValues[1].toIntOrNull()
            val detail = match.groupValues[2].trim().ifEmpty { "syntax error" }
            return detail to line
        }
        val message = messages.lastOrNull()
            ?.substringBefore("\nstack traceback:")
            ?.replace(Regex("^org\\.luaj\\.[\\w.$]+:\\s*"), "")
            ?.trim()
            .orEmpty()
        return message.ifEmpty { error.javaClass.simpleName } to null
    }
}
