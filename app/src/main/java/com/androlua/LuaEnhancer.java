package com.androlua;

import org.luaj.LuaValue;

import java.lang.reflect.Field;

import dx.proxy.Enhancer;
import dx.proxy.EnhancerInterface;
import dx.proxy.MethodFilter;
import dx.proxy.MethodInterceptor;

/**
 * Created by nirenr on 2018/12/19.
 */

public final class LuaEnhancer {

    private final Enhancer mEnhancer;

    public LuaEnhancer(String cls) throws ClassNotFoundException {
        this(Class.forName(cls));
    }

    public LuaEnhancer(Class<?> cls) {
        mEnhancer = new Enhancer(LuaApplication.getInstance());
        mEnhancer.setSuperclass(cls);
    }

    public void setInterceptor(EnhancerInterface obj, MethodInterceptor interceptor) {
        obj.setMethodInterceptor_Enhancer(interceptor);
    }

    public static void setInterceptor(Class<?> obj, MethodInterceptor interceptor) {
        try {
            Field field = obj.getDeclaredField("methodInterceptor");
            field.setAccessible(true);
            field.set(obj, interceptor);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public Class<?> create() {
        try {
            return mEnhancer.create();
        } catch (Exception e) {
            e.printStackTrace();
        }
        return null;
    }

    public Class<?> create(MethodFilter filer) {
        try {
            mEnhancer.setMethodFilter(filer);
            return mEnhancer.create();
        } catch (Exception e) {
            e.printStackTrace();
        }
        return null;
    }

    public Class<?> create(LuaValue arg) {
        MethodFilter filter = (method, name) -> !arg.get(name).isnil();
        try {
            mEnhancer.setMethodFilter(filter);
            Class<?> cls = mEnhancer.create();
            setInterceptor(cls, new LuaMethodInterceptor(arg));
            return cls;
        } catch (Exception e) {
            e.printStackTrace();
        }
        return null;
    }
}
