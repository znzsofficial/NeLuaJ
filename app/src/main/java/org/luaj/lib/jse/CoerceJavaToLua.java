//
// Source code recreated from a .class file by IntelliJ IDEA
// (powered by FernFlower decompiler)
// Optimized with improved variable naming, comments, and performance
//

package org.luaj.lib.jse;

import org.luaj.LuaBoolean;
import org.luaj.LuaDouble;
import org.luaj.LuaInteger;
import org.luaj.LuaString;
import org.luaj.LuaValue;

import java.util.concurrent.ConcurrentHashMap;
import java.util.Map;

/**
 * 将Java对象转换为Lua值的工具类。
 * 使用策略模式和缓存机制来优化转换性能。
 */
public class CoerceJavaToLua {
    // 使用ConcurrentHashMap保证线程安全的缓存
    private static final Map<Class<?>, Coercion> coercionCache = new ConcurrentHashMap<>();
    
    // 预定义的常用 coercion 策略（保持原有字段名以保证兼容性）
    static final Coercion b; // InstanceCoercion - 通用对象实例转换
    static final Coercion c; // ArrayCoercion - 数组转换
    static final Coercion d; // LuaCoercion - LuaValue直接返回

    static {
        // 初始化各种类型的 coercion 策略
        BoolCoercion boolCoercion = new BoolCoercion();
        IntCoercion intCoercion = new IntCoercion();
        LongCoercion longCoercion = new LongCoercion();
        CharCoercion charCoercion = new CharCoercion();
        DoubleCoercion doubleCoercion = new DoubleCoercion();
        StringCoercion stringCoercion = new StringCoercion();
        ClassCoercion classCoercion = new ClassCoercion();
        
        // 注册常用类型的 coercion 策略
        coercionCache.put(Boolean.class, boolCoercion);
        coercionCache.put(Byte.class, intCoercion);
        coercionCache.put(Character.class, charCoercion);
        coercionCache.put(Short.class, intCoercion);
        coercionCache.put(Integer.class, intCoercion);
        coercionCache.put(Long.class, longCoercion);
        coercionCache.put(Float.class, doubleCoercion);
        coercionCache.put(Double.class, doubleCoercion);
        coercionCache.put(String.class, stringCoercion);
        coercionCache.put(Class.class, classCoercion);
        
        // 初始化通用 coercion 策略
        b = new InstanceCoercion();
        c = new ArrayCoercion();
        d = new LuaCoercion();
    }

    public CoerceJavaToLua() {
    }

    /**
     * 将Boolean转换为Lua值
     * @param value Java Boolean值
     * @return 对应的Lua值
     */
    public static LuaValue coerce(Boolean value) {
        return value == null ? LuaValue.NIL : LuaValue.valueOf(value);
    }

    /**
     * 将Byte转换为Lua值
     * @param value Java Byte值
     * @return 对应的Lua值
     */
    public static LuaValue coerce(Byte value) {
        return value == null ? LuaValue.NIL : LuaInteger.valueOf(value);
    }

    /**
     * 将Character转换为Lua值
     * @param value Java Character值
     * @return 对应的Lua值
     */
    public static LuaValue coerce(Character value) {
        return value == null ? LuaValue.NIL : LuaInteger.valueOf(value);
    }

    /**
     * 将Integer转换为Lua值
     * @param value Java Integer值
     * @return 对应的Lua值
     */
    public static LuaValue coerce(Integer value) {
        return value == null ? LuaValue.NIL : LuaInteger.valueOf(value);
    }

    /**
     * 将Long转换为Lua值
     * @param value Java Long值
     * @return 对应的Lua值
     */
    public static LuaValue coerce(Long value) {
        return value == null ? LuaValue.NIL : LuaInteger.valueOf(value);
    }

    /**
     * 将Short转换为Lua值
     * @param shortValue Java Short值
     * @return 对应的Lua值
     */
    public static LuaValue coerce(Short shortValue) {
        return shortValue == null ? LuaValue.NIL : LuaInteger.valueOf(shortValue);
    }

    /**
     * 将任意Java对象转换为Lua值。
     * 使用缓存机制优化性能，避免重复查找coercion策略。
     * 
     * @param inputObject 要转换的Java对象
     * @return 对应的Lua值
     */
    public static LuaValue coerce(Object inputObject) {
        if (inputObject == null) {
            return LuaValue.NIL;
        }

        Class<?> inputClass = inputObject.getClass();
        
        // 从缓存中获取coercion策略
        Coercion coercion = coercionCache.get(inputClass);

        if (coercion == null) {
            // 根据类型选择合适的coercion策略
            if (inputClass.isArray()) {
                coercion = c; // 数组类型
            } else if (inputObject instanceof LuaValue) {
                coercion = d; // 已经是LuaValue
            } else {
                coercion = b; // 通用对象实例
            }
            // 缓存结果以供后续使用
            coercionCache.put(inputClass, coercion);
        }

        return coercion.coerce(inputObject);
    }

    /**
     * 数组类型的coercion策略
     */
    private static final class ArrayCoercion implements Coercion {
        private ArrayCoercion() {
        }

        public LuaValue coerce(Object var1) {
            return new JavaArray(var1);
        }
    }

    /**
     * Boolean类型的coercion策略
     */
    private static final class BoolCoercion implements Coercion {
        private BoolCoercion() {
        }

        public LuaValue coerce(Object var1) {
            // 直接返回预定义的TRUE/FALSE常量，避免创建新对象
            return (Boolean) var1 ? LuaValue.TRUE : LuaValue.FALSE;
        }
    }

    /**
     * Character类型的coercion策略
     */
    private static final class CharCoercion implements Coercion {
        private CharCoercion() {
        }

        public LuaValue coerce(Object var1) {
            return LuaInteger.valueOf((Character) var1);
        }
    }

    /**
     * Class类型的coercion策略
     */
    private static final class ClassCoercion implements Coercion {
        private ClassCoercion() {
        }

        public LuaValue coerce(Object var1) {
            return JavaClass.a((Class<?>) var1);
        }
    }

    /**
     * coercion策略接口
     */
    interface Coercion {
        /**
         * 将Java对象转换为Lua值
         * @param var1 要转换的Java对象
         * @return 对应的Lua值
         */
        LuaValue coerce(Object var1);
    }

    /**
     * Double/Float类型的coercion策略
     */
    private static final class DoubleCoercion implements Coercion {
        private DoubleCoercion() {
        }

        public LuaValue coerce(Object var1) {
            return LuaDouble.valueOf(((Number) var1).doubleValue());
        }
    }

    /**
     * 通用对象实例的coercion策略
     */
    private static final class InstanceCoercion implements Coercion {
        private InstanceCoercion() {
        }

        public LuaValue coerce(Object var1) {
            return new JavaInstance(var1);
        }
    }

    /**
     * Integer/Byte/Short类型的coercion策略
     */
    private static final class IntCoercion implements Coercion {
        private IntCoercion() {
        }

        public LuaValue coerce(Object var1) {
            return LuaInteger.valueOf(((Number) var1).intValue());
        }
    }

    /**
     * Long类型的coercion策略
     */
    private static final class LongCoercion implements Coercion {
        private LongCoercion() {
        }

        public LuaValue coerce(Object var1) {
            return LuaInteger.valueOf(((Number) var1).longValue());
        }
    }

    /**
     * LuaValue类型的coercion策略（直接返回）
     */
    private static final class LuaCoercion implements Coercion {
        private LuaCoercion() {
        }

        public LuaValue coerce(Object var1) {
            return (LuaValue) var1;
        }
    }

    /**
     * String类型的coercion策略
     */
    private static final class StringCoercion implements Coercion {
        private StringCoercion() {
        }

        public LuaValue coerce(Object var1) {
            return LuaString.valueOf(var1.toString());
        }
    }
}