package org.luaj.lib.jse;

import org.luaj.LuaValue;

import java.util.concurrent.ConcurrentHashMap;

/**
 * Lazily resolves a dotted Java package path from Lua.
 */
public class JavaPackage extends LuaValue {
    private final String packageName;
    private final LuajavaLib luajava;
    private final ConcurrentHashMap<String, CachedValue> cache = new ConcurrentHashMap<>();
    private long cacheGeneration = Long.MIN_VALUE;

    public JavaPackage(String packageName) {
        this(packageName, null);
    }

    public JavaPackage(String packageName, LuajavaLib luajava) {
        this.packageName = packageName;
        this.luajava = luajava;
    }

    @Override
    public synchronized LuaValue get(String key) {
        long generation = luajava != null ? luajava.classLoaderGeneration() : 0;
        if (cacheGeneration != generation) {
            // Cached JavaClass values retain their ClassLoader. Do not retain classes from a replaced project loader.
            cache.clear();
            cacheGeneration = generation;
        }
        CachedValue cached = cache.get(key);
        if (cached != null && cached.generation == generation) {
            return cached.value;
        }

        LuaValue resolved = resolve(key);
        // A failed class lookup is only a provisional package path. It may become a class after
        // loadDex() publishes another loader snapshot, so only cache successful class resolutions.
        if (resolved instanceof JavaClass) {
            cache.put(key, new CachedValue(generation, resolved));
        }
        return resolved;
    }

    @Override
    public LuaValue get(LuaValue key) {
        return get(key.tojstring());
    }

    @Override
    public String tojstring() {
        return "JavaPackage: " + packageName;
    }

    @Override
    public int type() {
        return TUSERDATA;
    }

    @Override
    public String typename() {
        return "userdata";
    }

    private LuaValue resolve(String key) {
        String classOrPackageName = packageName + '.' + key;
        try {
            return luajava != null
                ? JavaClass.a(luajava.resolveClass(classOrPackageName))
                : JavaClass.f(classOrPackageName);
        } catch (ClassNotFoundException | SecurityException ignored) {
            return new JavaPackage(classOrPackageName, luajava);
        }
    }

    private static final class CachedValue {
        private final long generation;
        private final LuaValue value;

        private CachedValue(long generation, LuaValue value) {
            this.generation = generation;
            this.value = value;
        }
    }
}
