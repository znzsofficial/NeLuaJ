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

    fun intSetterCache(): ConcurrentHashMap<String, Any> = intSetterCache
    fun floatSetterCache(): ConcurrentHashMap<String, Any> = floatSetterCache
    fun objectSetterCache(): ConcurrentHashMap<String, Any> = objectSetterCache
    fun colorStateListSetterCache(): ConcurrentHashMap<String, Any> = colorStateListSetterCache
}
