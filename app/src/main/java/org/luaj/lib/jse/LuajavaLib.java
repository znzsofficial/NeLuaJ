package org.luaj.lib.jse;

import com.androlua.LuaActivity;
import com.androlua.LuaEnhancer;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import org.luaj.LuaError;
import org.luaj.LuaTable;
import org.luaj.LuaUserdata;
import org.luaj.LuaValue;
import org.luaj.Varargs;
import org.luaj.lib.LibFunction;
import org.luaj.lib.OneArgFunction;
import org.luaj.lib.VarArgFunction;

import java.lang.reflect.Array;
import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.lang.reflect.Proxy;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.IdentityHashMap;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;

/**
 * LuaJava桥接库主类。
 * 提供Java类绑定、实例创建、代理创建等功能。
 */
public class LuajavaLib extends VarArgFunction {
    // 函数名称数组（保持原有字段名以保证兼容性）
    static final String[] d = new String[]{
        "bindClass", "newInstance", "new", "createProxy", "loadLib", "astable", "instanceof",
        "kotlinObject", "kotlinCompanion", "toTable", "toList", "toSet", "toMap",
        "constructor", "method", "iterate"
    };
    private static final LuaValue INSTANCE = LuaValue.valueOf("INSTANCE");
    private static final LuaValue COMPANION = LuaValue.valueOf("Companion");
    
    // 自定义类加载器列表
    public ArrayList<ClassLoader> e = new ArrayList<>();
    private volatile ClassLoader[] classLoaders = new ClassLoader[0];
    private volatile long classLoaderGeneration;

    /**
     * Retained for binary compatibility with the bundled Luaj++ API. Runtime lookups deliberately
     * do not populate this name-only cache because it cannot distinguish dynamic ClassLoaders.
     */
    public HashMap<String, LuaValue> f = new HashMap<>();

    /**
     * 将Java对象转换为Lua表（递归转换）
     * @param object 要转换的Java对象
     * @return 转换后的Lua表
     */
    public static LuaValue asTable(Object object) {
        return asTable(object, true);
    }

    /**
     * 将Java对象转换为Lua表
     * @param object 要转换的Java对象
     * @param recursive 是否递归转换子元素
     * @return 转换后的Lua表
     */
    public static LuaValue asTable(Object object, boolean recursive) {
        return asTableInternal(object, recursive, recursive ? new IdentityHashMap<>() : null);
    }

    /**
     * 内部实现：将Java对象转换为Lua表
     */
    private static LuaValue asTableInternal(
        Object object,
        boolean recursive,
        IdentityHashMap<Object, LuaTable> convertedTables
    ) {
        if (object == null) {
            return LuaValue.NIL;
        }

        Class<?> objectClass = object.getClass();
        boolean container = objectClass.isArray() || object instanceof Collection || object instanceof Map ||
            object instanceof JSONObject || object instanceof JSONArray;
        if (!container) {
            return CoerceJavaToLua.coerce(object);
        }

        if (convertedTables != null) {
            LuaTable converted = convertedTables.get(object);
            if (converted != null) {
                return converted;
            }
        }

        LuaTable table = new LuaTable();
        if (convertedTables != null) {
            convertedTables.put(object, table);
        }
        
        if (objectClass.isArray()) {
            // 数组类型
            int length = Array.getLength(object);
            for (int index = 0; index < length; index++) {
                table.set(index + 1, convertTableValue(Array.get(object, index), recursive, convertedTables));
            }
        } else if (object instanceof Collection) {
            // 集合类型
            int index = 1;
            for (Object item : (Collection<?>) object) {
                table.set(index++, convertTableValue(item, recursive, convertedTables));
            }
        } else if (object instanceof Map) {
            // Map类型
            for (Map.Entry<?, ?> entry : ((Map<?, ?>) object).entrySet()) {
                table.set(
                    CoerceJavaToLua.coerce(entry.getKey()),
                    convertTableValue(entry.getValue(), recursive, convertedTables)
                );
            }
        } else if (object instanceof JSONObject jsonObject) {
            // JSONObject类型
            Iterator<?> keys = jsonObject.keys();
            while (keys.hasNext()) {
                String key = (String) keys.next();
                try {
                    table.set(key, convertTableValue(jsonObject.get(key), recursive, convertedTables));
                } catch (JSONException ignored) {
                    // 忽略JSON解析错误
                }
            }
        } else if (object instanceof JSONArray jsonArray) {
            // JSONArray类型
            int length = jsonArray.length();
            for (int index = 0; index < length; index++) {
                try {
                    table.set(index + 1, convertTableValue(jsonArray.get(index), recursive, convertedTables));
                } catch (JSONException ignored) {
                    // 忽略JSON解析错误
                }
            }
        }

        return table;
    }

    /**
     * 转换表中的值
     */
    private static LuaValue convertTableValue(
        Object value,
        boolean recursive,
        IdentityHashMap<Object, LuaTable> convertedTables
    ) {
        if (value == null || value == JSONObject.NULL) {
            return LuaValue.NIL;
        }
        return recursive ? asTableInternal(value, true, convertedTables) : CoerceJavaToLua.coerce(value);
    }

    /**
     * 创建Java接口的Lua代理
     * @param type 接口类型
     * @param value Lua值（函数或表）
     * @return 代理对象
     */
    public static LuaUserdata createProxy(Class<?> type, LuaValue value) {
        checkInterface(type);
        ProxyInvocationHandler handler = new ProxyInvocationHandler(value);
        return createProxyUserdata(Proxy.newProxyInstance(type.getClassLoader(), new Class[]{type}, handler), type);
    }

    /**
     * 创建单接口代理的用户数据
     */
    private static LuaUserdata createProxyUserdata(Object proxy, Class<?> primaryInterface) {
        JavaInstance instance = new JavaInstance(proxy);
        instance.f = JavaClass.a(primaryInterface);
        return instance;
    }

    /**
     * 创建多接口代理的用户数据
     */
    private static LuaUserdata createProxyUserdata(Object proxy, Class<?>[] interfaces) {
        if (interfaces.length == 1) {
            return createProxyUserdata(proxy, interfaces[0]);
        }
        return new ProxyJavaInstance(proxy, interfaces);
    }

    /**
     * 创建Java类的覆盖类（继承并重写方法）
     * @param type 要覆盖的类
     * @param value Lua表，包含要重写的方法
     * @return 覆盖后的JavaClass
     */
    public static LuaValue override(Class type, LuaValue value) {
        return JavaClass.a((new LuaEnhancer(type)).create(value));
    }

    /** Binds a Java class using the current project class loader snapshot. */
    public LuaValue bindClassForName(String className) {
        try {
            return JavaClass.a(resolveClass(className));
        } catch (ClassNotFoundException exception) {
            return throwUnchecked(exception);
        }
    }

    @SuppressWarnings("unchecked")
    private static <T, E extends Throwable> T throwUnchecked(Throwable exception) throws E {
        throw (E) exception;
    }

    /**
     * Publishes a stable loader snapshot after LuaDexLoader changes. The public list field remains
     * available for legacy callers; callers that mutate it must publish the change again.
     */
    public synchronized void setClassLoaders(ArrayList<ClassLoader> classLoaders) {
        if (classLoaders == null) {
            throw new NullPointerException("classLoaders");
        }
        this.e = classLoaders;
        publishClassLoaders(classLoaders);
    }

    /**
     * 使用默认ClassLoader加载类
     */
    protected Class<?> f(String className) throws ClassNotFoundException {
        return Class.forName(className);
    }

    Class<?> resolveClass(String className) throws ClassNotFoundException {
        try {
            return f(className);
        } catch (ClassNotFoundException notFound) {
            for (ClassLoader classLoader : classLoaders) {
                if (classLoader == null) {
                    continue;
                }
                try {
                    return Class.forName(className, true, classLoader);
                } catch (ClassNotFoundException ignored) {
                    // Continue through the project loader chain.
                }
            }
            throw notFound;
        }
    }

    private void publishClassLoaders(ArrayList<ClassLoader> classLoaders) {
        this.classLoaders = new ArrayList<>(classLoaders).toArray(new ClassLoader[0]);
        classLoaderGeneration++;
    }

    long classLoaderGeneration() {
        return classLoaderGeneration;
    }

    /**
     * 主调用入口
     */
    public Varargs invoke(Varargs args) {
        try {
            return switch (super.b) {
                case 0 -> // load
                        load(args);
                case 1 -> // bindClass
                        bindClassForName(args.checkjstring(1));
                case 2, 3 -> // newInstance (by class object)
                        newInstance(args);
                case 4 -> // createProxy
                        createProxy(args);
                case 5 -> // loadLib
                        loadLib(args);
                case 6, 10 -> toTable(args);
                case 7 -> // instanceof
                        LuaValue.valueOf(
                                ((Class) args.arg(2).touserdata(Class.class)).isInstance(args.checkuserdata(1))
                        );
                case 8 -> kotlinMember(args, INSTANCE, "Kotlin object");
                case 9 -> kotlinMember(args, COMPANION, "Kotlin companion object");
                case 11 -> toList(args.checktable(1));
                case 12 -> toSet(args.checktable(1));
                case 13 -> toMap(args.checktable(1));
                case 14 -> constructor(args);
                case 15 -> method(args);
                case 16 -> iterate(args);
                default -> throw new LuaError("unsupported luajava operation: " + super.b + "\n" +
                        "This is an internal error. Please report this issue.");
            };
        } catch (LuaError error) {
            throw error;
        } catch (InvocationTargetException exception) {
            Throwable cause = exception.getTargetException();
            throw new LuaError("Java exception in luajava call\n" +
                "Cause: " + cause.getClass().getSimpleName() + ": " + cause.getMessage());
        } catch (Exception exception) {
            throw new LuaError("error in luajava call\n" +
                "Error: " + exception.getClass().getSimpleName() + ": " + exception.getMessage());
        }
    }

    /**
     * 初始化luajava库
     */
    private Varargs load(Varargs args) {
        LuaValue env = args.arg(2);
        env.checkglobals().s = this;
        LuaTable table = new LuaTable();
        a(table, this.getClass(), d, 1);
        env.set("luajava", table);
        env.get("package").get("loaded").set("luajava", table);
        
        // 注册基本类型
        env.set("boolean", JavaClass.a(Boolean.TYPE));
        env.set("byte", JavaClass.a(Byte.TYPE));
        env.set("char", JavaClass.a(Character.TYPE));
        env.set("short", JavaClass.a(Short.TYPE));
        env.set("int", JavaClass.a(Integer.TYPE));
        env.set("long", JavaClass.a(Long.TYPE));
        env.set("float", JavaClass.a(Float.TYPE));
        env.set("double", JavaClass.a(Double.TYPE));
        
        // 注册import函数
        env.set("import", new ImportFunction(this, env));
        return table;
    }

    /**
     * 创建新的Java实例
     */
    private Varargs newInstance(Varargs args) throws ClassNotFoundException {
        LuaValue target = args.checkvalue(1);
        Class<?> type;
        if (super.b == 2) {
            // 通过类名创建
            type = resolveClass(target.tojstring());
        } else {
            // 通过Class对象创建
            type = (Class<?>) target.checkuserdata(Class.class);
        }
        return JavaClass.a(type).getConstructor().invoke(args.subargs(2));
    }

    /** Returns one public constructor selected by its exact parameter types. */
    private LuaValue constructor(Varargs args) throws ClassNotFoundException, NoSuchMethodException {
        Class<?> type = toClass(args.checkvalue(1));
        Constructor<?> constructor = type.getConstructor(parameterTypes(args.checktable(2)));
        return JavaConstructor.a(constructor);
    }

    /** Returns one public method selected by its exact parameter types and bound to its target. */
    private LuaValue method(Varargs args) throws ClassNotFoundException, NoSuchMethodException {
        LuaValue target = args.checkvalue(1);
        JavaInstance instance;
        Object targetObject;

        if (target.type() == LuaValue.TSTRING) {
            Class<?> type = resolveClassName(target.checkjstring());
            instance = JavaClass.a(type);
            targetObject = type;
        } else {
            targetObject = target.checkuserdata();
            instance = target instanceof JavaInstance
                ? (JavaInstance) target
                : targetObject instanceof Class
                    ? JavaClass.a((Class<?>) targetObject)
                    : new JavaInstance(targetObject);
        }

        Class<?> type = targetObject instanceof Class ? (Class<?>) targetObject : targetObject.getClass();
        Method method = type.getMethod(args.checkjstring(2), parameterTypes(args.checktable(3)));
        if (targetObject instanceof Class && !Modifier.isStatic(method.getModifiers())) {
            throw new LuaError("method '" + method.getName() + "' requires an instance of '" + type.getName() + "'");
        }

        JavaMethod javaMethod = JavaMethod.a(method);
        if (javaMethod == null) {
            throw new LuaError("cannot access Java method '" + method + "'");
        }
        return new JavaMethod.JavaOOMethod(instance, javaMethod);
    }

    /** Returns a stateful Lua iterator for Java arrays, maps, iterables, iterators, and Kotlin sequences. */
    private LuaValue iterate(Varargs args) {
        Object value = args.checkuserdata(1);
        if (value instanceof Map) {
            return new JavaIterator(((Map<?, ?>) value).entrySet().iterator(), true);
        }
        if (value instanceof Iterator) {
            return new JavaIterator((Iterator<?>) value, false);
        }
        if (value instanceof Iterable) {
            return new JavaIterator(((Iterable<?>) value).iterator(), false);
        }
        if (value.getClass().isArray()) {
            return new JavaIterator(new ArrayIterator(value), false);
        }

        try {
            Method iterator = value.getClass().getMethod("iterator");
            Object result = iterator.invoke(value);
            if (result instanceof Iterator) {
                return new JavaIterator((Iterator<?>) result, false);
            }
        } catch (NoSuchMethodException ignored) {
            // Continue to the bridge-specific error below.
        } catch (Exception exception) {
            throw new LuaError("failed to create Java iterator: " + exception.getMessage());
        }
        throw new LuaError("luajava.iterate expects a Java array, Map, Iterable, Iterator, or Kotlin Sequence");
    }

    /**
     * Converts Java arrays, collections, and maps to a Lua table. Nested values remain userdata
     * unless recursive conversion is explicitly requested.
     */
    private LuaValue toTable(Varargs args) {
        if (args.istable(1)) {
            return args.checktable(1);
        }
        return asTable(args.checkuserdata(1), args.optboolean(2, false));
    }

    /** Converts the array part of a Lua table (indexes 1 through #table) to an ArrayList. */
    private static LuaValue toList(LuaTable table) {
        int length = table.length();
        ArrayList<Object> result = new ArrayList<>(length);
        for (int index = 1; index <= length; index++) {
            result.add(CoerceLuaToJava.coerce(table.get(index), Object.class));
        }
        return CoerceJavaToLua.coerce(result);
    }

    /** Converts the array part of a Lua table (indexes 1 through #table) to an ordered Set. */
    private static LuaValue toSet(LuaTable table) {
        int length = table.length();
        LinkedHashSet<Object> result = new LinkedHashSet<>(length);
        for (int index = 1; index <= length; index++) {
            result.add(CoerceLuaToJava.coerce(table.get(index), Object.class));
        }
        return CoerceJavaToLua.coerce(result);
    }

    /** Converts all Lua table entries to a Java Map in the table's current iteration order. */
    private static LuaValue toMap(LuaTable table) {
        LinkedHashMap<Object, Object> result = new LinkedHashMap<>(table.size());
        LuaValue key = LuaValue.NIL;
        Varargs entry;
        while (!(entry = table.next(key)).isnil(1)) {
            key = entry.arg1();
            result.put(
                CoerceLuaToJava.coerce(key, Object.class),
                CoerceLuaToJava.coerce(entry.arg(2), Object.class)
            );
        }
        return CoerceJavaToLua.coerce(result);
    }

    /**
     * Returns a Kotlin singleton or companion object without requiring Lua callers to know the
     * generated INSTANCE or Companion field names.
     */
    private LuaValue kotlinMember(Varargs args, LuaValue fieldName, String memberKind) throws ClassNotFoundException {
        Class<?> type = toClass(args.checkvalue(1));
        LuaValue member = JavaClass.a(type).get(fieldName);
        if (member.isnil()) {
            throw new LuaError(memberKind + " is not available on class '" + type.getName() + "'");
        }
        return member;
    }

    /**
     * 创建代理对象
     */
    private Varargs createProxy(Varargs args) throws ClassNotFoundException {
        int interfaceCount = args.narg() - 1;
        if (interfaceCount <= 0) {
            throw new LuaError("luajava.createProxy requires at least one interface argument.\n" +
                "Usage: luajava.createProxy(interface1, [interface2, ...], implementation)");
        }

        LuaValue value = args.checkvalue(interfaceCount + 1);
        Class<?>[] interfaces = new Class<?>[interfaceCount];
        for (int index = 0; index < interfaceCount; index++) {
            interfaces[index] = checkInterface(toClass(args.arg(index + 1)));
        }

        ProxyInvocationHandler handler = new ProxyInvocationHandler(value);
        return createProxyUserdata(
            Proxy.newProxyInstance(interfaces[0].getClassLoader(), interfaces, handler), 
            interfaces
        );
    }

    /**
     * 将LuaValue转换为Class对象
     */
    private Class<?> toClass(LuaValue value) throws ClassNotFoundException {
        if (value.type() == LuaValue.TSTRING) {
            return resolveClassName(value.checkjstring());
        }
        Object userdata = value.touserdata(Class.class);
        if (userdata instanceof Class) {
            return (Class<?>) userdata;
        }
        userdata = value.touserdata(JavaClass.class);
        if (userdata instanceof JavaClass) {
            return (Class<?>) ((JavaClass) userdata).touserdata(Class.class);
        }
        throw new LuaError("expected a Java class, got " + value.typename() + "\n" +
            "Value: " + value + "\n" +
            "Hint: Use luajava.bindClass() to get a Java class reference.");
    }

    private Class<?>[] parameterTypes(LuaTable table) throws ClassNotFoundException {
        int length = table.length();
        Class<?>[] result = new Class<?>[length];
        for (int index = 0; index < length; index++) {
            result[index] = toClass(table.get(index + 1));
        }
        return result;
    }

    private Class<?> resolveClassName(String className) throws ClassNotFoundException {
        int dimensions = 0;
        while (className.endsWith("[]")) {
            dimensions++;
            className = className.substring(0, className.length() - 2);
        }

        Class<?> type = switch (className) {
            case "boolean" -> Boolean.TYPE;
            case "byte" -> Byte.TYPE;
            case "char" -> Character.TYPE;
            case "short" -> Short.TYPE;
            case "int" -> Integer.TYPE;
            case "long" -> Long.TYPE;
            case "float" -> Float.TYPE;
            case "double" -> Double.TYPE;
            default -> resolveClass(className);
        };
        while (dimensions-- > 0) {
            type = Array.newInstance(type, 0).getClass();
        }
        return type;
    }

    /**
     * 检查类型是否为接口
     */
    private static Class<?> checkInterface(Class<?> type) {
        if (!type.isInterface()) {
            throw new LuaError("expected a Java interface, got class '" + type.getSimpleName() + "'\n" +
                "Class: " + type.getName() + "\n" +
                "Hint: Only interfaces can be used to create proxies. Use luajava.override() for classes.");
        }
        return type;
    }

    /**
     * 多接口代理实例
     */
    private static final class ProxyJavaInstance extends JavaInstance {
        private final JavaClass[] interfaces;

        private ProxyJavaInstance(Object proxy, Class<?>[] interfaces) {
            super(proxy);
            this.interfaces = new JavaClass[interfaces.length];
            for (int index = 0; index < interfaces.length; index++) {
                this.interfaces[index] = JavaClass.a(interfaces[index]);
            }
            this.f = this.interfaces[0];
        }

        @Override
        public LuaValue getJavaMethod(LuaValue key) {
            // 在所有接口中查找方法
            for (JavaClass javaInterface : this.interfaces) {
                LuaValue method = javaInterface.getMethod(key);
                if (method != null) {
                    return new JavaMethod.JavaOOMethod(this, method);
                }
            }
            return LuaValue.NIL;
        }

        @Override
        public LuaValue get(LuaValue key) {
            LuaValue value = getJavaMethod(key);
            if (!value.isnil()) {
                return value;
            }
            return super.get(key);
        }
    }

    private static final class JavaIterator extends VarArgFunction {
        private final Iterator<?> iterator;
        private final boolean mapEntries;
        private int index;

        private JavaIterator(Iterator<?> iterator, boolean mapEntries) {
            this.iterator = iterator;
            this.mapEntries = mapEntries;
        }

        @Override
        public Varargs invoke(Varargs args) {
            if (!iterator.hasNext()) {
                return LuaValue.NIL;
            }

            Object value = iterator.next();
            if (mapEntries) {
                Map.Entry<?, ?> entry = (Map.Entry<?, ?>) value;
                return LuaValue.varargsOf(
                    CoerceJavaToLua.coerce(entry.getKey()),
                    CoerceJavaToLua.coerce(entry.getValue()),
                    LuaValue.NONE
                );
            }
            return LuaValue.varargsOf(
                CoerceJavaToLua.coerce(index++),
                CoerceJavaToLua.coerce(value),
                LuaValue.NONE
            );
        }
    }

    private static final class ArrayIterator implements Iterator<Object> {
        private final Object array;
        private final int length;
        private int index;

        private ArrayIterator(Object array) {
            this.array = array;
            this.length = Array.getLength(array);
        }

        @Override
        public boolean hasNext() {
            return index < length;
        }

        @Override
        public Object next() {
            return Array.get(array, index++);
        }
    }

    /**
     * 加载Java库
     */
    private Varargs loadLib(Varargs args) throws Exception {
        String className = args.checkjstring(1);
        String methodName = args.checkjstring(2);
        Class<?> type = resolveClass(className);
        Object result = type.getMethod(methodName).invoke(type);
        if (result instanceof LuaValue) {
            return (LuaValue) result;
        }
        return LuaValue.NIL;
    }

    /**
     * import函数实现
     */
    private static final class ImportFunction extends VarArgFunction {
        final LuaValue env;
        final LuajavaLib luajava;

        private ImportFunction(LuajavaLib luajava, LuaValue env) {
            this.luajava = luajava;
            this.env = env;
        }

        public Varargs invoke(Varargs args) {
            try {
                String className = args.checkjstring(1);
                // 提取简单类名
                String simpleName = className.replaceFirst(".*?[$\\.]([^$\\.]*)$", "$1");
                LuaValue javaClass = this.luajava.bindClassForName(className);
                this.env.set(simpleName, javaClass);
                return javaClass;
            } catch (LuaError error) {
                throw error;
            } catch (Exception exception) {
                throw new LuaError(exception);
            }
        }
    }

    /**
     * 代理调用处理器
     */
    private static final class ProxyInvocationHandler implements InvocationHandler {
        private final LuaValue handler;

        private ProxyInvocationHandler(LuaValue value) {
            this.handler = value;
        }

        /**
         * 处理代理方法调用
         */
        public Object invoke(Object proxy, Method method, Object[] args) {
            String methodName = method.getName();
            boolean functionMode = this.handler.isfunction();
            
            // 获取Object类方法的默认结果（equals, hashCode, toString）
            Object defaultObjectResult = getDefaultObjectMethodResult(proxy, method, args);
            if (functionMode && defaultObjectResult != null) {
                return defaultObjectResult;
            }

            // 获取要调用的Lua函数
            LuaValue function = functionMode ? this.handler : this.handler.get(methodName);

            if (!function.isnil()) {
                LuaValue[] luaArgs = toLuaArgs(method, args);
                try {
                    return CoerceLuaToJava.coerce(function.invoke(luaArgs).arg1(), method.getReturnType());
                } catch (Exception exception) {
                    LuaActivity.logError(methodName, exception);
                }
            }

            // 如果Lua函数不存在，返回默认结果
            if (defaultObjectResult != null) {
                return defaultObjectResult;
            }

            // 返回nil
            return CoerceLuaToJava.coerce(LuaValue.NIL, method.getReturnType());
        }

        /**
         * 获取Object类方法的默认结果
         */
        private static Object getDefaultObjectMethodResult(Object proxy, Method method, Object[] args) {
            String methodName = method.getName();
            Class<?>[] parameterTypes = method.getParameterTypes();
            
            // equals方法
            if (parameterTypes.length == 1 && methodName.equals("equals") && parameterTypes[0] == Object.class) {
                Object other = args != null && args.length > 0 ? args[0] : null;
                return proxy == other;
            }
            
            // hashCode方法
            if (parameterTypes.length == 0 && methodName.equals("hashCode")) {
                return System.identityHashCode(proxy);
            }
            
            // toString方法
            if (parameterTypes.length == 0 && methodName.equals("toString")) {
                Class<?>[] interfaces = proxy.getClass().getInterfaces();
                String typeName = interfaces.length > 0 ? interfaces[0].getName() : proxy.getClass().getName();
                return typeName + "@" + Integer.toHexString(System.identityHashCode(proxy));
            }
            
            return null;
        }

        /**
         * 将Java参数转换为Lua参数
         */
        private static LuaValue[] toLuaArgs(Method method, Object[] args) {
            int argCount = args != null ? args.length : 0;
            boolean isVarArgs = (method.getModifiers() & 0x80) != 0;
            
            if (!isVarArgs || argCount == 0) {
                // 非可变参数方法
                LuaValue[] luaArgs = new LuaValue[argCount];
                for (int index = 0; index < argCount; index++) {
                    luaArgs[index] = CoerceJavaToLua.coerce(args[index]);
                }
                return luaArgs;
            }

            // 可变参数方法
            int fixedArgCount = argCount - 1;
            Object varArgArray = args[fixedArgCount];
            int varArgCount = varArgArray != null ? Array.getLength(varArgArray) : 0;
            LuaValue[] luaArgs = new LuaValue[fixedArgCount + varArgCount];
            
            // 固定参数
            for (int index = 0; index < fixedArgCount; index++) {
                luaArgs[index] = CoerceJavaToLua.coerce(args[index]);
            }
            
            // 可变参数
            for (int index = 0; index < varArgCount; index++) {
                luaArgs[index + fixedArgCount] = CoerceJavaToLua.coerce(Array.get(varArgArray, index));
            }
            
            return luaArgs;
        }
    }

    /**
     * override函数实现
     */
    public static final class override extends OneArgFunction {
        private final Class targetClass;

        public override(JavaClass javaClass) {
            this.targetClass = (Class) ((LuaUserdata) javaClass).touserdata(Class.class);
        }

        public LuaValue call(LuaValue value) {
            try {
                return LuajavaLib.override(this.targetClass, value);
            } catch (Exception exception) {
                throw new LuaError(exception);
            }
        }
    }
}
