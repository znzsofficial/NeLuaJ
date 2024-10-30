package dx.proxy;

import java.io.Serial;

public class ProxyException extends RuntimeException {
	
	@Serial
	private static final long serialVersionUID = 702035040596969930L;

	public ProxyException() {
		super();
	}
	
	public ProxyException(String msg) {
		super(msg);
	}

	public ProxyException(Throwable cause) {
		super(cause);
	}
}
