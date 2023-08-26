
package com.nwdxlgzs.AxmlEditor.rt;

import java.io.IOException;
import java.util.Stack;

import static com.nwdxlgzs.AxmlEditor.rt.Parser.*;

public class Reader {
    public static final NodeVisitor EMPTY_VISITOR = new NodeVisitor() {

        @Override
        public NodeVisitor child(String ns, String name) {
            return this;
        }

    };
    final Parser parser;

    public Reader(byte[] data) {
        super();
        this.parser = new Parser(data);
    }

    public void accept(final Visitor av) throws IOException {
        Stack<NodeVisitor> nvs = new Stack<NodeVisitor>();
        NodeVisitor tos = av;
        while (true) {
            int type = parser.next();
            switch (type) {
                case START_TAG:
                    nvs.push(tos);
                    tos = tos.child(parser.getNamespaceUri(), parser.getName());
                    if (tos != null) {
                        if (tos != EMPTY_VISITOR) {
                            tos.line(parser.getLineNumber());
                            for (int i = 0; i < parser.getAttrCount(); i++) {
                                tos.attr(parser.getAttrNs(i), parser.getAttrName(i), parser.getAttrResId(i),
                                        parser.getAttrType(i), parser.getAttrValue(i));
                            }
                        }
                    } else {
                        tos = EMPTY_VISITOR;
                    }
                    break;
                case END_TAG:
                    tos.end();
                    tos = nvs.pop();
                    break;
                case START_NS:
                    av.ns(parser.getNamespacePrefix(), parser.getNamespaceUri(), parser.getLineNumber());
                    break;
                case END_NS:
                    break;
                case TEXT:
                    tos.text(parser.getLineNumber(), parser.getText());
                    break;
                case END_FILE:
                    return;
            }
        }
    }
}
