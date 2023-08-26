
package com.nwdxlgzs.AxmlEditor.rt;


public class Visitor extends NodeVisitor {

    public Visitor() {
        super();

    }

    public Visitor(NodeVisitor av) {
        super(av);
    }

    /**
     * create a ns
     *
     * @param prefix
     * @param uri
     * @param ln
     */
    public void ns(String prefix, String uri, int ln) {
        if (nv != null && nv instanceof Visitor) {
            ((Visitor) nv).ns(prefix, uri, ln);
        }
    }

}
