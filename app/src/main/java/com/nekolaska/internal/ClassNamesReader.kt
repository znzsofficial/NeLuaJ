package com.nekolaska.internal

import android.content.Context
import dalvik.system.DexFile
import java.io.File
import java.io.IOException

class ClassNamesReader(private val context: Context) {

    // 使用 Set 存储补充类，可以天然去重，且查找效率更高。
    private val supplements: Set<String> = setOf(
        "android.widget.GridView",
        "android.widget.GridView\$InspectionCompanion",
        "android.widget.GridView\$StretchMode",
    )

    /**
     * 解析系统预加载类列表文件 (/system/etc/preloaded-classes)。
     * 返回一个不可变的列表。
     */
    val preloadedClasses: List<String> by lazy {
        val preloadedClassesFile = File("/system/etc/preloaded-classes")
        if (!preloadedClassesFile.exists() || !preloadedClassesFile.canRead()) {
            supplements.toList() // 如果文件不存在，只返回补充列表
        }

        try {
            val classNames = preloadedClassesFile.useLines { lines ->
                lines.map { it.trim() }
                    .filter { it.isNotEmpty() && !it.startsWith("#") }
                    .toSet() // 先转为 Set 去重
            }
            (classNames + supplements).toList() // 合并并转为 List
        } catch (e: IOException) {
            e.printStackTrace()
            supplements.toList() // 出现异常时，同样只返回补充列表
        }
    }

    /**
     * 获取当前应用的所有类列表。
     * 返回一个不可变的列表。
     */
    val appClasses: List<String> by lazy {
        try {
            DexFile(context.packageCodePath).entries().asSequence().toList()
        } catch (e: IOException) {
            e.printStackTrace()
            emptyList()
        }
    }

    /**
     * 获取所有经过过滤和排序的类名。
     * 使用 asSequence() 可以优化长链式操作的性能，避免为每个 filter/map 操作创建中间列表。
     */
    val allNames: List<String> by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        (preloadedClasses.asSequence() + appClasses.asSequence())
            .distinct()
            .filterNot(::isFilteredClassName)
            .sorted()
            .toList()
    }

    /**
     * 获取所有顶层类（不含内部类）的完整名称。
     */
    val allTopNames: List<String> by lazy {
        allNames.filterNot { it.contains('$') }
    }

    /**
     * 获取所有顶层类的简单名称（无包名），并去重排序。
     */
    val allTopSimpleNames: List<String> by lazy {
        allTopNames.asSequence()
            .map { it.substringAfterLast('.') }
            .distinct()
            .sorted()
            .toList()
    }

    /**
     * 检查类名是否应该被过滤掉。
     * 将过滤逻辑聚合到一个方法中，使 `allNames` 的初始化代码更清晰。
     * @param className 要检查的类名。
     * @return 如果类名应被过滤，则返回 true。
     */
    private fun isFilteredClassName(className: String): Boolean {
        return className.contains("ExternalSyntheticLambda") ||
                className.startsWith('[') ||
                className.endsWith("-IA") ||
                endsWithDollarNumber(className)
    }

    /**
     * 检查字符串是否以 '$' 和一个或多个数字结尾（例如匿名内部类）。
     * @param className 要检查的字符串。
     * @return 如果字符串符合模式，则返回 true，否则返回 false。
     */
    private fun endsWithDollarNumber(className: String): Boolean {
        val lastDollarIndex = className.lastIndexOf('$')
        if (lastDollarIndex == -1 || lastDollarIndex == className.length - 1) {
            return false
        }
        // 截取 '$' 后的部分并检查是否全为数字
        return className.substring(lastDollarIndex + 1).all(Char::isDigit)
    }
}