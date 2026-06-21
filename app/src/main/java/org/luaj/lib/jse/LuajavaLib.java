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
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

/**
 * LuaJava桥接库主类。
 * 提供Java类绑定、实例创建、代理创建等功能。
 */
public class LuajavaLib extends VarArgFunction {
    // 函数名称数组（保持原有字段名以保证兼容性）
    static final String[] d = new String[]{"bindClass", "newInstance", "new", "createProxy", "loadLib", "astable", "instanceof"};
    
    // 自定义类加载器列表
    public ArrayList<ClassLoader> e = new ArrayList<>();
    
    // 类名缓存：className -> LuaValue
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
        return asTableInternal(object, recursive);
    }

    /**
     * 内部实现：将Java对象转换为Lua表
     */
    private static LuaValue asTableInternal(Object object, boolean recursive) {
        if (object == null) {
            return LuaValue.NIL;
        }

        LuaTable table = new LuaTable();
        Class<?> objectClass = object.getClass();
        
        if (objectClass.isArray()) {
            // 数组类型
            int length = Array.getLength(object);
            for (int index = 0; index < length; index++) {
                table.set(index + 1, convertTableValue(Array.get(object, index), recursive));
            }
        } else if (object instanceof Collection) {
            // 集合类型
            int index = 1;
            for (Object item : (Collection<?>) object) {
                table.set(index++, convertTableValue(item, recursive));
            }
        } else if (object instanceof Map) {
            // Map类型
            for (Map.Entry<?, ?> entry : ((Map<?, ?>) object).entrySet()) {
                table.set(CoerceJavaToLua.coerce(entry.getKey()), convertTableValue(entry.getValue(), recursive));
            }
        } else if (object instanceof JSONObject) {
            // JSONObject类型
            JSONObject jsonObject = (JSONObject) object;
            Iterator<?> keys = jsonObject.keys();
            while (keys.hasNext()) {
                String key = (String) keys.next();
                try {
                    table.set(key, convertTableValue(jsonObject.get(key), recursive));
                } catch (JSONException ignored) {
                    // 忽略JSON解析错误
                }
            }
        } else if (object instanceof JSONArray) {
            // JSONArray类型
            JSONArray jsonArray = (JSONArray) object;
            int length = jsonArray.length();
            for (int index = 0; index < length; index++) {
                try {
                    table.set(index + 1, convertTableValue(jsonArray.get(index), recursive));
                } catch (JSONException ignored) {
                    // 忽略JSON解析错误
                }
            }
        } else {
            // 其他类型，直接转换
            return CoerceJavaToLua.coerce(object);
        }

        return table;
    }

    /**
     * 转换表中的值
     */
    private static LuaValue convertTableValue(Object value, boolean recursive) {
        if (value == null || value == JSONObject.NULL) {
            return LuaValue.NIL;
        }
        return recursive ? asTableInternal(value, true) : CoerceJavaToLua.coerce(value);
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

    /**
     * 绑定Java类（带缓存）
     * @param className 类名
     * @return 对应的JavaClass
     * @throws ClassNotFoundException 如果类未找到
     */
    public LuaValue bindClassForName(String className) throws ClassNotFoundException {
        // 检查缓存
        LuaValue cached = this.f.get(className);
        if (cached != null) {
            return cached;
        }

        try {
            // 尝试使用默认ClassLoader
            LuaValue javaClass = JavaClass.f(className);
            this.f.put(className, javaClass);
            return javaClass;
        } catch (Exception ignored) {
            // 尝试使用自定义ClassLoader
            for (ClassLoader classLoader : this.e) {
                try {
                    LuaValue javaClass = JavaClass.a(className, classLoader);
                    this.f.put(className, javaClass);
                    return javaClass;
                } catch (Exception ignored2) {
                    // 继续尝试下一个ClassLoader
                }
            }
            throw new ClassNotFoundException(className);
        }
    }

    /**
     * 使用默认ClassLoader加载类
     */
    protected Class<?> f(String className) throws ClassNotFoundException {
        return Class.forName(className);
    }

    /**
     * 主调用入口
     */
    public Varargs invoke(Varargs args) {
        try {
            switch (super.b) {
                case 0: // load
                    return load(args);
                case 1: // bindClass
                    return JavaClass.a(this.f(args.checkjstring(1)));
                case 2: // newInstance (by class name)
                case 3: // newInstance (by class object)
                    return newInstance(args);
                case 4: // createProxy
                    return createProxy(args);
                case 5: // loadLib
                    return loadLib(args);
                case 6: // astable
                    if (args.istable(1)) {
                        return args.checktable(1);
                    }
                    return asTable(args.checkuserdata(1), args.optboolean(2, false));
                case 7: // instanceof
                    return LuaValue.valueOf(
                        ((Class) args.arg(2).touserdata(Class.class)).isInstance(args.checkuserdata(1))
                    );
                default:
                    throw new LuaError("unsupported luajava operation: " + super.b + "\n" +
                        "This is an internal error. Please report this issue.");
            }
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
            type = this.f(target.tojstring());
        } else {
            // 通过Class对象创建
            type = (Class<?>) target.checkuserdata(Class.class);
        }
        return JavaClass.a(type).getConstructor().invoke(args.subargs(2));
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
        if (value.isstring()) {
            return this.f(value.checkjstring());
        }
        Object userdata = value.touserdata(Class.class);
        if (userdata instanceof Class) {
            return (Class<?>) userdata;
        }
        userdata = value.touserdata(JavaClass.class);
        if (userdata instanceof JavaClass) {
            return (Class<?>) ((JavaClass) userdata).touserdata(Class.class);
        }
        throw new LuaError("expected a Java interface class, got " + value.typename() + "\n" +
            "Value: " + value + "\n" +
            "Hint: Use luajava.bindClass() to get a Java class reference.");
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

    /**
     * 加载Java库
     */
    private Varargs loadLib(Varargs args) throws Exception {
        String className = args.checkjstring(1);
        String methodName = args.checkjstring(2);
        Class<?> type = this.f(className);
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
            } catch (ClassNotFoundException exception) {
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