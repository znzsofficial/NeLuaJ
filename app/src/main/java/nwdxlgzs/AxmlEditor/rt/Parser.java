
package com.nwdxlgzs.AxmlEditor.rt;

import com.nwdxlgzs.AxmlEditor.rt.ResConst;
import com.nwdxlgzs.AxmlEditor.rt.StringItems;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.IntBuffer;

import static com.nwdxlgzs.AxmlEditor.rt.NodeVisitor.TYPE_INT_BOOLEAN;
import static com.nwdxlgzs.AxmlEditor.rt.NodeVisitor.TYPE_STRING;

public class Parser implements ResConst {

    public static final int END_FILE = 7;
    public static final int END_NS = 5;
    public static final int END_TAG = 3;
    public static final int START_FILE = 1;
    public static final int START_NS = 4;
    public static final int START_TAG = 2;
    public static final int TEXT = 6;
    // private int attrName[];
    // private int attrNs[];
    // private int attrResId[];
    // private int attrType[];
    // private Object attrValue[];

    private int attributeCount;

    private IntBuffer attrs;

    private int classAttribute;
    private int fileSize = -1;
    private int idAttribute;
    private ByteBuffer in;
    private int lineNumber;
    private int nameIdx;
    private int nsIdx;

    private int prefixIdx;

    private int[] resourceIds;

    private String[] strings;

    private int styleAttribute;

    private int textIdx;

    public Parser(byte[] data) {
        this(ByteBuffer.wrap(data));
    }

    public Parser(ByteBuffer in) {
        super();
        this.in = in.order(ByteOrder.LITTLE_ENDIAN);
    }

    public int getAttrCount() {
        return attributeCount;
    }

    public int getAttributeCount() {
        return attributeCount;
    }

    public String getAttrName(int i) {
        int idx = attrs.get(i * 5 + 1);
        return strings[idx];

    }

    public String getAttrNs(int i) {
        int idx = attrs.get(i * 5 + 0);
        return idx >= 0 ? strings[idx] : null;
    }

    String getAttrRawString(int i) {
        int idx = attrs.get(i * 5 + 2);
        if (idx >= 0) {
            return strings[idx];
        }
        return null;
    }

    public int getAttrResId(int i) {
        if (resourceIds != null) {
            int idx = attrs.get(i * 5 + 1);
            if (idx >= 0 && idx < resourceIds.length) {
                return resourceIds[idx];
            }
        }
        return -1;
    }

    public int getAttrType(int i) {
        return attrs.get(i * 5 + 3) >> 24;
    }

    public Object getAttrValue(int i) {
        int v = attrs.get(i * 5 + 4);

        if (i == idAttribute) {
            return ValueWrapper.wrapId(v, getAttrRawString(i));
        } else if (i == styleAttribute) {
            return ValueWrapper.wrapStyle(v, getAttrRawString(i));
        } else if (i == classAttribute) {
            return ValueWrapper.wrapClass(v, getAttrRawString(i));
        }

        switch (getAttrType(i)) {
            case TYPE_STRING:
                return strings[v];
            case TYPE_INT_BOOLEAN:
                return v != 0;
            default:
                return v;
        }
    }

    public int getLineNumber() {
        return lineNumber;
    }

    public String getName() {
        return strings[nameIdx];
    }

    public String getNamespacePrefix() {
        return strings[prefixIdx];
    }

    public String getNamespaceUri() {
        return nsIdx >= 0 ? strings[nsIdx] : null;
    }

    public String getText() {
        return strings[textIdx];
    }

    public int next() throws IOException {
        if (fileSize < 0) {
            int type = in.getInt() & 0xFFFF;
            if (type != RES_XML_TYPE) {
                throw new RuntimeException();
            }
            fileSize = in.getInt();
            return START_FILE;
        }
        int event = -1;
        for (int p = in.position(); p < fileSize; p = in.position()) {
            int type = in.getInt() & 0xFFFF;
            int size = in.getInt();
            switch (type) {
                case RES_XML_START_ELEMENT_TYPE: {
                    {
                        lineNumber = in.getInt();
                        in.getInt();/* skip, 0xFFFFFFFF */
                        nsIdx = in.getInt();
                        nameIdx = in.getInt();
                        int flag = in.getInt();// 0x00140014 ?
                        if (flag != 0x00140014) {
                            throw new RuntimeException();
                        }
                    }

                    attributeCount = in.getShort() & 0xFFFF;
                    idAttribute = (in.getShort() & 0xFFFF) - 1;
                    classAttribute = (in.getShort() & 0xFFFF) - 1;
                    styleAttribute = (in.getShort() & 0xFFFF) - 1;

                    attrs = in.asIntBuffer();

                    // attrResId = new int[attributeCount];
                    // attrName = new int[attributeCount];
                    // attrNs = new int[attributeCount];
                    // attrType = new int[attributeCount];
                    // attrValue = new Object[attributeCount];
                    // for (int i = 0; i < attributeCount; i++) {
                    // int attrNsIdx = in.getInt();
                    // int attrNameIdx = in.getInt();
                    // int raw = in.getInt();
                    // int aValueType = in.getInt() >>> 24;
                    // int aValue = in.getInt();
                    // Object value = null;
                    // switch (aValueType) {
                    // case TYPE_STRING:
                    // value = strings[aValue];
                    // break;
                    // case TYPE_INT_BOOLEAN:
                    // value = aValue != 0;
                    // break;
                    // default:
                    // value = aValue;
                    // }
                    // int resourceId = attrNameIdx < this.resourceIds.length ?
                    // resourceIds[attrNameIdx] : -1;
                    // attrNs[i] = attrNsIdx;
                    // attrName[i] = attrNameIdx;
                    // attrType[i] = aValueType;
                    // attrResId[i] = resourceId;
                    // attrValue[i] = value;
                    // }
                    event = START_TAG;
                }
                break;
                case RES_XML_END_ELEMENT_TYPE: {
                    in.position(p + size);
                    event = END_TAG;
                }
                break;
                case RES_XML_START_NAMESPACE_TYPE:
                    lineNumber = in.getInt();
                    in.getInt();/* 0xFFFFFFFF */
                    prefixIdx = in.getInt();
                    nsIdx = in.getInt();
                    event = START_NS;
                    break;
                case RES_XML_END_NAMESPACE_TYPE:
                    in.position(p + size);
                    event = END_NS;
                    break;
                case RES_STRING_POOL_TYPE:
                    strings = StringItems.read(in);
                    in.position(p + size);
                    continue;
                case RES_XML_RESOURCE_MAP_TYPE:
                    int count = size / 4 - 2;
                    resourceIds = new int[count];
                    for (int i = 0; i < count; i++) {
                        resourceIds[i] = in.getInt();
                    }
                    in.position(p + size);
                    continue;
                case RES_XML_CDATA_TYPE:
                    lineNumber = in.getInt();
                    in.getInt();/* 0xFFFFFFFF */
                    textIdx = in.getInt();

                    in.getInt();/* 00000008 00000000 */
                    in.getInt();

                    event = TEXT;
                    break;
                default:
                    throw new RuntimeException();
            }
            in.position(p + size);
            return event;
        }
        return END_FILE;
    }
}
