package com.nekolaska.internal

import android.content.Context
import dalvik.system.DexFile
import java.io.BufferedReader
import java.io.File
import java.io.FileReader
import java.io.IOException

class ClassNamesReader(private val context: Context) {

    /**
     * 解析系统预加载类列表文件 (/system/etc/preloaded-classes)
     */
    val preloadedClasses: MutableList<String> by lazy {

        val preloadedClasses = mutableListOf<String>()
        val preloadedClassesFile = File("/system/etc/preloaded-classes")

        if (!preloadedClassesFile.exists() || !preloadedClassesFile.canRead()) {
            emptyList<String>()
        }

        try {
            BufferedReader(FileReader(preloadedClassesFile)).use { reader ->
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    val trimmedLine = line!!.trim()
                    if (trimmedLine.isNotEmpty() && !trimmedLine.startsWith("#")) {
                        preloadedClasses.add(trimmedLine)
                    }
                }
            }
        } catch (e: IOException) {
            e.printStackTrace()
        }

        preloadedClasses
    }

    /**
     * 获取当前应用的所有类列表。
     */
    val appClasses by lazy {
        val ret = mutableListOf<String>()
        try {
            val dex = DexFile(context.packageCodePath)
            val cls = dex.entries()
            while (cls.hasMoreElements()) {
                ret.add(cls.nextElement())
            }
        } catch (_: IOException) {
        }
        ret.toTypedArray()
    }

    /**
     * @param className 要检查的字符串。
     * @return 如果字符串符合模式，则返回 true，否则返回 false。
     */
    private fun endsWithDollarNumber(className: String): Boolean {
        // 找到最后一个 '$' 字符的索引。
        val lastDollarIndex = className.lastIndexOf('$')

        // 如果没有'$'，或者'$'是最后一个字符，那么它不符合我们的模式。
        if (lastDollarIndex == -1 || lastDollarIndex == className.length - 1) {
            return false
        }

        // 获取 '$' 后面的子字符串。
        val suffix = className.substring(lastDollarIndex + 1)

        // 检查这个子字符串是否全由数字组成。
        return suffix.all { it.isDigit() }
    }

    val allNames by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        (preloadedClasses + appClasses)
            .distinct()
            .filterNot { it.contains("ExternalSyntheticLambda") }
            .filterNot { endsWithDollarNumber(it) }
            .filterNot { it.startsWith('[') }
            .filterNot { it.endsWith("-IA") }
            .sorted()
    }

    val allTopNames by lazy {
        allNames.filterNot { it.contains('$') }
    }

    val allTopSimpleNames by lazy {
        allTopNames.map { it.substringAfterLast('.') }.distinct().sorted()
    }
}