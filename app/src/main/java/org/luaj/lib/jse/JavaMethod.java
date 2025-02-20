package org.luaj.lib.jse;

//
// Source code recreated from a .class file by IntelliJ IDEA
// (powered by FernFlower decompiler)
//

import org.luaj.LuaError;
import org.luaj.LuaFunction;
import org.luaj.LuaValue;
import org.luaj.Varargs;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

class JavaMethod extends JavaMember {
    static final Map<Method, LuaValue> h = Collections.synchronizedMap(new HashMap<>());// methods
    private final Class<?> i;// return type
    final Method j;

    private JavaMethod(Method method) {
        super(method.getParameterTypes(), method.getModifiers());
        this.j = method;
        this.i = method.getReturnType();

        try {
            if (!method.isAccessible()) {
                method.setAccessible(true);
            }
        } catch (Exception ignored) {
        }

    }

    static LuaFunction a(JavaMethod[] var0) {
        return new Overload(var0);
    }

    static JavaMethod a(Method m) {
        JavaMethod method = (JavaMethod) h.get(m);
        if (method == null) {
            try {
                method = new JavaMethod(m);
                h.put(m, method);
            } catch (Throwable ignored) {
                // skip this method
            }
        }
        return method;
    }

    public LuaValue call() {
        LuaValue.error("method cannot be called without instance");
        throw null;
    }

    public LuaValue call(LuaValue var1) {
        return this.invokeJavaMethod(var1, LuaValue.NONE);
    }

    public LuaValue call(LuaValue var1, LuaValue var2) {
        return this.invokeJavaMethod(var1, var2);
    }

    public LuaValue call(LuaValue var1, LuaValue var2, LuaValue var3) {
        return this.invokeJavaMethod(var1, LuaValue.varargsOf(var2, var3));
    }

    public Varargs invoke(Varargs var1) {
        return this.invokeJavaMethod(var1.arg(1), var1.subargs(2));
    }

    public Varargs invoke(LuaValue[] var1) {
        return this.invoke(LuaValue.varargsOf(var1));
    }

    public LuaValue invokeJavaMethod(LuaValue obj, Varargs var2) {
        if (super.e == null && super.d.length != var2.narg()) {
            throw new IllegalArgumentException(this.j.toString());
        } else {
            Object instance = obj.checkuserdata();
            Object[] var6 = this.a(var2);

            try {
                if (this.i == Void.TYPE) {
                    this.j.invoke(instance, var6);
                } else {
                    obj = CoerceJavaToLua.coerce(this.j.invoke(instance, var6));
                }
                return obj;
            } catch (InvocationTargetException targetException) {
                targetException.getTargetException().printStackTrace();
                throw new LuaError(this.j +
                        " " +
                        targetException.getTargetException());
            } catch (Exception e) {
                return LuaValue.error("coercion error " +
                        this.j +
                        " " +
                        e);
            }
        }
    }

    public String tojstring() {
        return "JavaMethod{\n  " +
                this.j +
                "\n}";
    }

    public static class JavaOOMethod extends LuaValue {
        private final JavaInstance b;
        private final LuaValue c;

        public JavaOOMethod(JavaInstance var1, LuaValue var2) {
            this.b = var1;
            this.c = var2;
        }

        public LuaValue call() {
            return this.c.invokeJavaMethod(this.b, LuaValue.NONE);
        }

        public LuaValue call(LuaValue var1) {
            return this.c.invokeJavaMethod(this.b, var1);
        }

        public LuaValue call(LuaValue var1, LuaValue var2) {
            return this.c.invokeJavaMethod(this.b, LuaValue.varargsOf(var1, var2));
        }

        public LuaValue call(LuaValue var1, LuaValue var2, LuaValue var3) {
            return this.c.invokeJavaMethod(this.b, LuaValue.varargsOf(var1, var2, var3));
        }

        public Varargs invoke(Varargs var1) {
            return this.c.invokeJavaMethod(this.b, var1);
        }

        public Varargs invoke(LuaValue[] var1) {
            return this.invoke(LuaValue.varargsOf(var1));
        }

        public String tojstring() {
            return this.c.tojstring();
        }

        public int type() {
            return this.c.type();
        }

        public String typename() {
            return this.c.typename();
        }
    }

    static class Overload extends LuaFunction {
        final JavaMethod[] b;

        Overload(JavaMethod[] var1) {
            this.b = var1;
        }

        public LuaValue call() {
            LuaValue.error("method cannot be called without instance");
            throw null;
        }

        public LuaValue call(LuaValue var1) {
            return this.invokeJavaMethod(var1, LuaValue.NONE);
        }

        public LuaValue call(LuaValue var1, LuaValue var2) {
            return this.invokeJavaMethod(var1, var2);
        }

        public LuaValue call(LuaValue var1, LuaValue var2, LuaValue var3) {
            return this.invokeJavaMethod(var1, LuaValue.varargsOf(var2, var3));
        }

        public Varargs invoke(Varargs var1) {
            return this.invokeJavaMethod(var1.arg(1), var1.subargs(2));
        }

        public Varargs invoke(LuaValue[] var1) {
            return this.invoke(LuaValue.varargsOf(var1));
        }

        public LuaValue invokeJavaMethod(LuaValue obj, Varargs args) {
            int bestMatchScore = CoerceLuaToJava.e;  // 初始匹配分数
            JavaMethod bestMethod = null;  // 最佳匹配方法
            int methodIndex = 0;  // 当前遍历的方法索引

            JavaMethod[] methods = this.b;  // 获取所有的 Java 方法

            // 遍历所有的 Java 方法，找到最佳匹配方法
            while (methodIndex < methods.length) {
                JavaMethod currentMethod = methods[methodIndex];  // 当前方法
                int matchScore = currentMethod.b(args);  // 获取与 args 的匹配分数

                // 如果当前方法的匹配分数更高，更新最佳方法
                if (matchScore < bestMatchScore) {
                    bestMatchScore = matchScore;
                    bestMethod = currentMethod;
                    // 如果完全匹配，提前退出
                    if (matchScore == 0) {
                        break;
                    }
                }

                methodIndex++;
            }

            // 如果找到了最佳匹配方法，调用它
            if (bestMethod != null) {
                return bestMethod.invokeJavaMethod(obj, args);
            } else {
                // 如果没有找到匹配方法，抛出一个异常
                String errorMessage = "no coercible public method\n" + this + "\n current args: " + args;
                LuaValue.error(errorMessage);  // 错误提示
                throw new LuaError(errorMessage);  // 抛出 LuaError 异常
            }
        }


        public String tojstring() {
            StringBuilder sb = new StringBuilder();
            sb.append("JavaMethod{\n");

            for (JavaMethod var5 : this.b) {
                sb.append("  ");
                sb.append(var5.j);
                sb.append("\n");
            }
            sb.append("}");
            return sb.toString();
        }
    }
}
