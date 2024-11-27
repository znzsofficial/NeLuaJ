package dx.proxy;

public interface EnhancerInterface {
	String SET_METHOD_INTERCEPTOR_ENHANCER = "setMethodInterceptor_Enhancer";
	String EXECUTE_SUPER_METHOD_ENHANCER = "executeSuperMethod_Enhancer";
	void setMethodInterceptor_Enhancer(MethodInterceptor methodInterceptor);
	
	@SuppressWarnings("rawtypes")
    Object executeSuperMethod_Enhancer(String methodName, Class[] argsType, Object[] argsValue);

}
