package org.luaj.lib.jse;

import org.luaj.LuaString;
import org.luaj.LuaTable;
import org.luaj.LuaUserdata;
import org.luaj.LuaValue;
import org.luaj.Varargs;

import java.lang.reflect.Array;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

/**
 * Converts Lua values to Java values for the luajava bridge.
 *
 * Dynamic target classes are deliberately not retained in the process-wide
 * coercion cache: a coercion retains its target class and could otherwise keep
 * an unloaded project DexClassLoader alive indefinitely.
 */
public class CoerceLuaToJava {
    static int a = 16;
    static int b = 32;
    static int c = 128;
    static int d = 256;
    static int e = 65536;
    @SuppressWarnings("rawtypes")
    static final Map f = Collections.synchronizedMap(new HashMap<>());

    interface Coercion {
        Object coerce(LuaValue value);

        int score(LuaValue value);
    }

    static {
        Coercion bool = new BoolCoercion();
        Coercion byteValue = new NumericCoercion(NumericCoercion.BYTE);
        Coercion character = new NumericCoercion(NumericCoercion.CHAR);
        Coercion shortValue = new NumericCoercion(NumericCoercion.SHORT);
        Coercion integer = new NumericCoercion(NumericCoercion.INT);
        Coercion longValue = new NumericCoercion(NumericCoercion.LONG);
        Coercion floatValue = new NumericCoercion(NumericCoercion.FLOAT);
        Coercion doubleValue = new NumericCoercion(NumericCoercion.DOUBLE);
        Coercion string = new StringCoercion(StringCoercion.STRING);

        f.put(Boolean.TYPE, bool);
        f.put(Boolean.class, bool);
        f.put(Byte.TYPE, byteValue);
        f.put(Byte.class, byteValue);
        f.put(Character.TYPE, character);
        f.put(Character.class, character);
        f.put(Short.TYPE, shortValue);
        f.put(Short.class, shortValue);
        f.put(Integer.TYPE, integer);
        f.put(Integer.class, integer);
        f.put(Long.TYPE, longValue);
        f.put(Long.class, longValue);
        f.put(Float.TYPE, floatValue);
        f.put(Float.class, floatValue);
        f.put(Double.TYPE, doubleValue);
        f.put(Double.class, doubleValue);
        f.put(String.class, string);
    }

    public CoerceLuaToJava() {
    }

    static final int a(Class<?> baseClass, Class<?> subClass) {
        if (subClass == null) {
            return e;
        }
        if (baseClass == subClass) {
            return 0;
        }

        int minimum = Math.min(e, a(baseClass, subClass.getSuperclass()) + 1);
        for (Class<?> interfaceClass : subClass.getInterfaces()) {
            minimum = Math.min(minimum, a(baseClass, interfaceClass) + 1);
        }
        return minimum;
    }

    static Coercion a(Class<?> targetClass) {
        Coercion coercion = (Coercion) f.get(targetClass);
        if (coercion != null) {
            return coercion;
        }
        if (targetClass.isArray()) {
            coercion = new ArrayCoercion(targetClass.getComponentType());
        } else if (Map.class.isAssignableFrom(targetClass)) {
            coercion = new MapCoercion(targetClass);
        } else if (Collection.class.isAssignableFrom(targetClass)) {
            coercion = new CollectionCoercion(targetClass);
        } else {
            coercion = new ObjectCoercion(targetClass);
        }
        if (targetClass.getClassLoader() == null) {
            f.put(targetClass, coercion);
        }
        return coercion;
    }

    public static Object arrayCoerce(LuaValue value, Class<?> componentClass) {
        return new ArrayCoercion(componentClass).coerce(value);
    }

    public static Object coerce(LuaValue value, Class<?> targetClass) {
        return a(targetClass).coerce(value);
    }

    static final class BoolCoercion implements Coercion {
        @Override
        public Object coerce(LuaValue value) {
            return value.toboolean() ? Boolean.TRUE : Boolean.FALSE;
        }

        @Override
        public int score(LuaValue value) {
            if (value.isnil()) {
                return b;
            }
            return value.type() == LuaValue.TBOOLEAN ? 0 : e;
        }

        @Override
        public String toString() {
            return "BoolCoercion()";
        }
    }

    static final class NumericCoercion implements Coercion {
        static final int BYTE = 0;
        static final int CHAR = 1;
        static final int SHORT = 2;
        static final int INT = 3;
        static final int LONG = 4;
        static final int FLOAT = 5;
        static final int DOUBLE = 6;

        static final String[] a = {"byte", "char", "short", "int", "long", "float", "double"};
        final int b;

        NumericCoercion(int targetType) {
            b = targetType;
        }

        @Override
        public Object coerce(LuaValue value) {
            if (value.type() == LuaValue.TUSERDATA) {
                Number number = value.touserdata(Number.class);
                return switch (b) {
                    case BYTE -> number.byteValue();
                    case CHAR -> (char) number.intValue();
                    case SHORT -> number.shortValue();
                    case INT -> number.intValue();
                    case LONG -> number.longValue();
                    case FLOAT -> number.floatValue();
                    case DOUBLE -> number.doubleValue();
                    default -> null;
                };
            }

            return switch (b) {
                case BYTE -> (byte) value.toint();
                case CHAR -> (char) value.toint();
                case SHORT -> (short) value.toint();
                case INT -> value.toint();
                case LONG -> value.tolong();
                case FLOAT -> (float) value.todouble();
                case DOUBLE -> value.todouble();
                default -> null;
            };
        }

        @Override
        public int score(LuaValue value) {
            if (value.isnil()) {
                return CoerceLuaToJava.a;
            }

            int stringPenalty = 0;
            if (value.type() == LuaValue.TSTRING) {
                value = value.tonumber();
                if (value.isnil()) {
                    return e;
                }
                stringPenalty = 4;
            }

            if (value.isint()) {
                long number = value.tolong();
                switch (b) {
                    case BYTE:
                        return stringPenalty + (number == (byte) number ? 0 : d);
                    case CHAR:
                        return stringPenalty + (number == (byte) number ? 1 : number == (char) number ? 0 : d);
                    case SHORT:
                        return stringPenalty + (number == (byte) number ? 1 : number == (short) number ? 0 : d);
                    case INT:
                        return stringPenalty + (number == (byte) number ? 2 :
                            (number == (char) number || number == (short) number) ? 1 :
                                number == (int) number ? 0 : d);
                    case LONG:
                        if (number == (byte) number) {
                            return stringPenalty + 3;
                        }
                        if (number == (char) number || number == (short) number) {
                            return stringPenalty + 2;
                        }
                        // LuaJ++ gives a full-width integer its best score for long, so a value
                        // outside int range cannot tie an int overload after tointeger().
                        return stringPenalty + (number == (int) number ? 1 : 0);
                    case FLOAT:
                    case DOUBLE:
                        return stringPenalty + c;
                    default:
                        return d;
                }
            }

            if (value.type() == LuaValue.TNUMBER) {
                double number = value.todouble();
                return switch (b) {
                    case LONG -> number == (long) number ? stringPenalty + b : d;
                    case FLOAT -> number == (float) number ? stringPenalty : d;
                    case DOUBLE ->
                            stringPenalty + ((number == (long) number || number == (float) number) ? 1 : 0);
                    default -> d;
                };
            }

            if (value.type() == LuaValue.TUSERDATA) {
                Object userdata = value.touserdata();
                Class<?> expected = numericClass(b);
                return userdata != null && userdata.getClass() == expected ? 0 : e;
            }
            return e;
        }

        private static Class<?> numericClass(int targetType) {
            return switch (targetType) {
                case BYTE -> Byte.class;
                case CHAR -> Character.class;
                case SHORT -> Short.class;
                case INT -> Integer.class;
                case LONG -> Long.class;
                case FLOAT -> Float.class;
                case DOUBLE -> Double.class;
                default -> Object.class;
            };
        }

        @Override
        public String toString() {
            return "NumericCoercion(" + a[b] + ')';
        }
    }

    static final class StringCoercion implements Coercion {
        static final int STRING = 0;
        static final int BYTES = 1;

        final int a;

        StringCoercion(int targetType) {
            a = targetType;
        }

        @Override
        public Object coerce(LuaValue value) {
            if (value.isnil()) {
                return null;
            }
            if (a == STRING) {
                return value.tojstring();
            }
            LuaString string = value.checkstring();
            byte[] bytes = new byte[string.e];
            string.copyInto(0, bytes, 0, bytes.length);
            return bytes;
        }

        @Override
        public int score(LuaValue value) {
            if (value.isnil()) {
                return CoerceLuaToJava.a;
            }
            if (value.type() == LuaValue.TSTRING) {
                return a == STRING ? 0 : 1;
            }
            if (value.type() == LuaValue.TUSERDATA && value.touserdata() instanceof String) {
                return 0;
            }
            return e;
        }

        @Override
        public String toString() {
            return "StringCoercion(" + (a == STRING ? "String" : "byte[]") + ')';
        }
    }

    static final class ArrayCoercion implements Coercion {
        final Class<?> a;
        final Coercion b;

        public ArrayCoercion(Class<?> componentClass) {
            a = componentClass;
            b = CoerceLuaToJava.a(componentClass);
        }

        @Override
        public Object coerce(LuaValue value) {
            if (value.isnil()) {
                return null;
            }
            if (value.type() == LuaValue.TUSERDATA) {
                return value.touserdata();
            }
            if (value.type() != LuaValue.TTABLE) {
                return null;
            }

            int length = value.length();
            Object array = Array.newInstance(a, length);
            for (int index = 0; index < length; index++) {
                Array.set(array, index, b.coerce(value.get(index + 1)));
            }
            return array;
        }

        @Override
        public int score(LuaValue value) {
            if (value.isnil()) {
                return CoerceLuaToJava.a;
            }
            if (value.type() == LuaValue.TUSERDATA) {
                Object userdata = value.touserdata();
                return userdata != null && userdata.getClass().isArray()
                    ? CoerceLuaToJava.a(a, userdata.getClass().getComponentType())
                    : e;
            }
            if (value.type() != LuaValue.TTABLE) {
                return e;
            }
            int length = value.length();
            if (length == 0) {
                return 0;
            }
            int stride = length > 10 ? length / 10 : 1;
            int maximum = 0;
            for (int index = 1; index <= length; index += stride) {
                maximum = Math.max(maximum, b.score(value.get(index)));
                if (maximum == e) {
                    return e;
                }
            }
            return maximum;
        }

        @Override
        public String toString() {
            return "ArrayCoercion(" + a.getName() + ')';
        }
    }

    static final class CollectionCoercion implements Coercion {
        final Class<?> a;
        final Coercion b;

        public CollectionCoercion(Class<?> targetType) {
            a = targetType;
            b = new ObjectCoercion(targetType);
        }

        @Override
        @SuppressWarnings({"rawtypes", "unchecked"})
        public Object coerce(LuaValue value) {
            if (value.isnil()) {
                return null;
            }
            if (value.type() == LuaValue.TUSERDATA) {
                return value.touserdata();
            }
            if (value.type() != LuaValue.TTABLE) {
                return null;
            }
            try {
                Collection result = a.isInterface()
                    ? new ArrayList<>()
                    : (Collection) a.newInstance();
                for (int index = 1; index <= value.length(); index++) {
                    result.add(b.coerce(value.get(index)));
                }
                return result;
            } catch (InstantiationException | IllegalAccessException exception) {
                return value.touserdata();
            }
        }

        @Override
        public int score(LuaValue value) {
            return collectionScore(a, value);
        }

        @Override
        public String toString() {
            return "CollectionCoercion(" + a.getName() + ')';
        }
    }

    static final class MapCoercion implements Coercion {
        final Class<?> a;
        final Coercion b;

        public MapCoercion(Class<?> targetType) {
            a = targetType;
            b = new ObjectCoercion(targetType);
        }

        @Override
        @SuppressWarnings({"rawtypes", "unchecked"})
        public Object coerce(LuaValue value) {
            if (value.isnil()) {
                return null;
            }
            if (value.type() == LuaValue.TUSERDATA) {
                return value.touserdata();
            }
            if (value.type() != LuaValue.TTABLE) {
                return null;
            }
            try {
                Map result = a == Map.class ? new HashMap<>() : (Map) a.newInstance();
                LuaValue key = LuaValue.NIL;
                Varargs entry;
                while (!(entry = value.next(key)).isnil(1)) {
                    key = entry.arg1();
                    result.put(b.coerce(key), b.coerce(entry.arg(2)));
                }
                return result;
            } catch (InstantiationException | IllegalAccessException exception) {
                return value.touserdata();
            }
        }

        @Override
        public int score(LuaValue value) {
            return collectionScore(a, value);
        }

        @Override
        public String toString() {
            return "MapCoercion(" + a.getName() + ')';
        }
    }

    static final class InterFaceCoercion implements Coercion {
        final Class<?> a;
        final Coercion b;

        public InterFaceCoercion(Class<?> targetType) {
            a = targetType;
            b = new ObjectCoercion(targetType);
        }

        @Override
        public Object coerce(LuaValue value) {
            if (value.isnil()) {
                return null;
            }
            if (value.type() == LuaValue.TTABLE) {
                return LuajavaLib.createProxy(a, value).touserdata();
            }
            return value.type() == LuaValue.TUSERDATA ? value.touserdata() : null;
        }

        @Override
        public int score(LuaValue value) {
            if (value.isnil()) {
                return CoerceLuaToJava.a;
            }
            if (value.type() == LuaValue.TTABLE || value.type() == LuaValue.TFUNCTION) {
                return d;
            }
            return value.type() == LuaValue.TUSERDATA ? a(a, value.touserdata().getClass()) : e;
        }

        @Override
        public String toString() {
            return "InterFaceCoercion(" + a.getName() + ')';
        }
    }

    static final class ObjectCoercion implements Coercion {
        final Class<?> a;

        ObjectCoercion(Class<?> targetType) {
            a = targetType;
        }

        @Override
        public Object coerce(LuaValue value) {
            if (LuaValue.class.isAssignableFrom(a)) {
                return value;
            }
            return switch (value.type()) {
                case LuaValue.TNIL -> null;
                case LuaValue.TUSERDATA -> value.optuserdata(a, null);
                case LuaValue.TSTRING -> value.tojstring();
                case LuaValue.TNUMBER ->
                        value.isint() ? Long.valueOf(value.tolong()) : Double.valueOf(value.todouble());
                case LuaValue.TBOOLEAN -> value.toboolean() ? Boolean.TRUE : Boolean.FALSE;
                case LuaValue.TTABLE, LuaValue.TFUNCTION -> {
                    if (a.isInterface()) {
                        LuaUserdata proxy = LuajavaLib.createProxy(a, value);
                        yield proxy.touserdata();
                    }
                    yield value;
                }
                default -> value;
            };
        }

        @Override
        public int score(LuaValue value) {
            if (LuaValue.class.isAssignableFrom(a)) {
                return CoerceLuaToJava.a(a, value.getClass());
            }
            return switch (value.type()) {
                case LuaValue.TNIL -> CoerceLuaToJava.a;
                case LuaValue.TUSERDATA -> {
                    Object userdata = value.touserdata();
                    yield userdata == null ? e : CoerceLuaToJava.a(a, userdata.getClass());
                }
                case LuaValue.TNUMBER ->
                        CoerceLuaToJava.a(a, value.isint() ? Integer.class : Double.class);
                case LuaValue.TBOOLEAN -> CoerceLuaToJava.a(a, Boolean.class);
                case LuaValue.TSTRING -> CoerceLuaToJava.a(a, String.class);
                case LuaValue.TTABLE -> a.isInterface() ? d : CoerceLuaToJava.a(a, LuaTable.class);
                case LuaValue.TFUNCTION ->
                        a.isInterface() ? d : CoerceLuaToJava.a(a, org.luaj.LuaFunction.class);
                default -> CoerceLuaToJava.a(a, value.getClass());
            };
        }

        @Override
        public String toString() {
            return "ObjectCoercion(" + a.getName() + ')';
        }
    }

    private static int collectionScore(Class<?> targetType, LuaValue value) {
        if (value.isnil()) {
            return a;
        }
        if (value.type() == LuaValue.TTABLE) {
            return 10;
        }
        if (value.type() == LuaValue.TUSERDATA) {
            Object userdata = value.touserdata();
            return userdata == null ? e : a(targetType, userdata.getClass());
        }
        return e;
    }
}
