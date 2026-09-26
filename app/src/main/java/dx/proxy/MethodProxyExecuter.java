package dx.proxy;

import java.lang.reflect.Method;
import java.util.Arrays;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

import org.luaj.LuaError;

public class MethodProxyExecuter {
    public static final String EXECUTE_INTERCEPTOR = "executeInterceptor";
    public static final String EXECUTE_METHOD = "executeMethod";

    /** super 委派方法的调用级缓存：key = 类#方法#参数列表，避免每次 superCall 反射全表扫描 */
    private static final ConcurrentMap<String, Method> SUPER_METHODS = new ConcurrentHashMap<>();

    @SuppressWarnings({"rawtypes"})
    public static Object executeInterceptor(MethodInterceptor interceptor, Class<?> superClass, String methodName,
                                            Class[] argsType, Object[] argsValue, Object object) {
        if(argsValue==null)
            argsValue=new Object[0];
        if(argsType==null)
            argsType=new Class[0];
        if (interceptor == null)
            return executeMethod(superClass, methodName, argsType, argsValue, object);
        try {
            MethodProxy methodProxy = new MethodProxy(superClass, methodName, argsType);
            return interceptor.intercept(object, argsValue, methodProxy);
        } catch (LuaError e) {
            // Lua 回调自身的错误原样上抛（pcall 可捕获，且保留类型）
            throw e;
        } catch (Exception e) {
            throw new ProxyException(e);
        }
    }

    @SuppressWarnings({"unchecked", "rawtypes"})
    public static Object executeMethod(Class subClass, String methodName, Class[] argsType, Object[] argsValue, Object object) {
        String key = subClass.getName() + '#' + methodName + '#' + Arrays.toString(argsType);
        Method method = SUPER_METHODS.get(key);
        if (method != null) {
            return invoke(method, object, argsValue, key);
        }
        try {
            method = subClass.getMethod(methodName + Const.SUBCLASS_INVOKE_SUPER_SUFFIX, argsType);
        } catch (Exception e) {
            try {
                method = subClass.getDeclaredMethod(methodName + Const.SUBCLASS_INVOKE_SUPER_SUFFIX, argsType);
            } catch (Exception e2) {

                    e2.printStackTrace();
                //throw new ProxyException(e2.getCause());
                return null;
            }
        }
        method.setAccessible(true);
        SUPER_METHODS.put(key, method);
        return invoke(method, object, argsValue, key);
    }

    private static Object invoke(Method method, Object object, Object[] argsValue, String key) {
        try {
            return method.invoke(object, argsValue);
        } catch (Exception e) {
            SUPER_METHODS.remove(key);
            e.printStackTrace();
            return null;
        }
    }

}
