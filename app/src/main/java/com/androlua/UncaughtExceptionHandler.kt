package com.androlua

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.PrintWriter
import java.io.StringWriter
import java.io.Writer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * @ClassName UncaughtExceptionHandler
 * @Description 全局捕捉异常
 * @Author summerain0
 * @Date 2020/9/11 15:31
 */
class UncaughtExceptionHandler(// 上下文
    private val context: Context
) : Thread.UncaughtExceptionHandler {
    // 会输出到文件中
    private var stringBuilder: StringBuilder? = null

    // 系统异常处理器
    private var defaultUncaughtExceptionHandler: Thread.UncaughtExceptionHandler? = null

    // 初始化
    fun init() {
        defaultUncaughtExceptionHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler(this)
    }

    override fun uncaughtException(thread: Thread, throwable: Throwable) {
        // 创建集合对象
        stringBuilder = StringBuilder()

        // 记录时间
        val simpleDateFormat = SimpleDateFormat("yyyy-MM-dd_HH:mm:ss.SSS", Locale.getDefault())
        val date = simpleDateFormat.format(Date())
        addMessage("崩溃时间", date)

        // 记录应用版本信息
        try {
            val pm = context.packageManager
            val pi = pm.getPackageInfo(context.packageName, PackageManager.GET_ACTIVITIES)

            addMessage("版本名", pi.versionName)
            addMessage(
                "版本号", if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    pi.longVersionCode.toString()
                } else {
                    pi.versionCode.toString()
                }
            )
        } catch (e: PackageManager.NameNotFoundException) {
            e.printStackTrace()
            addMessage("error", "记录版本信息失败！" + e.message)
        }

        // 记录设备信息
        for (field in Build::class.java.declaredFields) {
            try {
                field.isAccessible = true
                val obj = field[null]
                if (obj != null) {
                    addMessage(field.name, obj)
                }
            } catch (e: IllegalAccessException) {
                e.printStackTrace()
                addMessage("error", "记录设备信息失败！" + e.message)
            }
        }

        // 添加分隔符
        addMessage(null, "崩溃日志:")

        // 记录崩溃信息
        val writer: Writer = StringWriter()
        val printWriter = PrintWriter(writer)
        throwable.printStackTrace(printWriter)
        var cause = throwable.cause
        while (cause != null) {
            cause.printStackTrace(printWriter)
            cause = cause.cause
        }
        printWriter.close()
        addMessage(null, writer.toString())

        try {
            val path =
                (context.applicationContext.externalMediaDirs[0] as File).absolutePath + "/crash/"
            val filename = "$date.log"
            val file = File(path, filename)
            val fos = FileOutputStream(file)
            fos.write(stringBuilder.toString().toByteArray())
            fos.close()
        } catch (e: IOException) {
            e.printStackTrace()
            defaultUncaughtExceptionHandler!!.uncaughtException(thread, throwable)
        }

        // 启动崩溃异常页面
        val intent = Intent(context, UncaughtExceptionActivity::class.java)
        intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK) // 请勿修改，否则无法打开页面
        intent.putExtra("error", stringBuilder.toString())
        context.startActivity(intent)
        System.exit(1) // 请勿修改，否则无法打开页面
    }

    // 添加数据
    private fun addMessage(key: String?, obj: Any) {
        // 对数组做一下处理
        if (obj is Array<*>) {
            stringBuilder!!.append(key).append("= [")
            obj.forEach {
                stringBuilder!!.append(it).append(", ")
            }
            stringBuilder!!.append(" ]\n")
        }
        // 其他的都直接添加
        if (key == null) {
            stringBuilder!!.append(obj)
                .append("\n")
        } else {
            stringBuilder!!.append(key)
                .append("=")
                .append(obj)
                .append("\n")
        }
    }

    companion object {
        @SuppressLint("StaticFieldLeak")
        private var instance: UncaughtExceptionHandler? = null

        @JvmStatic
        fun getInstance(ctx: Context): UncaughtExceptionHandler {
            return instance ?: synchronized(this) {
                instance ?: UncaughtExceptionHandler(ctx).also { instance = it }
            }
        }
    }
}