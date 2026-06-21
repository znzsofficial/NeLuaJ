//
// Source code recreated from a .class file by IntelliJ IDEA
// (powered by FernFlower decompiler)
// Optimized with improved variable naming, comments, and performance
//

package org.luaj.lib.jse;

import org.luaj.LuaError;
import org.luaj.LuaString;
import org.luaj.LuaValue;
import org.luaj.Varargs;
import org.luaj.lib.OneArgFunction;

import java.lang.reflect.Array;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 表示Java类的Lua值。
 * 提供对Java类的方法、字段、构造函数等的访问。
 * 实现了CoerceJavaToLua.Coercion接口以支持类型转换。
 */
public class JavaClass extends JavaInstance implements CoerceJavaToLua.Coercion {
    // Class类的方法缓存（保持原有字段名以保证兼容性）
    static final HashMap<LuaValue, LuaValue> i = new HashMap<>();
    
    // JavaClass实例缓存：Class -> JavaClass
    static final Map<Class<?>, JavaClass> j = Collections.synchronizedMap(new HashMap<>());
    
    // JavaClass实例缓存：类名 -> JavaClass
    static final Map<String, JavaClass> k = Collections.synchronizedMap(new HashMap<>());
    
    // "new"关键字的Lua值常量
    static final LuaValue l = LuaValue.valueOf("new");
    
    // 以下字段用于缓存方法和字段信息（保持原有字段名以保证兼容性）
    final HashMap<LuaValue, Integer> m = new HashMap<>();
    final HashMap<LuaValue, Integer> n = new HashMap<>();
    final HashMap<LuaValue, Integer> o = new HashMap<>();
    final HashMap<LuaValue, LuaValue> p = new HashMap<>();
    final HashMap<LuaValue, LuaValue> q = new HashMap<>();
    final HashMap<LuaValue, LuaValue> r = new HashMap<>();
    
    // 字段缓存：字段名 -> Field对象
    Map<LuaValue, Field> s;
    
    // 方法缓存：方法名 -> LuaValue（可能是单个方法或重载方法）
    Map<LuaValue, LuaValue> t;
    
    // 内部类缓存：内部类名 -> JavaClass
    Map<LuaValue, JavaClass> u;

    static {
        // 预加载Class类的所有方法
        for (Method method : Class.class.getMethods()) {
            i.put(LuaValue.valueOf(method.getName()), JavaMethod.a(method));
        }
    }

    /**
     * 构造函数
     * @param clazz 要表示的Java类
     */
    JavaClass(Class<?> clazz) {
        super(clazz);
        super.f = this;
    }

    /**
     * 获取或创建指定Class的JavaClass实例（使用缓存）
     * @param clazz Java类
     * @return 对应的JavaClass实例
     */
    static JavaClass a(Class<?> clazz) {
        return j.computeIfAbsent(clazz, JavaClass::new);
    }

    /**
     * 使用指定的ClassLoader获取或创建JavaClass实例
     * @param className 类名
     * @param classLoader 类加载器
     * @return 对应的JavaClass实例
     * @throws ClassNotFoundException 如果类未找到
     */
    static JavaClass a(String className, ClassLoader classLoader) throws ClassNotFoundException {
        JavaClass cached = k.get(className);
        if (cached == null) {
            cached = a(Class.forName(className, true, classLoader));
            k.put(className, cached);
        }
        return cached;
    }

    /**
     * 使用默认ClassLoader获取或创建JavaClass实例
     * @param className 类名
     * @return 对应的JavaClass实例
     * @throws ClassNotFoundException 如果类未找到
     */
    static JavaClass f(String className) throws ClassNotFoundException {
        JavaClass cached = k.get(className);
        if (cached == null) {
            cached = a(Class.forName(className));
            k.put(className, cached);
        }
        return cached;
    }

    /**
     * 获取指定名称的公共字段
     * @param fieldName 字段名（LuaValue）
     * @return 对应的Field对象，如果未找到则返回null
     */
    Field b(LuaValue fieldName) {
        if (this.s == null) {
            // 延迟初始化字段缓存
            HashMap<LuaValue, Field> fieldMap = new HashMap<>();
            Field[] fields = ((Class<?>) super.b).getFields();

            for (int i = fields.length - 1; i >= 0; --i) {
                Field field = fields[i];
                if (Modifier.isPublic(field.getModifiers())) {
                    fieldMap.put(LuaValue.valueOf(field.getName()), field);

                    try {
                        if (!field.isAccessible()) {
                            field.setAccessible(true);
                        }
                    } catch (SecurityException ignored) {
                        // 忽略安全异常，某些字段可能无法设置为可访问
                    }
                }
            }

            this.s = fieldMap;
        }

        return this.s.get(fieldName);
    }

    /**
     * 获取指定名称的内部类
     * @param innerClassName 内部类名（LuaValue）
     * @return 对应的JavaClass实例，如果未找到则返回null
     */
    JavaClass c(LuaValue innerClassName) {
        if (this.u == null) {
            // 延迟初始化内部类缓存
            HashMap<LuaValue, JavaClass> innerClassMap = new HashMap<>();

            // 遍历类层次结构查找内部类
            for (Class<?> clazz = (Class<?>) super.b; clazz != null; clazz = clazz.getSuperclass()) {
                for (Class<?> innerClass : clazz.getDeclaredClasses()) {
                    if (Modifier.isPublic(innerClass.getModifiers())) {
                        String fullName = innerClass.getName();
                        // 提取内部类的简单名称（去掉外部类名前缀）
                        LuaString simpleName = LuaValue.valueOf(
                            fullName.substring(Math.max(fullName.lastIndexOf('$'), fullName.lastIndexOf('.')) + 1)
                        );
                        if (!innerClassMap.containsKey(simpleName)) {
                            innerClassMap.put(simpleName, a(innerClass));
                        }
                    }
                }
            }

            this.u = innerClassMap;
        }
        return this.u.get(innerClassName);
    }

    /**
     * 创建类的实例（无参构造）
     * @return 新创建的JavaInstance
     */
    public LuaValue call() {
        try {
            return new JavaInstance(((Class<?>) super.b).newInstance());
        } catch (Exception e) {
            // 如果无参构造失败，尝试使用"new"方法
            return this.getMethod(l).call();
        }
    }

    /**
     * 创建类的实例或进行类型转换
     * @param arg 构造函数参数或要转换的值
     * @return 新创建的JavaInstance或转换后的值
     */
    public LuaValue call(LuaValue arg) {
        Class<?> obj = (Class<?>) this.touserdata();
        LuaValue converted = coerceOrCreateFromSingleArg(obj, arg, null);
        if (converted != null) {
            return converted;
        }
        if (obj.isPrimitive()) {
            return new JavaInstance(CoerceLuaToJava.coerce(arg, obj));
        }
        return this.getMethod(l).call(arg);
    }

    public LuaValue call(LuaValue arg1, LuaValue arg2) {
        return this.getMethod(l).call(arg1, arg2);
    }

    public LuaValue call(LuaValue arg1, LuaValue arg2, LuaValue arg3) {
        return this.getMethod(l).call(arg1, arg2, arg3);
    }

    /**
     * Coercion接口实现：返回自身
     */
    public LuaValue coerce(Object obj) {
        return this;
    }

    /**
     * 获取类的属性或方法
     * @param key 属性名或方法名
     * @return 对应的LuaValue
     */
    @Override
    public LuaValue get(LuaValue key) {
        // 如果是数字，创建数组
        if (key.isnumber())
            return CoerceJavaToLua.c.coerce(Array.newInstance((Class<?>) touserdata(), key.toint()));
        
        // 根据关键字返回特殊属性
        return switch (key.tojstring()) {
            case "override" -> new LuajavaLib.override(this);
            case "new" -> getMethod(key);
            case "array" -> new OneArgFunction() {
                public LuaValue call(LuaValue size) {
                    return CoerceJavaToLua.coerce(
                        (new CoerceLuaToJava.ArrayCoercion((Class<?>) JavaClass.super.b)).coerce(size)
                    );
                }
            };
            case "class" -> this;
            default -> super.get(key);
        };
    }

    /**
     * 获取构造函数
     * @return 构造函数的LuaValue
     */
    public LuaValue getConstructor() {
        return this.getMethod(l);
    }

    /**
     * 获取指定名称的方法
     * @param methodName 方法名（LuaValue）
     * @return 对应的方法LuaValue，如果未找到则返回null
     */
    public LuaValue getMethod(LuaValue methodName) {
        if (this.t == null) {
            // 延迟初始化方法缓存
            HashMap<String, List<JavaMethod>> methodMap = new HashMap<>();
            Method[] methods = ((Class<?>) super.b).getMethods();

            // 按方法名分组
            for (Method method : methods) {
                if (Modifier.isPublic(method.getModifiers())) {
                    String name = method.getName();
                    methodMap.computeIfAbsent(name, key -> new ArrayList<>()).add(JavaMethod.a(method));
                }
            }

            // 构建最终的方法缓存
            HashMap<LuaValue, LuaValue> finalMethodMap = new HashMap<>();
            
            // 处理构造函数
            Constructor<?>[] constructors = ((Class<?>) super.b).getConstructors();
            if (constructors.length == 0) {
                constructors = ((Class<?>) super.b).getDeclaredConstructors();
            }

            ArrayList<JavaConstructor> constructorList = new ArrayList<>();
            for (Constructor<?> constructor : constructors) {
                if (Modifier.isPublic(constructor.getModifiers())) {
                    constructor.setAccessible(true);
                    constructorList.add(JavaConstructor.a(constructor));
                }
            }

            // 根据构造函数数量创建相应的LuaValue
            switch (constructorList.size()) {
                case 0:
                    break;
                case 1:
                    finalMethodMap.put(l, constructorList.get(0));
                    break;
                default:
                    finalMethodMap.put(l, JavaConstructor.forConstructors(constructorList.toArray(new JavaConstructor[0])));
                    break;
            }

            // 添加Class类的方法
            finalMethodMap.putAll(i);

            // 添加类的实例方法
            for (Map.Entry<String, List<JavaMethod>> entry : methodMap.entrySet()) {
                String name = entry.getKey();
                List<JavaMethod> methodList = entry.getValue();
                LuaString luaName = LuaValue.valueOf(name);
                
                // 单个方法直接存储，多个方法创建重载包装器
                LuaValue methodValue;
                if (methodList.size() == 1) {
                    methodValue = methodList.get(0);
                } else {
                    methodValue = JavaMethod.a(methodList.toArray(new JavaMethod[0]));
                }

                finalMethodMap.put(luaName, methodValue);
            }

            this.t = finalMethodMap;
        }

        return this.t.get(methodName);
    }

    /**
     * 调用类的构造函数或方法
     * @param args 参数
     * @return 调用结果
     */
    public Varargs invoke(Varargs args) {
        if (args.narg() == 1) {
            Class<?> obj = (Class<?>) this.touserdata();
            LuaValue arg = args.arg1();
            LuaValue converted = coerceOrCreateFromSingleArg(obj, arg, args);
            if (converted != null) {
                return converted;
            }

            if (obj.isPrimitive()) {
                return new JavaInstance(CoerceLuaToJava.coerce(arg, obj));
            }
        }

        return this.get(l).invoke(args);
    }

    /**
     * 尝试将单个参数转换为指定类型的对象，或创建代理/覆盖类
     * @param obj 目标类型
     * @param arg 参数值
     * @param originalArgs 原始参数（用于回退调用）
     * @return 转换后的值，如果无法转换则返回null
     */
    private LuaValue coerceOrCreateFromSingleArg(Class<?> obj, LuaValue arg, Varargs originalArgs) {
        // 接口 + 函数 -> 创建代理
        if (obj.isInterface() && arg.isfunction()) {
            return LuajavaLib.createProxy(obj, arg);
        }
        
        // 非表参数无法处理
        if (!arg.istable()) {
            return null;
        }

        // 根据目标类型进行不同的处理
        if (obj.isPrimitive()) {
            // 基本类型 -> 数组转换
            return CoerceJavaToLua.coerce((new CoerceLuaToJava.ArrayCoercion(obj)).coerce(arg));
        } else if (obj.isInterface()) {
            // 接口 -> 创建代理
            return LuajavaLib.createProxy(obj, arg);
        } else if ((obj.getModifiers() & Modifier.ABSTRACT) != 0) {
            // 抽象类 -> 创建覆盖类
            try {
                return LuajavaLib.override(obj, arg).call();
            } catch (Exception e) {
                throw new LuaError("failed to create instance of abstract class '" + obj.getSimpleName() + "'\n" +
                    "Class: " + obj.getName() + "\n" +
                    "Error: " + e.getClass().getSimpleName() + ": " + e.getMessage() + "\n" +
                    "Hint: Ensure the Lua table implements all abstract methods.");
            }
        } else if (Map.class.isAssignableFrom(obj)) {
            // Map类型 -> 转换为Map
            return CoerceJavaToLua.coerce((new CoerceLuaToJava.MapCoercion(obj)).coerce(arg));
        } else if (List.class.isAssignableFrom(obj)) {
            // List类型 -> 转换为Collection
            return CoerceJavaToLua.coerce((new CoerceLuaToJava.CollectionCoercion(obj)).coerce(arg));
        } else if (arg.length() == 0 && arg.checktable().size() > 0) {
            // 非空表 -> 尝试创建覆盖类
            try {
                return LuajavaLib.override(obj, arg);
            } catch (Exception e) {
                throw new LuaError("failed to create instance of '" + obj.getSimpleName() + "' from Lua table\n" +
                    "Class: " + obj.getName() + "\n" +
                    "Error: " + e.getClass().getSimpleName() + ": " + e.getMessage());
            }
        }

        // 回退：尝试使用构造函数
        try {
            if (originalArgs != null) {
                return this.get(l).invoke(originalArgs).arg1();
            }
            return this.get(l).call(arg);
        } catch (Exception e) {
            // 最后尝试数组转换
            return CoerceJavaToLua.coerce((new CoerceLuaToJava.ArrayCoercion(obj)).coerce(arg));
        }
    }
}