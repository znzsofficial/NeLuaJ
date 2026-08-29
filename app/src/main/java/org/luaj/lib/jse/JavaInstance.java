package org.luaj.lib.jse;

import org.luaj.LuaError;
import org.luaj.LuaMetaTable;
import org.luaj.LuaTable;
import org.luaj.LuaUserdata;
import org.luaj.LuaValue;
import org.luaj.Varargs;

import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.util.Collection;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

/**
 * Lua userdata wrapper for Java objects, fields, bean properties, and collections.
 */
public class JavaInstance extends LuaUserdata {
    private static final int GET_FIELD = 1;
    private static final int METHOD = 2;
    private static final int INNER_CLASS = 3;
    private static final int GETTER = 4;
    private static final int GET_VALUE = 5;
    private static final int SET_FIELD = 6;
    private static final int SETTER = 7;
    private static final int SET_VALUE = 8;
    private static final int SET_LISTENER = 9;

    static final LuaValue e = LuaValue.valueOf("class");

    JavaClass f;
    // JavaClass inherits this storage for class-level Lua-assigned values.
    protected HashMap<LuaValue, LuaValue> g;
    private HashMap<LuaValue, LuaValue> h;

    public JavaInstance(Object instance) {
        super(instance);
    }

    @Override
    public LuaValue call(LuaValue arg) {
        if (arg.istable()) {
            applyTable(arg);
            return this;
        }
        return super.call(arg);
    }

    @Override
    public LuaValue get(LuaValue key) {
        ensureJavaClass();
        LuaValue cached = f.p.get(key);
        if (cached != null) {
            return cached;
        }

        int type = getType(f.m, key);
        LuaValue value = getField(key, type, f.m);
        if (value != null) {
            return value;
        }
        value = getMethod(key, type, f.m);
        if (value != null) {
            return value;
        }
        value = getInnerClass(key, type, f.m);
        if (value != null) {
            return value;
        }
        value = getGetter(key, type, f.m);
        if (value != null) {
            return value;
        }
        value = getCollectionValue(key, type, f.m);
        if (value != null) {
            return value;
        }
        value = getAssignedValue(key);
        if (value != null) {
            return value;
        }
        if (key.eq_b(e)) {
            f.p.put(key, f);
            return f;
        }
        return super.get(key);
    }

    public LuaValue getJavaMethod(String key) {
        return getJavaMethod(LuaValue.valueOf(key));
    }

    @Override
    public LuaValue getJavaMethod(LuaValue key) {
        ensureJavaClass();
        LuaValue cached = f.p.get(key);
        if (cached != null) {
            return cached;
        }

        int type = getType(f.n, key);
        LuaValue value = getMethod(key, type, f.n);
        if (value != null) {
            return value;
        }
        value = getInnerClass(key, type, f.n);
        if (value != null) {
            return value;
        }
        value = getGetter(key, type, f.n);
        if (value != null) {
            return value;
        }
        value = getField(key, type, f.n);
        if (value != null) {
            return value;
        }
        value = getCollectionValue(key, type, f.n);
        if (value != null) {
            return value;
        }
        value = getAssignedValue(key);
        if (value != null) {
            return value;
        }
        if (key.eq_b(e)) {
            f.p.put(key, f);
            return f;
        }
        return super.get(key);
    }

    @Override
    public LuaValue getmetatable() {
        if (c != null) {
            return c;
        }
        ensureJavaClass();
        return f.c != null ? f.c : super.getmetatable();
    }

    @Override
    public Varargs invoke(Varargs args) {
        if (args.narg() == 1 && args.arg1().istable()) {
            applyTable(args.arg1());
            return this;
        }
        return super.invoke(args);
    }

    @Override
    public Object invokeJavaMethod(String key, Object... args) {
        return getJavaMethod(key).jcall(args);
    }

    @Override
    public LuaValue invokeJavaMethod(String key, Varargs args) {
        return getJavaMethod(key).invokeJavaMethod(this, args);
    }

    @Override
    public LuaValue len() {
        if (b instanceof Map) {
            return CoerceJavaToLua.coerce(((Map<?, ?>) b).size());
        }
        if (b instanceof Collection) {
            return CoerceJavaToLua.coerce(((Collection<?>) b).size());
        }
        return super.len();
    }

    @Override
    public LuaValue metatag(LuaValue tag) {
        LuaValue metatable = getmetatable();
        if (metatable != null) {
            return metatable.rawget(tag);
        }
        LuaValue value = getAssignedValue(tag);
        return value != null ? value : NIL;
    }

    @Override
    public Varargs next(LuaValue index) {
        if (b instanceof Map) {
            return nextMap((Map<?, ?>) b, index);
        }
        if (b instanceof List<?> list) {
            int nextIndex = index.isnil() ? 0 : index.toint() + 1;
            return nextIndex < list.size()
                ? LuaValue.varargsOf(
                    CoerceJavaToLua.coerce(nextIndex),
                    CoerceJavaToLua.coerce(list.get(nextIndex)),
                    LuaValue.NONE
                )
                : NIL;
        }
        if (b instanceof Collection<?> collection) {
            int nextIndex = index.isnil() ? 0 : index.toint() + 1;
            if (nextIndex >= collection.size()) {
                return NIL;
            }

            Iterator<?> iterator = collection.iterator();
            for (int currentIndex = 0; currentIndex < nextIndex; currentIndex++) {
                iterator.next();
            }
            return LuaValue.varargsOf(
                CoerceJavaToLua.coerce(nextIndex),
                CoerceJavaToLua.coerce(iterator.next()),
                LuaValue.NONE
            );
        }
        return super.next(index);
    }

    @Override
    public void set(LuaValue key, LuaValue value) {
        ensureJavaClass();
        int type = getType(f.o, key);

        if ((type == 0 || type == SET_FIELD) && setField(key, value, type)) {
            return;
        }
        if ((type == 0 || type == SETTER) && setSetter(key, value, type)) {
            return;
        }
        if ((type == 0 || type == SET_LISTENER) && setListener(key, value, type)) {
            return;
        }
        if ((type == 0 || type == SET_VALUE) && setCollectionValue(key, value, type)) {
            return;
        }
        setAssignedValue(key, value);
    }

    private void applyTable(LuaValue table) {
        LuaValue key = NIL;
        Varargs next;
        while (!(next = table.next(key)).isnil(1)) {
            key = next.arg1();
            set(key, next.arg(2));
        }
    }

    private void ensureJavaClass() {
        if (f == null) {
            f = JavaClass.a(b.getClass());
        }
    }

    private LuaValue getField(LuaValue key, int type, HashMap<LuaValue, Integer> typeCache) {
        if (type != 0 && type != GET_FIELD) {
            return null;
        }
        Field field = f.b(key);
        if (field == null) {
            return null;
        }
        if (type == 0) {
            typeCache.put(key, GET_FIELD);
        }
        try {
            LuaValue value = CoerceJavaToLua.coerce(field.get(b));
            // JavaClass is shared by every instance, so only class-level constants are safe here.
            if (Modifier.isStatic(field.getModifiers()) && Modifier.isFinal(field.getModifiers())) {
                f.p.put(key, value);
            }
            return value;
        } catch (Exception exception) {
            throw new LuaError(exception);
        }
    }

    private LuaValue getMethod(LuaValue key, int type, HashMap<LuaValue, Integer> typeCache) {
        if (type != 0 && type != METHOD) {
            return null;
        }
        LuaValue value = h != null ? h.get(key) : null;
        if (value != null) {
            return value;
        }
        LuaValue method = f.getMethod(key);
        if (method == null) {
            return null;
        }
        if (type == 0) {
            typeCache.put(key, METHOD);
        }
        value = new JavaMethod.JavaOOMethod(this, method);
        if (h == null) {
            h = new HashMap<>();
        }
        h.put(key, value);
        return value;
    }

    private LuaValue getInnerClass(LuaValue key, int type, HashMap<LuaValue, Integer> typeCache) {
        if (type != 0 && type != INNER_CLASS || !(b instanceof Class)) {
            return null;
        }
        JavaClass innerClass = f.c(key);
        if (innerClass == null) {
            return null;
        }
        if (type == 0) {
            typeCache.put(key, INNER_CLASS);
        }
        if (Modifier.isStatic(((Class<?>) innerClass.b).getModifiers())) {
            f.p.put(key, innerClass);
        }
        return innerClass;
    }

    private LuaValue getGetter(LuaValue key, int type, HashMap<LuaValue, Integer> typeCache) {
        if (type != 0 && type != GETTER) {
            return null;
        }

        LuaValue getter = f.q.get(key);
        if (getter == null) {
            String property = key.tojstring();
            if ("class".equals(property)) {
                return CoerceJavaToLua.coerce(b.getClass());
            }
            String suffix = beanSuffix(property);
            getter = f.getMethod(LuaValue.valueOf("get" + suffix));
            if (getter == null) {
                getter = f.getMethod(LuaValue.valueOf("is" + suffix));
            }
        }
        if (getter == null) {
            return null;
        }
        if (type == 0) {
            f.q.put(key, getter);
            typeCache.put(key, GETTER);
        }
        LuaValue value = getter.invokeJavaMethod(this, NONE);
        return value.isuserdata(CharSequence.class) ? value.tostring() : value;
    }

    @SuppressWarnings("rawtypes")
    private LuaValue getCollectionValue(LuaValue key, int type, HashMap<LuaValue, Integer> typeCache) {
        if (type != 0 && type != GET_VALUE) {
            return null;
        }
        if (b instanceof Map) {
            return CoerceJavaToLua.coerce(((Map) b).get(CoerceLuaToJava.coerce(key, Object.class)));
        }
        if (b instanceof List) {
            return CoerceJavaToLua.coerce(((List) b).get(key.checkint()));
        }
        if (b instanceof LuaMetaTable) {
            return ((LuaMetaTable) b).__index(key);
        }
        return null;
    }

    private boolean setField(LuaValue key, LuaValue value, int type) {
        Field field = f.b(key);
        if (field == null) {
            return false;
        }
        if (type == 0) {
            f.o.put(key, SET_FIELD);
        }
        try {
            field.set(b, CoerceLuaToJava.coerce(value, field.getType()));
            return true;
        } catch (Exception exception) {
            throw new LuaError(exception);
        }
    }

    private boolean setSetter(LuaValue key, LuaValue value, int type) {
        LuaValue setter = f.r.get(key);
        if (setter == null) {
            setter = f.getMethod(LuaValue.valueOf("set" + beanSuffix(key.tojstring())));
        }
        if (setter == null) {
            return false;
        }
        if (type == 0) {
            f.r.put(key, setter);
            f.o.put(key, SETTER);
        }
        setter.invokeJavaMethod(this, value);
        return true;
    }

    private boolean setListener(LuaValue key, LuaValue value, int type) {
        String name = key.tojstring();
        if (name.length() <= 2 || !name.startsWith("on") || !value.isfunction()) {
            return false;
        }
        if (!setJavaListener(name, value)) {
            return false;
        }
        if (type == 0) {
            f.o.put(key, SET_LISTENER);
        }
        return true;
    }

    @SuppressWarnings("rawtypes")
    private boolean setCollectionValue(LuaValue key, LuaValue value, int type) {
        if (b instanceof Map) {
            ((Map) b).put(
                CoerceLuaToJava.coerce(key, Object.class),
                CoerceLuaToJava.coerce(value, Object.class)
            );
            return true;
        }
        if (b instanceof List) {
            ((List) b).set(key.checkint(), CoerceLuaToJava.coerce(value, Object.class));
            return true;
        }
        if (b instanceof LuaMetaTable) {
            ((LuaMetaTable) b).__newindex(key, value);
            return true;
        }
        return false;
    }

    private boolean setJavaListener(String name, LuaValue value) {
        LuaValue method = f.getMethod(LuaValue.valueOf("setOn" + name.substring(2) + "Listener"));
        if (!(method instanceof JavaMethod listenerSetter)) {
            return false;
        }
        LuaTable implementation = new LuaTable();
        implementation.set(name, value);
        listenerSetter.invokeJavaMethod(
            this,
            LuajavaLib.createProxy(listenerSetter.j.getParameterTypes()[0], implementation)
        );
        return true;
    }

    private LuaValue getAssignedValue(LuaValue key) {
        HashMap<LuaValue, LuaValue> values = g;
        if (values != null && values.containsKey(key)) {
            return values.get(key);
        }

        HashMap<LuaValue, LuaValue> classValues = f.g;
        if (classValues != null && classValues.containsKey(key)) {
            return classValues.get(key);
        }
        return null;
    }

    private void setAssignedValue(LuaValue key, LuaValue value) {
        if (g == null) {
            g = new HashMap<>();
        }
        g.put(key, value);
    }

    private static int getType(HashMap<LuaValue, Integer> typeCache, LuaValue key) {
        Integer type = typeCache.get(key);
        return type != null ? type : 0;
    }

    private static String beanSuffix(String property) {
        if (property.isEmpty() || !Character.isLowerCase(property.charAt(0))) {
            return property;
        }
        return Character.toUpperCase(property.charAt(0)) + property.substring(1);
    }

    private static Varargs nextMap(Map<?, ?> map, LuaValue index) {
        Object previous = index.isnil() ? null : CoerceLuaToJava.coerce(index, Object.class);
        boolean returnNext = index.isnil();
        for (Map.Entry<?, ?> entry : map.entrySet()) {
            if (returnNext) {
                return LuaValue.varargsOf(
                    CoerceJavaToLua.coerce(entry.getKey()),
                    CoerceJavaToLua.coerce(entry.getValue()),
                    LuaValue.NONE
                );
            }
            if (previous.equals(entry.getKey())) {
                returnNext = true;
            }
        }
        return NIL;
    }
}
