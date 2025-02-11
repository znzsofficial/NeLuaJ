//
// Source code recreated from a .class file by IntelliJ IDEA
// (powered by FernFlower decompiler)
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

public class JavaClass extends JavaInstance implements CoerceJavaToLua.Coercion {
    static final HashMap<LuaValue, LuaValue> i = new HashMap<>();
    static final Map<Class<?>, JavaClass> j = Collections.synchronizedMap(new HashMap());
    static final Map<String, JavaClass> k = Collections.synchronizedMap(new HashMap());
    static final LuaValue l = LuaValue.valueOf("new");
    final HashMap<LuaValue, Integer> m = new HashMap<>();
    final HashMap<LuaValue, Integer> n = new HashMap<>();
    final HashMap<LuaValue, Integer> o = new HashMap<>();
    final HashMap<LuaValue, LuaValue> p = new HashMap<>();
    final HashMap<LuaValue, LuaValue> q = new HashMap<>();
    final HashMap<LuaValue, LuaValue> r = new HashMap<>();
    Map<LuaValue, Field> s;
    Map<LuaValue, LuaValue> t;
    Map<LuaValue, JavaClass> u;

    static {
        for (Method method : Class.class.getMethods()) {
            i.put(LuaValue.valueOf(method.getName()), JavaMethod.a(method));
        }
    }

    JavaClass(Class<?> var1) {
        super(var1);
        super.f = this;
    }

    static JavaClass a(Class<?> var0) {
        JavaClass javaClass = j.get(var0);
        if (javaClass == null) {
            javaClass = new JavaClass(var0);
            ((Map) j).put(var0, javaClass);
        }
        return javaClass;
    }

    static JavaClass a(String var0, ClassLoader var1) throws ClassNotFoundException {
        JavaClass var3 = k.get(var0);
        JavaClass var2 = var3;
        if (var3 == null) {
            var2 = a(Class.forName(var0, true, var1));
            ((Map) k).put(var0, var2);
        }
        return var2;
    }

    static JavaClass f(String var0) throws ClassNotFoundException {
        JavaClass var2 = k.get(var0);
        JavaClass var1 = var2;
        if (var2 == null) {
            var1 = a(Class.forName(var0));
            ((Map) k).put(var0, var1);
        }

        return var1;
    }

    Field b(LuaValue var1) {
        if (this.s == null) {
            HashMap var4 = new HashMap();
            Field[] var3 = ((Class<?>) super.b).getFields();

            for (int var2 = var3.length - 1; var2 >= 0; --var2) {
                Field var5 = var3[var2];
                if (Modifier.isPublic(var5.getModifiers())) {
                    var4.put(LuaValue.valueOf(var5.getName()), var5);

                    try {
                        if (!var5.isAccessible()) {
                            var5.setAccessible(true);
                        }
                    } catch (SecurityException ignored) {
                    }
                }
            }

            this.s = var4;
        }

        return this.s.get(var1);
    }

    JavaClass c(LuaValue var1) {
        if (this.u == null) {
            HashMap var5 = new HashMap();

            for (Class var4 = (Class) super.b; var4 != null; var4 = var4.getSuperclass()) {
                for (Class var7 : var4.getDeclaredClasses()) {
                    if (Modifier.isPublic(var7.getModifiers())) {
                        String var8 = var7.getName();
                        LuaString var9 = LuaValue.valueOf(var8.substring(Math.max(var8.lastIndexOf(36), var8.lastIndexOf(46)) + 1));
                        if (!var5.containsKey(var9)) {
                            var5.put(var9, a(var7));
                        }
                    }
                }
            }

            this.u = var5;
        }
        return this.u.get(var1);
    }

    public LuaValue call() {
        try {
            return new JavaInstance(((Class<?>) super.b).newInstance());
        } catch (Exception var2) {
            return this.getMethod(l).call();
        }
    }

    public LuaValue call(LuaValue arg) {
        Class<?> obj = (Class<?>) this.touserdata();
        if (arg.istable()) {
            if (obj.isPrimitive()) {
                return CoerceJavaToLua.coerce((new CoerceLuaToJava.ArrayCoercion(obj)).coerce(arg));
            } else if (obj.isInterface()) {
                return LuajavaLib.createProxy(obj, arg);
            } else if ((obj.getModifiers() & Modifier.ABSTRACT) != 0) {
                try {
                    return LuajavaLib.override(obj, arg).call();
                } catch (Exception e) {
                    throw new LuaError(e);
                }
            } else if (Map.class.isAssignableFrom(obj)) {
                return CoerceJavaToLua.coerce((new CoerceLuaToJava.MapCoercion(obj)).coerce(arg));
            } else if (List.class.isAssignableFrom(obj)) {
                return CoerceJavaToLua.coerce((new CoerceLuaToJava.CollectionCoercion(obj)).coerce(arg));
            } else if (arg.length() == 0 && arg.checktable().size() > 0) {
                try {
                    return LuajavaLib.override(obj, arg);
                } catch (Exception var4) {
                    throw new LuaError(var4);
                }
            } else {
                try {
                    return this.get(l).call(arg);
                } catch (Exception var6) {
                    return CoerceJavaToLua.coerce((new CoerceLuaToJava.ArrayCoercion(obj)).coerce(arg));
                }
            }
        } else if (obj.isPrimitive()) {
            return new JavaInstance(CoerceLuaToJava.coerce(arg, obj));
        } else {
            return this.getMethod(l).call(arg);
        }
    }

    public LuaValue call(LuaValue var1, LuaValue var2) {
        return this.getMethod(l).call(var1, var2);
    }

    public LuaValue call(LuaValue var1, LuaValue var2, LuaValue var3) {
        return this.getMethod(l).call(var1, var2, var3);
    }

    public LuaValue coerce(Object var1) {
        return this;
    }


    @Override
    public LuaValue get(LuaValue key) {
        if (key.isnumber())
            return CoerceJavaToLua.c.coerce(Array.newInstance((Class<?>) touserdata(), key.toint()));
        return switch (key.tojstring()) {
            case "override" -> new LuajavaLib.override(this);
            case "new" -> getMethod(key);
            case "array" -> new OneArgFunction() {
                public LuaValue call(LuaValue var1) {
                    return CoerceJavaToLua.coerce((new CoerceLuaToJava.ArrayCoercion((Class) JavaClass.super.b)).coerce(var1));
                }
            };
            case "class" -> this;
            default -> super.get(key);
        };
    }

    public LuaValue getConstructor() {
        return this.getMethod(l);
    }

    public LuaValue getMethod(LuaValue var1) {
        if (this.t == null) {
            HashMap<String, List> methodMap = new HashMap<>();
            Method[] methods = ((Class) super.b).getMethods();

            for (Method method : methods) {
                if (Modifier.isPublic(method.getModifiers())) {
                    // 获取方法名
                    String methodName = method.getName();

                    // 从方法映射中获取与该方法名对应的 JavaMethod 列表
                    List<JavaMethod> methodList = (List<JavaMethod>) methodMap.get(methodName);

                    // 如果该方法名的列表为空，则初始化一个新的列表
                    if (methodList == null) {
                        methodList = new ArrayList<>();
                        methodMap.put(methodName, methodList);
                    }

                    // 将该方法转化为 JavaMethod 对象并添加到方法列表中
                    methodList.add(JavaMethod.a(method));
                }
            }


            HashMap constructorMap = new HashMap();
            Constructor[] constructors = ((Class) super.b).getConstructors();
            if (constructors.length == 0) {
                constructors = ((Class) super.b).getDeclaredConstructors();
            }

            ArrayList list = new ArrayList();

            for (Constructor constructor : constructors) {
                if (Modifier.isPublic(constructor.getModifiers())) {
                    constructor.setAccessible(true);
                    list.add(JavaConstructor.a(constructor));
                }
            }

            switch (list.size()) {
                case 0:
                    break;
                case 1:
                    constructorMap.put(l, list.get(0));
                    break;
                default:
                    constructorMap.put(l, JavaConstructor.forConstructors((JavaConstructor[]) list.toArray(new JavaConstructor[list.size()])));
                    break;
            }

            constructorMap.putAll(i);

            for (Map.Entry var13 : methodMap.entrySet()) {
                String methodNameKey = (String) var13.getKey();
                List methodList = (List) var13.getValue();
                LuaString luaMethodName = LuaValue.valueOf(methodNameKey);
                Object methodValue;
                if (methodList.size() == 1) {
                    methodValue = methodList.get(0);
                } else {
                    methodValue = JavaMethod.a((JavaMethod[]) methodList.toArray(new JavaMethod[methodList.size()]));
                }

                constructorMap.put(luaMethodName, methodValue);
            }

            this.t = constructorMap;
        }

        return this.t.get(var1);
    }

    public Varargs invoke(Varargs var1) {
        if (var1.narg() == 1) {
            Class var3 = (Class) this.touserdata();
            LuaValue var2 = var1.arg1();
            if (var2.istable()) {
                if (var3.isPrimitive()) {
                    var1 = CoerceJavaToLua.coerce((new CoerceLuaToJava.ArrayCoercion(var3)).coerce(var2));
                    return var1;
                } else if (var3.isInterface()) {
                    var1 = LuajavaLib.createProxy(var3, var2);
                    return var1;
                } else if ((var3.getModifiers() & 1024) != 0) {
                    try {
                        return LuajavaLib.override(var3, var2).call();
                    } catch (Exception e) {
                        throw new LuaError(e);
                    }
                } else if (Map.class.isAssignableFrom(var3)) {
                    var1 = CoerceJavaToLua.coerce((new CoerceLuaToJava.MapCoercion(var3)).coerce(var2));
                    return var1;
                } else if (List.class.isAssignableFrom(var3)) {
                    var1 = CoerceJavaToLua.coerce((new CoerceLuaToJava.CollectionCoercion(var3)).coerce(var2));
                    return var1;
                } else if (var2.length() == 0 && var2.checktable().size() > 0) {
                    try {
                        var1 = LuajavaLib.override(var3, var2);
                        return var1;
                    } catch (Exception var5) {
                        throw new LuaError(var5);
                    }
                } else {
                    try {
                        var1 = this.get(l).invoke(var1);
                    } catch (Exception var4) {
                        var1 = CoerceJavaToLua.coerce((new CoerceLuaToJava.ArrayCoercion(var3)).coerce(var2));
                    }

                    return var1;
                }
            }

            if (var3.isPrimitive()) {
                var1 = new JavaInstance(CoerceLuaToJava.coerce(var2, var3));
                return var1;
            }
        }

        var1 = this.get(l).invoke(var1);
        return var1;
    }
}
