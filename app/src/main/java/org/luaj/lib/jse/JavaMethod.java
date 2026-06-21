package org.luaj.lib.jse;

//
// Source code recreated from a .class file by IntelliJ IDEA
// (powered by FernFlower decompiler)
// Optimized with improved variable naming, comments, and performance
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

/**
 * 表示Java方法的Lua值。
 * 支持单个方法和重载方法的调用。
 */
class JavaMethod extends JavaMember {
    // 方法缓存：Method -> JavaMethod（保持原有字段名以保证兼容性）
    static final Map<Method, LuaValue> h = Collections.synchronizedMap(new HashMap<>());
    
    // 返回类型
    private final Class<?> i;
    
    // 原始Method对象
    final Method j;

    /**
     * 私有构造函数
     * @param method 要包装的Method对象
     */
    private JavaMethod(Method method) {
        super(method.getParameterTypes(), method.getModifiers());
        this.j = method;
        this.i = method.getReturnType();

        // 确保方法可访问
        try {
            if (!method.isAccessible()) {
                method.setAccessible(true);
            }
        } catch (Exception ignored) {
            // 某些方法可能无法设置为可访问
        }
    }

    /**
     * 创建重载方法包装器
     * @param methods 重载的方法数组
     * @return 包装后的LuaFunction
     */
    static LuaFunction a(JavaMethod[] methods) {
        return new Overload(methods);
    }

    /**
     * 获取或创建JavaMethod实例（使用缓存）
     * @param method 原始Method对象
     * @return 对应的JavaMethod实例
     */
    static JavaMethod a(Method method) {
        JavaMethod cached = (JavaMethod) h.get(method);
        if (cached == null) {
            try {
                cached = new JavaMethod(method);
                h.put(method, cached);
            } catch (Throwable ignored) {
                // 跳过无法创建的方法
            }
        }
        return cached;
    }

    /**
     * 无参调用（错误：方法需要实例）
     */
    public LuaValue call() {
        throw new LuaError("Java method '" + this.j.getName() + "' cannot be called without an instance.\n" +
            "Method: " + this.j + "\n" +
            "Usage: instance:" + this.j.getName() + "(...)");
    }

    /**
     * 单参数调用
     * @param instance 实例对象
     * @return 调用结果
     */
    public LuaValue call(LuaValue instance) {
        return this.invokeJavaMethod(instance, LuaValue.NONE);
    }

    /**
     * 双参数调用
     * @param instance 实例对象
     * @param arg1 第一个参数
     * @return 调用结果
     */
    public LuaValue call(LuaValue instance, LuaValue arg1) {
        return this.invokeJavaMethod(instance, arg1);
    }

    /**
     * 三参数调用
     * @param instance 实例对象
     * @param arg1 第一个参数
     * @param arg2 第二个参数
     * @return 调用结果
     */
    public LuaValue call(LuaValue instance, LuaValue arg1, LuaValue arg2) {
        return this.invokeJavaMethod(instance, LuaValue.varargsOf(arg1, arg2));
    }

    /**
     * 可变参数调用
     * @param args 参数列表（第一个参数是实例）
     * @return 调用结果
     */
    public Varargs invoke(Varargs args) {
        return this.invokeJavaMethod(args.arg(1), args.subargs(2));
    }

    /**
     * 数组参数调用
     * @param args 参数数组
     * @return 调用结果
     */
    public Varargs invoke(LuaValue[] args) {
        return this.invoke(LuaValue.varargsOf(args));
    }

    /**
     * 执行Java方法调用
     * @param instance 实例对象
     * @param args 方法参数
     * @return 调用结果
     */
    public LuaValue invokeJavaMethod(LuaValue instance, Varargs args) {
        // 检查参数数量（如果不是可变参数方法）
        if (super.e == null && super.d.length != args.narg()) {
            throw new LuaError(buildArgCountError(args));
        }
        
        Object javaInstance = instance.checkuserdata();
        Object[] javaArgs = this.a(args);

        try {
            // 调用方法并转换结果
            if (this.i == Void.TYPE) {
                // void方法
                this.j.invoke(javaInstance, javaArgs);
                return instance; // 返回实例本身
            } else {
                // 有返回值的方法
                return CoerceJavaToLua.coerce(this.j.invoke(javaInstance, javaArgs));
            }
        } catch (InvocationTargetException targetException) {
            // 方法内部抛出的异常
            Throwable cause = targetException.getTargetException();
            throw new LuaError(buildInvocationError(args, cause));
        } catch (Exception e) {
            // 其他异常（参数类型不匹配等）
            throw new LuaError(buildCoercionError(args, e));
        }
    }

    /**
     * 构建参数数量错误信息
     */
    private String buildArgCountError(Varargs args) {
        return "method argument count mismatch for '" + this.j.getName() + "'\n" +
            "Method: " + this.j + "\n" +
            "Expected: " + this.d.length + " arguments\n" +
            "Got: " + args.narg() + " arguments\n" +
            "Arguments: " + describeArgs(args);
    }

    /**
     * 构建方法调用错误信息
     */
    private String buildInvocationError(Varargs args, Throwable cause) {
        return "exception in Java method '" + this.j.getName() + "'\n" +
            "Method: " + this.j + "\n" +
            "Arguments: " + describeArgs(args) + "\n" +
            "Cause: " + cause.getClass().getSimpleName() + ": " + cause.getMessage();
    }

    /**
     * 构建参数转换错误信息
     */
    private String buildCoercionError(Varargs args, Exception exception) {
        return "failed to invoke Java method '" + this.j.getName() + "'\n" +
            "Method: " + this.j + "\n" +
            "Arguments: " + describeArgs(args) + "\n" +
            "Error: " + exception.getClass().getSimpleName() + ": " + exception.getMessage();
    }

    /**
     * 描述参数列表
     */
    private static String describeArgs(Varargs args) {
        StringBuilder sb = new StringBuilder("[");
        int n = args.narg();
        for (int i = 1; i <= n; i++) {
            if (i > 1) {
                sb.append(", ");
            }
            LuaValue arg = args.arg(i);
            sb.append(arg.typename());
            sb.append('=');
            sb.append(arg);
        }
        sb.append(']');
        return sb.toString();
    }

    /**
     * 返回方法的字符串表示
     */
    public String tojstring() {
        return "JavaMethod{\n  " + this.j + "\n}";
    }

    /**
     * 表示绑定到特定实例的方法（面向对象调用模式）
     */
    public static class JavaOOMethod extends LuaValue {
        private final JavaInstance boundInstance;
        private final LuaValue method;

        /**
         * 构造函数
         * @param instance 绑定的实例
         * @param method 要调用的方法
         */
        public JavaOOMethod(JavaInstance instance, LuaValue method) {
            this.boundInstance = instance;
            this.method = method;
        }

        public LuaValue call() {
            return this.method.invokeJavaMethod(this.boundInstance, LuaValue.NONE);
        }

        public LuaValue call(LuaValue arg1) {
            return this.method.invokeJavaMethod(this.boundInstance, arg1);
        }

        public LuaValue call(LuaValue arg1, LuaValue arg2) {
            return this.method.invokeJavaMethod(this.boundInstance, LuaValue.varargsOf(arg1, arg2));
        }

        public LuaValue call(LuaValue arg1, LuaValue arg2, LuaValue arg3) {
            return this.method.invokeJavaMethod(this.boundInstance, LuaValue.varargsOf(arg1, arg2, arg3));
        }

        public Varargs invoke(Varargs args) {
            return this.method.invokeJavaMethod(this.boundInstance, args);
        }

        public Varargs invoke(LuaValue[] args) {
            return this.invoke(LuaValue.varargsOf(args));
        }

        public String tojstring() {
            return this.method.tojstring();
        }

        public int type() {
            return this.method.type();
        }

        public String typename() {
            return this.method.typename();
        }
    }

    /**
     * 表示重载方法的包装器
     * 根据参数类型自动选择最佳匹配的方法
     */
    static class Overload extends LuaFunction {
        final JavaMethod[] overloadedMethods;

        /**
         * 构造函数
         * @param methods 重载的方法数组
         */
        Overload(JavaMethod[] methods) {
            this.overloadedMethods = methods;
        }

        /**
         * 无参调用（错误：方法需要实例）
         */
        public LuaValue call() {
            throw new LuaError("Java method '" + this.overloadedMethods[0].j.getName() + 
                "' cannot be called without an instance.\n" +
                "Usage: instance:" + this.overloadedMethods[0].j.getName() + "(...)");
        }

        /**
         * 单参数调用
         */
        public LuaValue call(LuaValue instance) {
            return this.invokeJavaMethod(instance, LuaValue.NONE);
        }

        /**
         * 双参数调用
         */
        public LuaValue call(LuaValue instance, LuaValue arg1) {
            return this.invokeJavaMethod(instance, arg1);
        }

        /**
         * 三参数调用
         */
        public LuaValue call(LuaValue instance, LuaValue arg1, LuaValue arg2) {
            return this.invokeJavaMethod(instance, LuaValue.varargsOf(arg1, arg2));
        }

        /**
         * 可变参数调用
         */
        public Varargs invoke(Varargs args) {
            return this.invokeJavaMethod(args.arg(1), args.subargs(2));
        }

        /**
         * 数组参数调用
         */
        public Varargs invoke(LuaValue[] args) {
            return this.invoke(LuaValue.varargsOf(args));
        }

        /**
         * 执行重载方法调用，自动选择最佳匹配的方法
         * @param instance 实例对象
         * @param args 方法参数
         * @return 调用结果
         */
        public LuaValue invokeJavaMethod(LuaValue instance, Varargs args) {
            int bestMatchScore = CoerceLuaToJava.e;  // 初始匹配分数（最差）
            JavaMethod bestMethod = null;  // 最佳匹配方法

            // 遍历所有重载方法，找到最佳匹配
            for (JavaMethod currentMethod : this.overloadedMethods) {
                int matchScore = currentMethod.b(args);  // 计算匹配分数

                // 如果当前方法匹配更好，更新最佳方法
                if (matchScore < bestMatchScore) {
                    bestMatchScore = matchScore;
                    bestMethod = currentMethod;
                    
                    // 如果完全匹配，提前退出
                    if (matchScore == 0) {
                        break;
                    }
                }
            }

            // 调用最佳匹配方法
            if (bestMethod != null) {
                return bestMethod.invokeJavaMethod(instance, args);
            } else {
                // 没有找到匹配方法，抛出详细的错误信息
                throw new LuaError(buildNoMatchingMethodError(args));
            }
        }

        /**
         * 构建无匹配方法的错误信息
         */
        private String buildNoMatchingMethodError(Varargs args) {
            StringBuilder sb = new StringBuilder();
            sb.append("no matching overload found for method '");
            sb.append(this.overloadedMethods[0].j.getName());
            sb.append("'\n\n");
            
            sb.append("Arguments provided: ");
            sb.append(describeArgs(args));
            sb.append("\n\n");
            
            sb.append("Available overloads:\n");
            for (JavaMethod method : this.overloadedMethods) {
                sb.append("  - ");
                sb.append(method.j);
                sb.append("\n");
            }
            
            sb.append("\nHint: Check that argument types match the method signatures.");
            return sb.toString();
        }

        /**
         * 描述参数列表
         */
        private static String describeArgs(Varargs args) {
            StringBuilder sb = new StringBuilder("[");
            int n = args.narg();
            for (int i = 1; i <= n; i++) {
                if (i > 1) {
                    sb.append(", ");
                }
                LuaValue arg = args.arg(i);
                sb.append(arg.typename());
                sb.append('=');
                sb.append(arg);
            }
            sb.append(']');
            return sb.toString();
        }

        /**
         * 返回所有重载方法的字符串表示
         */
        public String tojstring() {
            StringBuilder sb = new StringBuilder();
            sb.append("JavaMethod{\n");

            for (JavaMethod method : this.overloadedMethods) {
                sb.append("  ");
                sb.append(method.j);
                sb.append("\n");
            }
            sb.append("}");
            return sb.toString();
        }
    }
}