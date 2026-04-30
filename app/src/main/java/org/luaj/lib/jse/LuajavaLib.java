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

public class LuajavaLib extends VarArgFunction {
    static final String[] d = new String[]{"bindClass", "newInstance", "new", "createProxy", "loadLib", "astable", "instanceof"};
    public ArrayList<ClassLoader> e = new ArrayList<>();
    public HashMap<String, LuaValue> f = new HashMap<>();

    public static LuaValue asTable(Object object) {
        if (object == null) {
            return LuaValue.NIL;
        }

        LuaTable table = new LuaTable();
        if (object.getClass().isArray()) {
            int length = Array.getLength(object);
            for (int index = 0; index < length; index++) {
                table.set(index + 1, asTable(Array.get(object, index)));
            }
        } else if (object instanceof Collection) {
            int index = 1;
            for (Object item : (Collection<?>) object) {
                table.set(index++, asTable(item));
            }
        } else if (object instanceof Map) {
            for (Map.Entry<?, ?> entry : ((Map<?, ?>) object).entrySet()) {
                table.set(CoerceJavaToLua.coerce(entry.getKey()), asTable(entry.getValue()));
            }
        } else if (object instanceof JSONObject) {
            JSONObject jsonObject = (JSONObject) object;
            Iterator<?> keys = jsonObject.keys();
            while (keys.hasNext()) {
                String key = (String) keys.next();
                try {
                    table.set(key, asTable(jsonObject.get(key)));
                } catch (JSONException ignored) {
                }
            }
        } else if (object instanceof JSONArray) {
            JSONArray jsonArray = (JSONArray) object;
            int length = jsonArray.length();
            for (int index = 0; index < length; index++) {
                try {
                    table.set(index + 1, asTable(jsonArray.get(index)));
                } catch (JSONException ignored) {
                }
            }
        } else {
            return CoerceJavaToLua.coerce(object);
        }

        return table;
    }

    public static LuaValue asTable(Object object, boolean recursive) {
        if (recursive) {
            return asTable(object);
        }
        if (object == null) {
            return LuaValue.NIL;
        }

        LuaTable table = new LuaTable();
        if (object.getClass().isArray()) {
            int length = Array.getLength(object);
            for (int index = 0; index < length; index++) {
                table.set(index + 1, CoerceJavaToLua.coerce(Array.get(object, index)));
            }
        } else if (object instanceof Collection) {
            int index = 1;
            for (Object item : (Collection<?>) object) {
                table.set(index++, CoerceJavaToLua.coerce(item));
            }
        } else if (object instanceof Map) {
            for (Map.Entry<?, ?> entry : ((Map<?, ?>) object).entrySet()) {
                table.set(CoerceJavaToLua.coerce(entry.getKey()), CoerceJavaToLua.coerce(entry.getValue()));
            }
        } else if (object instanceof JSONObject) {
            JSONObject jsonObject = (JSONObject) object;
            Iterator<?> keys = jsonObject.keys();
            while (keys.hasNext()) {
                String key = (String) keys.next();
                try {
                    table.set(key, CoerceJavaToLua.coerce(jsonObject.get(key)));
                } catch (JSONException ignored) {
                }
            }
        } else if (object instanceof JSONArray) {
            JSONArray jsonArray = (JSONArray) object;
            int length = jsonArray.length();
            for (int index = 0; index < length; index++) {
                try {
                    table.set(index + 1, CoerceJavaToLua.coerce(jsonArray.get(index)));
                } catch (JSONException ignored) {
                }
            }
        } else {
            return CoerceJavaToLua.coerce(object);
        }

        return table;
    }

    public static LuaUserdata createProxy(Class type, LuaValue value) {
        ProxyInvocationHandler handler = new ProxyInvocationHandler(value);
        return LuaValue.userdataOf(Proxy.newProxyInstance(type.getClassLoader(), new Class[]{type}, handler));
    }

    public static LuaValue override(Class type, LuaValue value) {
        return JavaClass.a((new LuaEnhancer(type)).create(value));
    }

    public LuaValue bindClassForName(String className) throws ClassNotFoundException {
        LuaValue cached = this.f.get(className);
        if (cached != null) {
            return cached;
        }

        try {
            LuaValue javaClass = JavaClass.f(className);
            this.f.put(className, javaClass);
            return javaClass;
        } catch (Exception ignored) {
            for (ClassLoader classLoader : this.e) {
                try {
                    LuaValue javaClass = JavaClass.a(className, classLoader);
                    this.f.put(className, javaClass);
                    return javaClass;
                } catch (Exception ignored2) {
                }
            }
            throw new ClassNotFoundException(className);
        }
    }

    protected Class<?> f(String className) throws ClassNotFoundException {
        return Class.forName(className);
    }

    public Varargs invoke(Varargs args) {
        try {
            switch (super.b) {
                case 0:
                    return load(args);
                case 1:
                    return JavaClass.a(this.f(args.checkjstring(1)));
                case 2:
                case 3:
                    return newInstance(args);
                case 4:
                    return createProxy(args);
                case 5:
                    return loadLib(args);
                case 6:
                    if (args.istable(1)) {
                        return args.checktable(1);
                    }
                    return asTable(args.checkuserdata(1), args.optboolean(2, false));
                case 7:
                    return LuaValue.valueOf(((Class) args.arg(2).touserdata(Class.class)).isInstance(args.checkuserdata(1)));
                default:
                    throw new LuaError("not yet supported: " + this);
            }
        } catch (LuaError error) {
            throw error;
        } catch (InvocationTargetException exception) {
            throw new LuaError(exception.getTargetException());
        } catch (Exception exception) {
            throw new LuaError(exception);
        }
    }

    private Varargs load(Varargs args) {
        LuaValue env = args.arg(2);
        env.checkglobals().s = this;
        LuaTable table = new LuaTable();
        a(table, this.getClass(), d, 1);
        env.set("luajava", table);
        env.get("package").get("loaded").set("luajava", table);
        env.set("boolean", JavaClass.a(Boolean.TYPE));
        env.set("byte", JavaClass.a(Byte.TYPE));
        env.set("char", JavaClass.a(Character.TYPE));
        env.set("short", JavaClass.a(Short.TYPE));
        env.set("int", JavaClass.a(Integer.TYPE));
        env.set("long", JavaClass.a(Long.TYPE));
        env.set("float", JavaClass.a(Float.TYPE));
        env.set("double", JavaClass.a(Double.TYPE));
        env.set("import", new ImportFunction(this, env));
        return table;
    }

    private Varargs newInstance(Varargs args) throws ClassNotFoundException {
        LuaValue target = args.checkvalue(1);
        Class<?> type;
        if (super.b == 2) {
            type = this.f(target.tojstring());
        } else {
            type = (Class<?>) target.checkuserdata(Class.class);
        }
        return JavaClass.a(type).getConstructor().invoke(args.subargs(2));
    }

    private Varargs createProxy(Varargs args) throws ClassNotFoundException {
        int interfaceCount = args.narg() - 1;
        if (interfaceCount <= 0) {
            throw new LuaError("no interfaces");
        }

        LuaTable table = args.checktable(interfaceCount + 1);
        Class[] interfaces = new Class[interfaceCount];
        for (int index = 0; index < interfaceCount; index++) {
            interfaces[index] = this.f(args.checkjstring(index + 1));
        }

        ProxyInvocationHandler handler = new ProxyInvocationHandler(table);
        return LuaValue.userdataOf(Proxy.newProxyInstance(this.getClass().getClassLoader(), interfaces, handler));
    }

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

    private static final class ImportFunction extends VarArgFunction {
        final LuaValue d;
        final LuajavaLib e;

        private ImportFunction(LuajavaLib luajava, LuaValue env) {
            this.e = luajava;
            this.d = env;
        }

        public Varargs invoke(Varargs args) {
            try {
                String className = args.checkjstring(1);
                String simpleName = className.replaceFirst(".*?[$\\.]([^$\\.]*)$", "$1");
                LuaValue javaClass = this.e.bindClassForName(className);
                this.d.set(simpleName, javaClass);
                return javaClass;
            } catch (ClassNotFoundException exception) {
                throw new LuaError(exception);
            }
        }
    }

    private static final class ProxyInvocationHandler implements InvocationHandler {
        private final LuaValue a;

        private ProxyInvocationHandler(LuaValue value) {
            this.a = value;
        }

        public Object invoke(Object proxy, Method method, Object[] args) {
            String methodName = method.getName();
            LuaValue function = this.a.isfunction() ? this.a : this.a.get(methodName);

            if (!function.isnil()) {
                LuaValue[] luaArgs = toLuaArgs(method, args);
                try {
                    return CoerceLuaToJava.coerce(function.invoke(luaArgs).arg1(), method.getReturnType());
                } catch (Exception exception) {
                    LuaActivity.logError(methodName, exception);
                }
            }

            Object defaultObjectResult = getDefaultObjectMethodResult(proxy, method, args);
            if (defaultObjectResult != null) {
                return defaultObjectResult;
            }

            return CoerceLuaToJava.coerce(LuaValue.NIL, method.getReturnType());
        }

        private static Object getDefaultObjectMethodResult(Object proxy, Method method, Object[] args) {
            String methodName = method.getName();
            Class<?>[] parameterTypes = method.getParameterTypes();
            if (parameterTypes.length == 1 && methodName.equals("equals") && parameterTypes[0] == Object.class) {
                Object other = args != null && args.length > 0 ? args[0] : null;
                return proxy == other;
            }
            if (parameterTypes.length == 0 && methodName.equals("hashCode")) {
                return System.identityHashCode(proxy);
            }
            if (parameterTypes.length == 0 && methodName.equals("toString")) {
                Class<?>[] interfaces = proxy.getClass().getInterfaces();
                String typeName = interfaces.length > 0 ? interfaces[0].getName() : proxy.getClass().getName();
                return typeName + "@" + Integer.toHexString(System.identityHashCode(proxy));
            }
            return null;
        }

        private static LuaValue[] toLuaArgs(Method method, Object[] args) {
            int argCount = args != null ? args.length : 0;
            boolean isVarArgs = (method.getModifiers() & 0x80) != 0;
            if (!isVarArgs || argCount == 0) {
                LuaValue[] luaArgs = new LuaValue[argCount];
                for (int index = 0; index < argCount; index++) {
                    luaArgs[index] = CoerceJavaToLua.coerce(args[index]);
                }
                return luaArgs;
            }

            int fixedArgCount = argCount - 1;
            Object varArgArray = args[fixedArgCount];
            int varArgCount = varArgArray != null ? Array.getLength(varArgArray) : 0;
            LuaValue[] luaArgs = new LuaValue[fixedArgCount + varArgCount];
            for (int index = 0; index < fixedArgCount; index++) {
                luaArgs[index] = CoerceJavaToLua.coerce(args[index]);
            }
            for (int index = 0; index < varArgCount; index++) {
                luaArgs[index + fixedArgCount] = CoerceJavaToLua.coerce(Array.get(varArgArray, index));
            }
            return luaArgs;
        }
    }

    public static final class override extends OneArgFunction {
        private final Class d;

        public override(JavaClass javaClass) {
            this.d = (Class) ((LuaUserdata) javaClass).touserdata(Class.class);
        }

        public LuaValue call(LuaValue value) {
            try {
                return LuajavaLib.override(this.d, value);
            } catch (Exception exception) {
                throw new LuaError(exception);
            }
        }
    }
}
