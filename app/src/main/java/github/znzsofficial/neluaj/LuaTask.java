package github.znzsofficial.neluaj;

import android.annotation.SuppressLint;
import android.os.Handler;
import android.os.Looper;
import androidx.annotation.NonNull;
import com.androlua.LuaContext;
import com.androlua.LuaGcable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.luaj.LuaValue;
import org.luaj.Varargs;
import org.luaj.lib.VarArgFunction;
import org.luaj.lib.jse.CoerceJavaToLua;

public class LuaTask extends VarArgFunction implements LuaGcable {
  private final LuaContext mContext;
  private ExecutorService mExecutor;
  private Handler handler;

  public LuaTask(@NonNull LuaContext context) {
    mContext = context;
    context.regGc(this);
  }

  @SuppressLint("StaticFieldLeak")
  public Varargs invoke(Varargs args) {

    int narg = args.narg();
    int i = narg - 2;
    LuaValue[] as = new LuaValue[i >= 0 ? i : 0];
    LuaValue func = args.arg1();
    for (int i2 = 0; i2 < i; i2++) {
      as[i2] = args.arg(i2 + 2);
    }

    mExecutor = Executors.newSingleThreadExecutor();
    handler = new Handler(Looper.getMainLooper());

    Runnable LuaTaskRunnable =
        new Runnable() {
          private Varargs result;

          @Override
          public void run() {
            if (func.isnumber()) {
              try {
                Thread.sleep(func.tolong());
              } catch (Exception e) {
                e.printStackTrace();
                mContext.sendError("LuaTask: Delay", e);
              }
            } else {
              try {
                result = func.invoke(LuaValue.varargsOf(as));
              } catch (Exception e) {
                e.printStackTrace();
                mContext.sendError("LuaTask: DoInBackground", e);
                result =
                    LuaValue.varargsOf(
                        new LuaValue[] {LuaValue.NIL, LuaValue.valueOf(e.toString())});
              }
            }
            handler.post(
                () -> {
                  if (narg > 1) {
                    try {
                      args.arg(narg).invoke(result);
                    } catch (Exception e) {
                      e.printStackTrace();
                      mContext.sendError("LuaTask: Callback", e);
                    }
                  }
                });
          }
          ;
        };
    mExecutor.execute(LuaTaskRunnable);
    return CoerceJavaToLua.coerce(mExecutor);
  }

  @Override
  public void gc() {
    if (mExecutor != null) mExecutor.shutdown();
  }

  @Override
  public boolean isGc() {
    return false;
  }

  public ExecutorService getExecutor() {
    return this.mExecutor;
  }
}
