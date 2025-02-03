//
// Source code recreated from a .class file by IntelliJ IDEA
// (powered by FernFlower decompiler)
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

class JavaConstructor extends JavaMember {
    static final Map<Object, Object> h = Collections.synchronizedMap(new HashMap<>());
    final Constructor i;

    private JavaConstructor(Constructor var1) {
        super(var1.getParameterTypes(), var1.getModifiers());
        this.i = var1;
    }

    static JavaConstructor a(Constructor var0) {
        JavaConstructor var2 = (JavaConstructor)h.get(var0);
        JavaConstructor var1 = var2;
        if (var2 == null) {
            var1 = new JavaConstructor(var0);
            h.put(var0, var1);
        }

        return var1;
    }

    public static LuaValue forConstructors(JavaConstructor[] var0) {
        return new Overload(var0);
    }

    public Varargs invoke(Varargs var1) {
        if (super.e == null && super.d.length != var1.narg()) {
            throw new IllegalArgumentException(this.i.toString());
        } else {
            Object[] var5 = this.a(var1);

            try {
                return new JavaInstance(this.i.newInstance(var5));
            } catch (InvocationTargetException e) {
                throw new LuaError(this.i +
                        " " +
                        e.getTargetException());
            } catch (Exception var4) {
                String var2 = "coercion error " +
                        this.i +
                        " " +
                        var4;
                LuaValue.error(var2);
                throw null;
            }
        }
    }

    public String tojstring() {
        return "JavaConstructor{\n  " +
                this.i +
                "\n}";
    }

    static class Overload extends VarArgFunction {
        final JavaConstructor[] d;

        public Overload(JavaConstructor[] var1) {
            this.d = var1;
        }

        public Varargs invoke(Varargs args) {
            int minCost = CoerceLuaToJava.e; // 初始最小匹配开销
            JavaConstructor bestConstructor = null; // 最优匹配的构造函数

            for (JavaConstructor javaConstructor : this.d) {
                int cost = javaConstructor.b(args); // 计算当前构造函数的匹配开销

                if (cost < minCost) {
                    bestConstructor = javaConstructor;
                    minCost = cost;

                    // 如果完全匹配，提前退出
                    if (cost == 0) {
                        break;
                    }
                }
            }

            if (bestConstructor != null) {
                return bestConstructor.invoke(args); // 调用最佳匹配的构造函数
            } else {
                // 抛出错误信息并包含当前对象的详细信息
                LuaValue.error("No coercible public constructor found for arguments: " + args + "\n" + this);
                return null; // 永远不会被执行
            }
        }

        public String tojstring() {
            StringBuilder var3 = new StringBuilder();
            var3.append("JavaConstructor{\n");

            for(JavaConstructor var5 : this.d) {
                var3.append("  ");
                var3.append(var5.i);
                var3.append("\n");
            }

            var3.append("}");
            return var3.toString();
        }
    }
}
