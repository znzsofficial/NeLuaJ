package com.androlua;

import dx.proxy.MethodInterceptor;
import dx.proxy.MethodProxy;

import org.luaj.LuaError;
import org.luaj.LuaValue;

import java.lang.reflect.Method;

/**
 * Created by nirenr on 2018/12/21.
 */

public class LuaAbstractMethodInterceptor implements MethodInterceptor {
    private final LuaValue obj;

    public LuaAbstractMethodInterceptor(LuaValue obj) {
        this.obj = obj;
    }

    @Override
    public Object intercept(Object object, Object[] args, MethodProxy methodProxy) throws Exception {
        Method method = methodProxy.getOriginalMethod();
        String methodName = method.getName();
        LuaValue func;
        if (obj.isfunction()) {
            func = obj;
        } else {
            func = obj.get(methodName);
        }
        Class<?> retType = method.getReturnType();

        if (func.isnil()) {
            if (retType.equals(boolean.class) || retType.equals(Boolean.class))
                return false;
            else if (retType.isPrimitive() || Number.class.isAssignableFrom(retType))
                return 0;
            else
                return null;
        }

        Object ret = null;
        try {
            // Checks if returned type is void. if it is returns null.
            if (retType.equals(Void.class) || retType.equals(void.class)) {
                func.jcall(args);
            } else {
                ret = func.jcall(args);
            }
        } catch (LuaError e) {
            //mContext.sendError(methodName, e);
        }
        if (ret == null)
            if (retType.equals(boolean.class) || retType.equals(Boolean.class))
                return false;
            else if (retType.isPrimitive() || Number.class.isAssignableFrom(retType))
                return 0;
        return ret;
    }
}
