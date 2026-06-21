//
// Source code recreated from a .class file by IntelliJ IDEA
// (powered by FernFlower decompiler)
// Optimized with improved variable naming, comments, and performance
//

package org.luaj.lib.jse;

import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationTargetException;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import org.luaj.LuaError;
import org.luaj.LuaValue;
import org.luaj.Varargs;
import org.luaj.lib.VarArgFunction;

/**
 * 表示Java构造函数的Lua值。
 * 支持单个构造函数和重载构造函数的调用。
 */
class JavaConstructor extends JavaMember {
    // 构造函数缓存：Constructor -> JavaConstructor（保持原有字段名以保证兼容性）
    static final Map<Constructor<?>, JavaConstructor> h = Collections.synchronizedMap(new HashMap<>());
    
    // 原始Constructor对象
    final Constructor i;

    /**
     * 私有构造函数
     * @param constructor 要包装的Constructor对象
     */
    private JavaConstructor(Constructor constructor) {
        super(constructor.getParameterTypes(), constructor.getModifiers());
        this.i = constructor;
    }

    /**
     * 获取或创建JavaConstructor实例（使用缓存）
     * @param constructor 原始Constructor对象
     * @return 对应的JavaConstructor实例
     */
    static JavaConstructor a(Constructor<?> constructor) {
        return h.computeIfAbsent(constructor, JavaConstructor::new);
    }

    /**
     * 创建重载构造函数包装器
     * @param constructors 重载的构造函数数组
     * @return 包装后的LuaValue
     */
    public static LuaValue forConstructors(JavaConstructor[] constructors) {
        return new Overload(constructors);
    }

    /**
     * 执行构造函数调用
     * @param args 参数列表
     * @return 新创建的JavaInstance
     */
    public Varargs invoke(Varargs args) {
        // 检查参数数量（如果不是可变参数构造函数）
        if (super.e == null && super.d.length != args.narg()) {
            throw new IllegalArgumentException(buildArityError(args));
        }

        Object[] javaArgs = this.a(args);

        try {
            // 调用构造函数创建实例
            return new JavaInstance(this.i.newInstance(javaArgs));
        } catch (InvocationTargetException e) {
            // 构造函数内部抛出的异常
            throw new LuaError(buildInvocationError(args, e.getTargetException()));
        } catch (Exception e) {
            // 其他异常（参数类型不匹配等）
            throw new LuaError(buildCoercionError(args, e));
        }
    }

    /**
     * 构建参数数量错误信息
     */
    private String buildArityError(Varargs args) {
        return "constructor argument count mismatch for '" + this.i.getDeclaringClass().getSimpleName() + "'\n" +
            "Constructor: " + describeConstructor(this.i) + "\n" +
            "Expected: " + this.i.getParameterTypes().length + " arguments\n" +
            "Got: " + args.narg() + " arguments\n" +
            "Arguments: " + describeArgs(args);
    }

    /**
     * 构建调用错误信息
     */
    private String buildInvocationError(Varargs args, Throwable cause) {
        return "exception in constructor for '" + this.i.getDeclaringClass().getSimpleName() + "'\n" +
            "Constructor: " + describeConstructor(this.i) + "\n" +
            "Arguments: " + describeArgs(args) + "\n" +
            "Cause: " + cause.getClass().getSimpleName() + ": " + cause.getMessage();
    }

    /**
     * 构建参数转换错误信息
     */
    private String buildCoercionError(Varargs args, Exception exception) {
        return "failed to create instance of '" + this.i.getDeclaringClass().getSimpleName() + "'\n" +
            "Constructor: " + describeConstructor(this.i) + "\n" +
            "Arguments: " + describeArgs(args) + "\n" +
            "Error: " + exception.getClass().getSimpleName() + ": " + exception.getMessage();
    }

    /**
     * 描述构造函数的签名
     * @param constructor 构造函数对象
     * @return 格式化的构造函数描述
     */
    private static String describeConstructor(Constructor<?> constructor) {
        StringBuilder sb = new StringBuilder();
        sb.append(constructor.getDeclaringClass().getName());
        sb.append('(');
        Class<?>[] parameterTypes = constructor.getParameterTypes();
        for (int i = 0; i < parameterTypes.length; i++) {
            if (i > 0) {
                sb.append(", ");
            }
            sb.append(parameterTypes[i].getTypeName());
        }
        sb.append(')');
        return sb.toString();
    }

    /**
     * 描述参数列表
     * @param args 参数列表
     * @return 格式化的参数描述
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
     * 返回构造函数的字符串表示
     */
    public String tojstring() {
        return "JavaConstructor{\n  " + this.i + "\n}";
    }

    /**
     * 表示重载构造函数的包装器
     * 根据参数类型自动选择最佳匹配的构造函数
     */
    static class Overload extends VarArgFunction {
        // 重载的构造函数数组（保持原有字段名以保证兼容性）
        final JavaConstructor[] d;

        /**
         * 构造函数
         * @param constructors 重载的构造函数数组
         */
        public Overload(JavaConstructor[] constructors) {
            this.d = constructors;
        }

        /**
         * 执行重载构造函数调用，自动选择最佳匹配的构造函数
         * @param args 参数列表
         * @return 新创建的JavaInstance
         */
        public Varargs invoke(Varargs args) {
            int minCost = CoerceLuaToJava.e;  // 初始匹配分数（最差）
            JavaConstructor bestConstructor = null;  // 最佳匹配构造函数

            // 遍历所有重载构造函数，找到最佳匹配
            for (JavaConstructor constructor : this.d) {
                int cost = constructor.b(args);  // 计算匹配分数

                // 如果当前构造函数匹配更好，更新最佳构造函数
                if (cost < minCost) {
                    bestConstructor = constructor;
                    minCost = cost;

                    // 如果完全匹配，提前退出
                    if (cost == 0) {
                        break;
                    }
                }
            }

            // 调用最佳匹配构造函数
            if (bestConstructor != null) {
                return bestConstructor.invoke(args);
            }

            // 没有找到匹配构造函数，抛出详细的错误信息
            throw new LuaError(buildNoMatchingConstructorError(args));
        }

        /**
         * 构建无匹配构造函数的错误信息
         */
        private String buildNoMatchingConstructorError(Varargs args) {
            StringBuilder sb = new StringBuilder();
            sb.append("no matching overload found for constructor of '");
            sb.append(this.d[0].i.getDeclaringClass().getSimpleName());
            sb.append("'\n\n");
            
            sb.append("Arguments provided: ");
            sb.append(describeArgs(args));
            sb.append("\n\n");
            
            sb.append("Available constructors:\n");
            for (JavaConstructor constructor : this.d) {
                sb.append("  - ");
                sb.append(constructor.i);
                sb.append("\n");
            }
            
            sb.append("\nHint: Check that argument types match the constructor signatures.");
            return sb.toString();
        }

        /**
         * 返回所有重载构造函数的字符串表示
         */
        public String tojstring() {
            StringBuilder sb = new StringBuilder();
            sb.append("JavaConstructor{\n");

            for (JavaConstructor constructor : this.d) {
                sb.append("  ");
                sb.append(constructor.i);
                sb.append("\n");
            }

            sb.append("}");
            return sb.toString();
        }
    }
}