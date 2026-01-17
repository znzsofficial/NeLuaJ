package org.luaj.android

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.webkit.MimeTypeMap
import androidx.activity.result.ActivityResult
import androidx.activity.result.ActivityResultLauncher
import com.androlua.LuaActivity
import org.luaj.LuaFunction
import org.luaj.LuaString
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.Varargs
import org.luaj.lib.VarArgFunction
import java.io.ByteArrayOutputStream
import java.io.InputStream
import androidx.core.net.toUri
import com.nekolaska.ktx.m_bytes
import com.nekolaska.ktx.toLuaValue
import org.luaj.lib.OneArgFunction

class saf(private val context: LuaActivity) {
    private fun LuaFunction.safeCall(arg: LuaValue): LuaValue {
        return try {
            this.call(arg)
        } catch (e: Exception) {
            context.sendError("saf callback", e)
            LuaValue.NIL
        }
    }

    private var rootUri: Uri? = null
    private val PREF_KEY = "_DOCUMENT_TREE"

    // 回调持有者
    private var onSelectCallback: LuaFunction? = null
    private var onReadDocCallback: LuaFunction? = null
    private var onSaveDocCallback: LuaFunction? = null

    // 注册 Launcher (必须在 Activity 初始化阶段完成)
    private val treeLauncher: ActivityResultLauncher<Intent>
    private val docLauncher: ActivityResultLauncher<Intent>
    private val createLauncher: ActivityResultLauncher<Intent>

    init {
        // 1. 恢复之前保存的 URI
        val savedUriStr = context.getSharedData(PREF_KEY, null) as? String
        if (!savedUriStr.isNullOrEmpty()) {
            try {
                rootUri = savedUriStr.toUri()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        // 2. 注册选择目录的回调 (使用 LuaActivity.resultLauncher)
        treeLauncher = context.resultLauncher(object : VarArgFunction() {
            override fun invoke(args: Varargs): Varargs {
                val result = args.arg1().checkuserdata(ActivityResult::class.java) as ActivityResult
                handleTreeResult(result)
                return NIL
            }
        })

        // 3. 注册打开文件的回调
        docLauncher = context.resultLauncher(object : VarArgFunction() {
            override fun invoke(args: Varargs): Varargs {
                val result = args.arg1().checkuserdata(ActivityResult::class.java) as ActivityResult
                handleDocResult(result)
                return NIL
            }
        })

        // 4. 注册保存文件的回调
        createLauncher = context.resultLauncher(object : VarArgFunction() {
            override fun invoke(args: Varargs): Varargs {
                val result = args.arg1().checkuserdata(ActivityResult::class.java) as ActivityResult
                handleCreateResult(result)
                return NIL
            }
        })
    }

    // --- 核心功能实现 ---

    fun get(): Uri? = rootUri

    /**
     * 选择目录
     */
    fun select(callback: LuaFunction) {
        this.onSelectCallback = callback
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        treeLauncher.launch(intent)
    }

    private fun handleTreeResult(result: ActivityResult) {
        if (result.resultCode == Activity.RESULT_OK) {
            val uri = result.data?.data
            if (uri != null) {
                val takeFlags =
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                try {
                    context.contentResolver.takePersistableUriPermission(uri, takeFlags)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
                rootUri = uri
                context.setSharedData(PREF_KEY, uri.toString())
                onSelectCallback?.safeCall(uri.toLuaValue())
            } else {
                onSelectCallback?.safeCall(LuaValue.NIL)
            }
        } else {
            onSelectCallback?.safeCall(LuaValue.NIL)
        }
        onSelectCallback = null
    }

    /**
     * 列出文件 (无需 Launcher，直接查询 ContentProvider)
     */
    fun list(callback: LuaFunction) {
        val uri = rootUri
        if (uri == null) {
            // 没权限时先请求权限
            select(object : OneArgFunction() {
                override fun call(arg: LuaValue): LuaValue {
                    if (!arg.isnil()) list(callback)
                    return NIL
                }
            })
            return
        }

        try {
            // 必须使用 getTreeDocumentId 获取根目录 ID
            val docId = DocumentsContract.getTreeDocumentId(uri)
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(uri, docId)

            val fileList = LuaTable()
            var index = 1

            val cursor = context.contentResolver.query(
                childrenUri,
                arrayOf(
                    Document.COLUMN_DOCUMENT_ID,
                    Document.COLUMN_DISPLAY_NAME,
                    Document.COLUMN_MIME_TYPE,
                    Document.COLUMN_SIZE
                ),
                null, null, null
            )

            cursor?.use {
                while (it.moveToNext()) {
                    val childDocId = it.getString(0) // 获取子文件的 ID
                    val name = it.getString(1)
                    val mime = it.getString(2)
                    val size = it.getLong(3)

                    // 构建子文件的完整 URI
                    val fileUri = DocumentsContract.buildDocumentUriUsingTree(uri, childDocId)

                    val fileInfo = LuaTable().apply {
                        set("name", name)
                        set("uri", fileUri.toString())
                        set("mime", mime)
                        set("size", LuaValue.valueOf(size.toDouble()))
                        set("isDirectory", LuaValue.valueOf(mime == Document.MIME_TYPE_DIR))
                    }
                    fileList.set(index++, fileInfo)
                }
            }
            callback.safeCall(fileList)

        } catch (e: Exception) {
            e.printStackTrace()
            // 调试用：打印具体错误
            // android.util.Log.e("SAF", "List error: " + e.message)
            callback.safeCall(LuaValue.NIL)
        }
    }

    /**
     * 读取 Tree 内的文件
     */
    fun read(fileName: String): LuaValue {
        val uri = rootUri ?: return LuaValue.NIL
        val targetUri = findFileUri(uri, fileName) ?: return LuaValue.NIL
        return readFileFromUri(targetUri)
    }

    /**
     * 调用系统选择器读取文件
     */
    fun read(callback: LuaFunction) {
        this.onReadDocCallback = callback
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        docLauncher.launch(intent)
    }

    private fun handleDocResult(result: ActivityResult) {
        if (result.resultCode == Activity.RESULT_OK) {
            val uri = result.data?.data
            if (uri != null) {
                onReadDocCallback?.safeCall(readFileFromUri(uri))
            } else {
                onReadDocCallback?.safeCall(LuaValue.NIL)
            }
        } else {
            onReadDocCallback?.safeCall(LuaValue.NIL)
        }
        onReadDocCallback = null
    }

    /**
     * 保存内容到 Tree 内的文件
     */
    fun save(fileName: String, content: LuaString): LuaValue {
        val uri = rootUri
        if (uri == null) {
            // 如果没有权限，引导用户去授权
            select(object : OneArgFunction() {
                override fun call(arg: LuaValue): LuaValue {
                    if (!arg.isnil()) save(fileName, content)
                    return NIL
                }
            })
            return LuaValue.FALSE
        }

        try {
            // 1. 尝试查找现有文件
            var targetUri = findFileUri(uri, fileName)

            // 2. 如果文件不存在，则创建
            if (targetUri == null) {
                // [关键修复]：必须将 TreeUri 转换为 DocumentUri 才能作为父目录使用
                val docId = DocumentsContract.getTreeDocumentId(uri)
                val parentDocUri = DocumentsContract.buildDocumentUriUsingTree(uri, docId)

                // 根据文件名后缀猜测 MIME 类型，默认为 text/plain
                val mimeType = getMimeType(fileName)

                targetUri = DocumentsContract.createDocument(
                    context.contentResolver,
                    parentDocUri, // 这里传入转换后的 DocumentUri
                    mimeType,
                    fileName
                )
            }

            // 3. 写入内容
            if (targetUri != null) {
                context.contentResolver.openOutputStream(targetUri, "wt")?.use {
                    it.write(content.m_bytes)
                }
                return LuaValue.TRUE
            }
        } catch (e: Exception) {
            e.printStackTrace()
            // 可以在这里加个 Log 或者 Toast 方便调试
            // android.util.Log.e("Saf", "Save error: " + e.message)
        }
        return LuaValue.FALSE
    }

    // --- 辅助方法 ---

    /**
     * 简单的 MIME 类型推断
     */
    /**
     * 根据文件名后缀自动获取 MimeType
     * 默认为 "application/octet-stream" (二进制流)，比 "text/plain" 更安全
     */
    private fun getMimeType(fileName: String): String {
        val extension = MimeTypeMap.getFileExtensionFromUrl(fileName)
        if (extension != null) {
            val type = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension.lowercase())
            if (type != null) {
                return type
            }
        }
        // 如果是 .lua 文件，系统可能不识别，手动指定一下
        if (fileName.endsWith(".lua", true)) return "text/plain"

        // 默认返回二进制流，这样系统通常允许保存为任意类型
        return "application/octet-stream"
    }

    /**
     * 调用系统创建文件界面保存
     */
    fun save(fileName: String, content: LuaString, callback: LuaFunction) {
        this.onSaveDocCallback = callback
        // 这里 trick 一下，把要保存的内容暂时存在对象里，或者等回调拿到 URI 后再写入
        // 为了简单，我们只在回调里处理写入。
        // 由于 Intent 无法直接传大 bytes，这里使用闭包或者成员变量来传递 content 会比较麻烦。
        // 更好的方式是创建一个一次性的 Listener 内部类持有 content。

        // 为了适应 resultLauncher 这种单例注册模式，我们必须动态设置 Launcher 的 Intent
        // 但 ActivityResultContracts.CreateDocument 并不接受内容。
        // 方案：回调拿到 URI -> 写入。

        // 重新定义一个带 Content 的 Handle
        createHandleWrapper = { uri ->
            if (uri != null) {
                try {
                    context.contentResolver.openOutputStream(uri, "wt")?.use {
                        it.write(content.m_bytes)
                    }
                    callback.safeCall(LuaValue.TRUE)
                } catch (e: Exception) {
                    e.printStackTrace()
                    callback.safeCall(LuaValue.FALSE)
                }
            } else {
                callback.safeCall(LuaValue.FALSE)
            }
        }

        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = getMimeType(fileName)
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        createLauncher.launch(intent)
    }

    // 临时保存 save 操作的回调逻辑
    private var createHandleWrapper: ((Uri?) -> Unit)? = null

    private fun handleCreateResult(result: ActivityResult) {
        val uri = if (result.resultCode == Activity.RESULT_OK) result.data?.data else null
        createHandleWrapper?.invoke(uri)
        createHandleWrapper = null
        onSaveDocCallback = null // 清理引用
    }

    // --- 内部工具 ---

    private fun readFileFromUri(uri: Uri): LuaValue {
        return try {
            context.contentResolver.openInputStream(uri)?.use {
                LuaString.valueOf(readAllBytes(it))
            } ?: LuaValue.NIL
        } catch (e: Exception) {
            e.printStackTrace()
            LuaValue.NIL
        }
    }

    fun exists(fileName: String): Boolean {
        val uri = rootUri ?: return false
        return findFileUri(uri, fileName) != null
    }

    fun mkdir(dirName: String): Boolean {
        val uri = rootUri ?: return false
        if (exists(dirName)) return false // 已存在

        return try {
            val docId = DocumentsContract.getTreeDocumentId(uri)
            val parentUri = DocumentsContract.buildDocumentUriUsingTree(uri, docId)

            DocumentsContract.createDocument(
                context.contentResolver,
                parentUri,
                Document.MIME_TYPE_DIR, // 关键：指定 MIME 类型为文件夹
                dirName
            ) != null
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    fun delete(fileName: String): Boolean {
        val uri = rootUri ?: return false
        val targetUri = findFileUri(uri, fileName) ?: return false

        return try {
            DocumentsContract.deleteDocument(context.contentResolver, targetUri)
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    fun type(fileName: String): LuaValue {
        val uri = rootUri ?: return LuaValue.NIL
        val targetUri = findFileUri(uri, fileName) ?: return LuaValue.NIL

        return try {
            val cursor = context.contentResolver.query(
                targetUri,
                arrayOf(Document.COLUMN_MIME_TYPE),
                null, null, null
            )
            var type = "file"
            cursor?.use {
                if (it.moveToFirst()) {
                    val mime = it.getString(0)
                    if (mime == Document.MIME_TYPE_DIR) {
                        type = "directory"
                    }
                }
            }
            LuaValue.valueOf(type)
        } catch (_: Exception) {
            LuaValue.NIL
        }
    }

    fun rename(oldName: String, newName: String): Boolean {
        val uri = rootUri ?: return false
        val targetUri = findFileUri(uri, oldName) ?: return false

        return try {
            // 注意：renameDocument 实际上是重命名 Display Name
            DocumentsContract.renameDocument(context.contentResolver, targetUri, newName) != null
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun findFileUri(treeUri: Uri, displayName: String): Uri? {
        // 使用正确的 ID 构建查询子文件的 URI
        val docId = DocumentsContract.getTreeDocumentId(treeUri)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, docId)

        val cursor = context.contentResolver.query(
            childrenUri,
            arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME),
            null, null, null
        )
        cursor?.use {
            while (it.moveToNext()) {
                val name = it.getString(1)
                if (name == displayName) {
                    val fileId = it.getString(0)
                    // 构建找到的文件的 URI
                    return DocumentsContract.buildDocumentUriUsingTree(treeUri, fileId)
                }
            }
        }
        return null
    }

    private fun readAllBytes(inputStream: InputStream): ByteArray {
        val buffer = ByteArrayOutputStream()
        val data = ByteArray(4096)
        var nRead: Int
        while (inputStream.read(data, 0, data.size).also { nRead = it } != -1) {
            buffer.write(data, 0, nRead)
        }
        return buffer.toByteArray()
    }
}