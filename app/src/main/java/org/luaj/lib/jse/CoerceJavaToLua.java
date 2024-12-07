//
// Source code recreated from a .class file by IntelliJ IDEA
// (powered by FernFlower decompiler)
//

package org.luaj.lib.jse;

import org.luaj.LuaBoolean;
import org.luaj.LuaDouble;
import org.luaj.LuaInteger;
import org.luaj.LuaString;
import org.luaj.LuaValue;

import java.util.HashMap;
import java.util.Map;

public class CoerceJavaToLua {
    private static final Map<Class<?>, Coercion> a = new HashMap<>();
    static final Coercion b;
    static final Coercion c;
    static final Coercion d;

    static {
        BoolCoercion var4 = new BoolCoercion();
        IntCoercion var0 = new IntCoercion();
        LongCoercion var6 = new LongCoercion();
        CharCoercion var1 = new CharCoercion();
        DoubleCoercion var2 = new DoubleCoercion();
        StringCoercion var3 = new StringCoercion();
        //new BytesCoercion();
        ClassCoercion var5 = new ClassCoercion();
        a.put(Boolean.class, var4);
        a.put(Byte.class, var0);
        a.put(Character.class, var1);
        a.put(Short.class, var0);
        a.put(Integer.class, var0);
        a.put(Long.class, var6);
        a.put(Float.class, var2);
        a.put(Double.class, var2);
        a.put(String.class, var3);
        a.put(Class.class, var5);
        b = new InstanceCoercion();
        c = new ArrayCoercion();
        d = new LuaCoercion();
    }

    public CoerceJavaToLua() {
    }

    public static LuaValue coerce(Boolean var0) {
        LuaValue var1;
        if (var0 == null) {
            var1 = LuaValue.NIL;
        } else {
            var1 = LuaValue.valueOf(var0);
        }
        return var1;
    }

    public static LuaValue coerce(Byte var0) {
        LuaValue var1;
        if (var0 == null) {
            var1 = LuaValue.NIL;
        } else {
            var1 = LuaInteger.valueOf(var0);
        }

        return var1;
    }

    public static LuaValue coerce(Character var0) {
        LuaValue var1;
        if (var0 == null) {
            var1 = LuaValue.NIL;
        } else {
            var1 = LuaInteger.valueOf(var0);
        }

        return var1;
    }

    public static LuaValue coerce(Integer var0) {
        LuaValue var1;
        if (var0 == null) {
            var1 = LuaValue.NIL;
        } else {
            var1 = LuaInteger.valueOf(var0);
        }

        return var1;
    }

    public static LuaValue coerce(Long var0) {
        LuaValue var1;
        if (var0 == null) {
            var1 = LuaValue.NIL;
        } else {
            var1 = LuaInteger.valueOf(var0);
        }

        return var1;
    }

    public static LuaValue coerce(Object var0) {
        LuaValue var4;
        if (var0 == null) {
            var4 = LuaValue.NIL;
        } else {
            Class<?> var3 = var0.getClass();
            Coercion var2 = a.get(var3);
            Coercion var1 = var2;
            if (var2 == null) {
                if (var3.isArray()) {
                    var1 = c;
                } else if (var0 instanceof LuaValue) {
                    var1 = d;
                } else {
                    var1 = b;
                }

                a.put(var3, var1);
            }

            var4 = var1.coerce(var0);
        }

        return var4;
    }

    public static LuaValue coerce(Short var0) {
        LuaValue var1;
        if (var0 == null) {
            var1 = LuaValue.NIL;
        } else {
            var1 = LuaInteger.valueOf(var0);
        }

        return var1;
    }

    private static final class ArrayCoercion implements Coercion {
        private ArrayCoercion() {
        }

        public LuaValue coerce(Object var1) {
            return new JavaArray(var1);
        }
    }

    private static final class BoolCoercion implements Coercion {
        private BoolCoercion() {
        }

        public LuaValue coerce(Object var1) {
            LuaBoolean var2;
            if ((Boolean) var1) {
                var2 = LuaValue.TRUE;
            } else {
                var2 = LuaValue.FALSE;
            }

            return var2;
        }
    }

//    private static final class BytesCoercion implements Coercion {
//        private BytesCoercion() {
//        }
//
//        public LuaValue coerce(Object var1) {
//            return LuaValue.valueOf((byte[])var1);
//        }
//    }

    private static final class CharCoercion implements Coercion {
        private CharCoercion() {
        }

        public LuaValue coerce(Object var1) {
            return LuaInteger.valueOf((Character) var1);
        }
    }

    private static final class ClassCoercion implements Coercion {
        private ClassCoercion() {
        }

        public LuaValue coerce(Object var1) {
            return JavaClass.a((Class<?>) var1);
        }
    }

    interface Coercion {
        LuaValue coerce(Object var1);
    }

    private static final class DoubleCoercion implements Coercion {
        private DoubleCoercion() {
        }

        public LuaValue coerce(Object var1) {
            return LuaDouble.valueOf(((Number) var1).doubleValue());
        }
    }

    private static final class InstanceCoercion implements Coercion {
        private InstanceCoercion() {
        }

        public LuaValue coerce(Object var1) {
            return new JavaInstance(var1);
        }
    }

    private static final class IntCoercion implements Coercion {
        private IntCoercion() {
        }

        public LuaValue coerce(Object var1) {
            return LuaInteger.valueOf(((Number) var1).intValue());
        }
    }

    private static final class LongCoercion implements Coercion {
        private LongCoercion() {
        }

        public LuaValue coerce(Object var1) {
            return LuaInteger.valueOf(((Number) var1).longValue());
        }
    }

    private static final class LuaCoercion implements Coercion {
        private LuaCoercion() {
        }

        public LuaValue coerce(Object var1) {
            return (LuaValue) var1;
        }
    }

    private static final class StringCoercion implements Coercion {
        private StringCoercion() {
        }

        public LuaValue coerce(Object var1) {
            return LuaString.valueOf(var1.toString());
        }
    }
}
