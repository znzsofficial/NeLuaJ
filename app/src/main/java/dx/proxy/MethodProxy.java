package dx.proxy;

import androidx.annotation.NonNull;

import java.lang.reflect.Method;
import java.util.Arrays;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

public class MethodProxy {

    private final Class<?> subClass;
    private final String methodName;
    public final Class<?>[] argsType;

    /**
     * 反射解析缓存。MethodProxy 在每次拦截调用时都会被 new 出来，
     * 实例级缓存永远不会命中，因此必须是静态的：key = 类#方法#参数类型。
     */
    private static final ConcurrentMap<String, Method> ORIGINAL = new ConcurrentHashMap<>();
    private static final ConcurrentMap<String, Method> SUPER = new ConcurrentHashMap<>();

    @SuppressWarnings("rawtypes")
    public MethodProxy(Class subClass, String methodName, Class[] argsType) {
        this.subClass = subClass;
        this.methodName = methodName;
        this.argsType = argsType;
    }

    private String cacheKey() {
        return subClass.getName() + '#' + methodName + '#' + Arrays.toString(argsType);
    }

    public String getMethodName() {
        return methodName;
    }

    /** 缓存反射查找结果：intercept 每次调用都会走到这里，getMethod 是全表扫描 */
    public Method getOriginalMethod() {
        String key = cacheKey();
        Method method = ORIGINAL.get(key);
        if (method != null) return method;
        try {
            method = subClass.getMethod(methodName, argsType);
        } catch (NoSuchMethodException e) {
            try {
                method = subClass.getDeclaredMethod(methodName, argsType);
            } catch (NoSuchMethodException e2) {
                throw new ProxyException(e2.getMessage());
            }
        }
        ORIGINAL.put(key, method);
        return method;
    }

    public Method getSuperMethod() {
        String key = "super#" + cacheKey();
        Method method = SUPER.get(key);
        if (method != null) return method;
        Class<?> superclass = subClass.getSuperclass();
        try {
            method = superclass.getMethod(methodName, argsType);
        } catch (NoSuchMethodException e) {
            try {
                method = superclass.getDeclaredMethod(methodName, argsType);
            } catch (NoSuchMethodException e2) {
                throw new ProxyException(e2.getMessage());
            }
        }
        SUPER.put(key, method);
        return method;
    }

    public Method getProxyMethod() {
        try {
            return subClass.getMethod(methodName + Const.SUBCLASS_INVOKE_SUPER_SUFFIX, argsType);
        } catch (NoSuchMethodException e) {
            throw new ProxyException(e.getMessage());
        }
    }

    public Object invokeSuper(Object object, Object[] argsValue) {
        return ((EnhancerInterface) object).executeSuperMethod_Enhancer(methodName, argsType, argsValue);
    }

    @NonNull
    @Override
    public String toString() {
        return "MethodProxy{" +
                getSuperMethod() +
                '}';
    }
}
