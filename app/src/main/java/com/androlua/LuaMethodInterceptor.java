package com.androlua;

import androidx.annotation.NonNull;

import dx.proxy.MethodInterceptor;
import dx.proxy.MethodProxy;

import org.luaj.LuaError;
import org.luaj.LuaValue;
import org.luaj.Varargs;
import org.luaj.lib.VarArgFunction;
import org.luaj.lib.jse.CoerceJavaToLua;
import org.luaj.lib.jse.CoerceLuaToJava;

import java.lang.reflect.Method;

/**
 * Created by nirenr on 2019/3/1.
 */

public class LuaMethodInterceptor implements MethodInterceptor {
    private final LuaValue obj;

    public LuaMethodInterceptor(LuaValue obj) {
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
        Object[] na = new Object[args.length + 1];
        System.arraycopy(args, 0, na, 1, args.length);
        na[0] = new SuperCall(object, methodProxy);
        args = na;
        Object ret = null;
        try {
            // Checks if returned type is void. if it is returns null.
            if (retType.equals(Void.class) || retType.equals(void.class)) {
                func.jcall(args);
            } else {
                ret = func.jcall(args);
            }
        } catch (LuaError e) {
            LuaActivity.logError(methodName, e);
        }
        if (ret == null)
            if (retType.equals(boolean.class) || retType.equals(Boolean.class))
                return false;
            else if (retType.isPrimitive() || Number.class.isAssignableFrom(retType))
                return 0;
        return ret;
    }

    private static class SuperCall extends VarArgFunction {

        private final Object mObject;
        private final MethodProxy mMethodProxy;

        public SuperCall(Object obj, MethodProxy methodProxy) {
            mObject = obj;
            mMethodProxy = methodProxy;
        }

        @Override
        public Varargs invoke(Varargs vargs) {
            int n = vargs.narg();
            Object[] args = new Object[n];
            Class[] argsType = mMethodProxy.argsType;
            for (int i = 0; i < n; i++) {
                args[i] = CoerceLuaToJava.coerce(vargs.arg(i + 1), argsType[i]);
            }
            return CoerceJavaToLua.coerce(mMethodProxy.invokeSuper(mObject, args));
        }

        @Override
        public LuaValue tostring() {
            return LuaValue.valueOf(toString());
        }

        @NonNull
        @Override
        public String toString() {
            return "SuperCall{" +
                    "Object=" + mObject +
                    ", Method=" + mMethodProxy +
                    '}';
        }
    }
}
