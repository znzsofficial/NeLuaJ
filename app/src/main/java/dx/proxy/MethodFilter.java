package dx.proxy;

import java.lang.reflect.Method;

/**
 * Created by nirenr on 2018/12/20.
 */

public interface MethodFilter {
    boolean filter(Method mode, String name);
}
