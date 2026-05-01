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
    static final Map<Constructor<?>, JavaConstructor> h = Collections.synchronizedMap(new HashMap<>());
    final Constructor i;

    private JavaConstructor(Constructor var1) {
        super(var1.getParameterTypes(), var1.getModifiers());
        this.i = var1;
    }

    static JavaConstructor a(Constructor<?> var0) {
        return h.computeIfAbsent(var0, JavaConstructor::new);
    }

    public static LuaValue forConstructors(JavaConstructor[] var0) {
        return new Overload(var0);
    }

    public Varargs invoke(Varargs var1) {
        if (super.e == null && super.d.length != var1.narg()) {
            throw new IllegalArgumentException(buildArityError(var1));
        }

        Object[] var5 = this.a(var1);

        try {
            return new JavaInstance(this.i.newInstance(var5));
        } catch (InvocationTargetException e) {
            throw new LuaError(buildInvocationError(var1, e.getTargetException()));
        } catch (Exception var4) {
            throw new LuaError(buildCoercionError(var1, var4));
        }
    }

    private String buildArityError(Varargs args) {
        return "no matching constructor: " + describeConstructor(this.i) +
                " expected " + this.i.getParameterTypes().length +
                " args, got " + args.narg() +
                " -> " + describeArgs(args);
    }

    private String buildInvocationError(Varargs args, Throwable cause) {
        return "constructor failed: " + describeConstructor(this.i) +
                " with args " + describeArgs(args) +
                " -> " + cause;
    }

    private String buildCoercionError(Varargs args, Exception exception) {
        return "coercion error for constructor: " + describeConstructor(this.i) +
                " with args " + describeArgs(args) +
                " -> " + exception;
    }

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
            int minCost = CoerceLuaToJava.e;
            JavaConstructor bestConstructor = null;

            for (JavaConstructor javaConstructor : this.d) {
                int cost = javaConstructor.b(args);

                if (cost < minCost) {
                    bestConstructor = javaConstructor;
                    minCost = cost;

                    if (cost == 0) {
                        break;
                    }
                }
            }

            if (bestConstructor != null) {
                return bestConstructor.invoke(args);
            }

            throw new LuaError("no coercible public constructor found for arguments: " + describeArgs(args) + "\navailable constructors:\n" + this);
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
