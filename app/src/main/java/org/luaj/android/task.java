package org.luaj.android;

import com.androlua.AsyncTaskX;
import com.androlua.LuaContext;
import com.androlua.LuaGcable;

import org.luaj.LuaValue;
import org.luaj.Varargs;
import org.luaj.lib.VarArgFunction;
import org.luaj.lib.jse.CoerceJavaToLua;

public class task extends VarArgFunction implements LuaGcable {
    private final LuaContext mContext;
    private AsyncTaskX<Varargs, Varargs, Varargs> mTask;

    public task(LuaContext context) {
        mContext = context;
        context.regGc(this);
    }

    public Varargs invoke(Varargs args) {
        int n = args.narg();
        int i = n - 2;
        i = i >= 0 ? i : 0;
        LuaValue[] as = new LuaValue[i];
        LuaValue func = args.arg1();
        for (int i1 = 0; i1 < n - 2; i1++) {
            as[i1] = args.arg(i1 + 2);
        }
        mTask = new AsyncTaskX<>() {
            protected Varargs a(Varargs... varargs) {
                if (func.isnumber()) {
                    try {
                        Thread.sleep(func.tolong());
                    } catch (Exception ignored) {
                    }
                    return LuaValue.varargsOf(as);
                }
                try {
                    return func.invoke(as);
                } catch (Exception e) {
                    mContext.sendError("task", e);
                    return LuaValue.varargsOf(new LuaValue[]{LuaValue.NIL, LuaValue.valueOf(e.toString())});
                }
            }

            protected void b(Varargs varargs) {
                if (n > 1) {
                    try {
                        args.arg(n).invoke(varargs);
                    } catch (Exception e) {
                        mContext.sendError("task", e);
                    }
                }
            }
        };
        mTask.execute();
        return CoerceJavaToLua.coerce(mTask);
    }

    @Override
    public void gc() {
        if (mTask != null)
            mTask.cancel(true);
    }

    @Override
    public boolean isGc() {
        return false;
    }
}