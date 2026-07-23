package com.androlua.layout

import java.lang.reflect.Method
import java.lang.reflect.Modifier
import java.util.concurrent.ConcurrentHashMap

/**
 * loadlayout 反射辅助：属性可写性、Method 缓存。
 */
internal object LayoutReflection {

    private val NO_METHOD = Any()

    private val classPropertyNames = ConcurrentHashMap<Class<*>, Set<String>>()
    private val booleanSetterCache = ConcurrentHashMap<String, Any>()
    private val floatSetterCache = ConcurrentHashMap<String, Any>()
    private val intSetterCache = ConcurrentHashMap<String, Any>()
    private val colorStateListSetterCache = ConcurrentHashMap<String, Any>()
    private val objectSetterCache = ConcurrentHashMap<String, Any>()

    fun propertyNamesFor(clazz: Class<*>): Set<String> {
        return classPropertyNames.computeIfAbsent(clazz) {
            val names = HashSet<String>(64)
            for (m in clazz.methods) {
                if (Modifier.isStatic(m.modifiers)) continue
                // setXxx(T) 与 setLineSpacing(float,float) 等均视为可写属性名
                if (m.parameterTypes.isEmpty()) continue
                val n = m.name
                if (n.length > 3 && n.startsWith("set")) {
                    val prop = n.substring(3)
                    names.add(prop)
                    if (prop.isNotEmpty() && prop[0].isUpperCase()) {
                        names.add(prop.replaceFirstChar { ch -> ch.lowercaseChar() })
                    }
                }
            }
            var c: Class<*>? = clazz
            while (c != null && c != Any::class.java) {
                for (f in c.declaredFields) {
                    if (!Modifier.isStatic(f.modifiers) && Modifier.isPublic(f.modifiers)) {
                        names.add(f.name)
                    }
                }
                c = c.superclass
            }
            names
        }
    }

    fun canSetJavaProperty(clazz: Class<*>, key: String): Boolean {
        if (key.isEmpty()) return false
        if (key.length > 2 && key[0] == 'o' && key[1] == 'n' && key[2].isUpperCase()) return true
        val names = propertyNamesFor(clazz)
        if (key in names) return true
        // 仅在首字符大小写互换时再查一次，避免无意义分配
        val c0 = key[0]
        if (!c0.isLetter()) return false
        val flipped = if (c0.isLowerCase()) c0.uppercaseChar() else c0.lowercaseChar()
        if (flipped == c0) return false
        val alt = flipped + key.substring(1)
        return alt in names
    }

    fun cachedMethod(
        cache: ConcurrentHashMap<String, Any>,
        clazz: Class<*>,
        name: String,
        vararg paramTypes: Class<*>
    ): Method? {
        // 单参 setter 热路径：避免 buildString；多参仍拼 key
        val key = if (paramTypes.size == 1) {
            clazz.name + '#' + name + '#' + paramTypes[0].name
        } else {
            buildString(clazz.name.length + name.length + 16) {
                append(clazz.name)
                append('#')
                append(name)
                for (p in paramTypes) {
                    append('#')
                    append(p.name)
                }
            }
        }
        val hit = cache[key]
        if (hit === NO_METHOD) return null
        if (hit is Method) return hit
        var c: Class<*>? = clazz
        while (c != null && c != Any::class.java) {
            try {
                val m = c.getMethod(name, *paramTypes)
                cache[key] = m
                return m
            } catch (_: NoSuchMethodException) {
                c = c.superclass
            }
        }
        cache[key] = NO_METHOD
        return null
    }

    /** Lua / 表属性名 → setXxx */
    fun setterName(key: String): String {
        if (key.isEmpty()) return "set"
        val c0 = key[0]
        return if (c0.isLowerCase()) {
            "set" + c0.uppercaseChar() + key.substring(1)
        } else {
            "set$key"
        }
    }

    fun invokeBooleanSetter(target: Any, methodName: String, value: Boolean): Boolean {
        val m = cachedMethod(
            booleanSetterCache, target.javaClass, methodName,
            Boolean::class.javaPrimitiveType!!
        ) ?: return false
        return runCatching {
            m.invoke(target, value)
            true
        }.getOrDefault(false)
    }

    fun invokeFloatSetter(target: Any, methodName: String, value: Float): Boolean {
        val m = cachedMethod(
            floatSetterCache, target.javaClass, methodName,
            Float::class.javaPrimitiveType!!
        ) ?: return false
        return runCatching {
            m.invoke(target, value)
            true
        }.getOrDefault(false)
    }

    fun invokeIntSetter(target: Any, methodName: String, value: Int): Boolean {
        val m = cachedMethod(
            intSetterCache, target.javaClass, methodName,
            Int::class.javaPrimitiveType!!
        ) ?: return false
        return runCatching {
            m.invoke(target, value)
            true
        }.getOrDefault(false)
    }

    fun invokeColorStateListSetter(
        target: Any,
        methodName: String,
        csl: android.content.res.ColorStateList
    ): Boolean {
        val m = cachedMethod(
            colorStateListSetterCache, target.javaClass, methodName,
            android.content.res.ColorStateList::class.java
        ) ?: return false
        return runCatching {
            m.invoke(target, csl)
            true
        }.getOrDefault(false)
    }

    fun invokeObjectSetter(target: Any, methodName: String, value: Any): Boolean {
        // 精确类型 → 常见接口/父类形参（setTag(Object)、setImageDrawable(Drawable)…）
        val candidates = ArrayList<Class<*>>(4)
        candidates.add(value.javaClass)
        when (value) {
            is android.graphics.drawable.Drawable ->
                candidates.add(android.graphics.drawable.Drawable::class.java)
            is android.view.View ->
                candidates.add(android.view.View::class.java)
            is CharSequence -> {
                candidates.add(CharSequence::class.java)
                candidates.add(String::class.java)
            }
        }
        candidates.add(Any::class.java)
        for (param in candidates) {
            val m = cachedMethod(objectSetterCache, target.javaClass, methodName, param)
                ?: continue
            if (runCatching {
                    m.invoke(target, value)
                    true
                }.getOrDefault(false)
            ) {
                return true
            }
        }
        return false
    }

    /**
     * 热路径：用缓存 Method 直接写属性，避开 JavaInstance `view[key]=` 桥。
     * 调用方应先 [canSetJavaProperty]，避免误命中无关 setXxx。
     * @return true 已成功设置
     */
    fun trySetJavaValue(target: Any, key: String, value: Any?): Boolean {
        if (value == null) return false
        val name = setterName(key)
        return when (value) {
            is Boolean -> invokeBooleanSetter(target, name, value)
            is Int -> invokeIntSetter(target, name, value)
            is Long -> {
                val n = value.toInt()
                if (n.toLong() == value && invokeIntSetter(target, name, n)) true
                else invokeFloatSetter(target, name, value.toFloat())
            }
            is Float -> invokeFloatSetter(target, name, value)
            is Double -> {
                val asInt = value.toInt()
                if (asInt.toDouble() == value && invokeIntSetter(target, name, asInt)) true
                else invokeFloatSetter(target, name, value.toFloat())
            }
            is android.content.res.ColorStateList ->
                invokeColorStateListSetter(target, name, value)
            is CharSequence -> invokeCharSequenceSetter(target, name, value)
            else -> invokeObjectSetter(target, name, value)
        }
    }

    private fun invokeCharSequenceSetter(
        target: Any,
        methodName: String,
        value: CharSequence,
    ): Boolean {
        // setText(CharSequence) 比 setText(String) 更常见
        val byCs = cachedMethod(
            objectSetterCache, target.javaClass, methodName, CharSequence::class.java
        )
        if (byCs != null) {
            return runCatching {
                byCs.invoke(target, value)
                true
            }.getOrDefault(false)
        }
        val byStr = cachedMethod(
            objectSetterCache, target.javaClass, methodName, String::class.java
        )
        if (byStr != null) {
            return runCatching {
                byStr.invoke(target, value.toString())
                true
            }.getOrDefault(false)
        }
        return false
    }

    fun intSetterCache(): ConcurrentHashMap<String, Any> = intSetterCache
    fun floatSetterCache(): ConcurrentHashMap<String, Any> = floatSetterCache
    fun objectSetterCache(): ConcurrentHashMap<String, Any> = objectSetterCache
    fun colorStateListSetterCache(): ConcurrentHashMap<String, Any> = colorStateListSetterCache
}
