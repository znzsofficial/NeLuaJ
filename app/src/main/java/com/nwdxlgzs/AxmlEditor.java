package com.nwdxlgzs;

import com.nwdxlgzs.fix.EntryPoint;
import com.nwdxlgzs.rt.NodeVisitor;
import com.nwdxlgzs.rt.Reader;
import com.nwdxlgzs.rt.Util;
import com.nwdxlgzs.rt.Visitor;
import com.nwdxlgzs.rt.Writer;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

public class AxmlEditor {
    private final String[] components = {
            "activity", "activity-alias", "provider", "receiver", "service", "intent-filter", "data"
    };
    private File mManifest;
    private int mVersionCode = -1;
    private int mMinimumSdk = -1;
    private int mTargetSdk = -1;
    private int mInstallLocation = -1;
    private String mVersionName;
    private String mAppName;
    private String mPackageName;
    private byte[] mManifestData;
    private String[] permissions;
    private boolean changeHost = true;
    private String targetScheme;
    private String replaceScheme;
    private String[] providerKeys;
    private String[] providerRaws;
    private String[] providerNews;

    public AxmlEditor(File manifest) {
        mManifest = manifest;
    }

    public AxmlEditor(InputStream manifest) throws IOException {
        mManifestData = Util.readIs(manifest);
    }

    public AxmlEditor(byte[] manifest) {
        mManifestData = manifest;
    }

    private boolean usefix = false;

    public void setUseFix(boolean use) {
        usefix = use;
    }

    public void setChangeScheme(String target, String new_scheme) {
        targetScheme = target;
        replaceScheme = new_scheme;
    }

    public void setChangeHostIfLikePackageName(boolean change) {
        changeHost = change;
    }

    public void setUsePermissions(String[] list) {
        permissions = list;
    }

    public void setVersionCode(int versionCode) {
        mVersionCode = versionCode;
    }

    public void setVersionName(String versionName) {
        mVersionName = versionName;
    }

    public void setAppName(String appName) {
        mAppName = appName;
    }

    public void setPackageName(String packageName) {
        mPackageName = packageName;
    }

    public void setMinimumSdk(int sdk) {
        mMinimumSdk = sdk;
    }

    public void setTargetSdk(int sdk) {
        mTargetSdk = sdk;
    }

    public void setInstallLocation(int location) {
        mInstallLocation = location;
    }

    public void setTargetReplaceAppName(String name) {
        needAutoGuessTarget = false;
        targetReplaceAppName = name;
    }

    public void setTargetReplacePackageName(String name) {
        needAutoGuessTarget = false;
        targetReplacePackageName = name;
    }

    public void setProviderHandleTask(String[] keys, String[] raws, String[] news) {
        providerKeys = keys;
        providerRaws = raws;
        providerNews = news;
    }

    private boolean permissionLoopOK = false;
    private String targetReplaceAppName;
    private String targetReplacePackageName;
    private boolean needAutoGuessTarget = true;

    /*private LuaActivity a;
    public void MD(LuaActivity a){
        this.a=a;
    }/**/
    public void commit() throws IOException {
        Reader reader = new Reader(mManifestData == null ? Util.readFile(mManifest) : mManifestData);
        Writer writer = new Writer();
        permissionLoopOK = false;
        if (needAutoGuessTarget) {
            targetReplaceAppName = null;
            targetReplacePackageName = null;
        }
        reader.accept(
                new Visitor(writer) {
                    public NodeVisitor child(String ns, String name) {
                        return new NodeVisitor(super.child(ns, name)) {
                            public NodeVisitor child(String ns, String name) {
                                // 只要你保留一个uses-permission的tag我就给你批量加标签
                                if (name.equalsIgnoreCase("uses-permission")) {
                  /*if(false){
                  return new NodeVisitor(super.child(ns, name)) {
                      @Override
                      public void attr(String ns,String name,int resourceId,int type,Object value) {
                          a.sendMsg(ns+"|"+ name+"|"+ resourceId+"|"+type+"|"+value);
                      }
                  };}*/

                                    if (permissions == null) {
                                        return super.child(ns, name);
                                    }
                                    if (!permissionLoopOK) {
                                        for (String permission : permissions) {
                                            super.child(ns, name)
                                                    .attr(
                                                            "http://schemas.android.com/apk/res/android",
                                                            "name",
                                                            16842755,
                                                            3,
                                                            permission);
                                        }
                                        permissionLoopOK = true;
                                    }
                                    return null;
                                } else if (name.equalsIgnoreCase("uses-sdk")) {
                                    return new NodeVisitor(super.child(ns, name)) {
                                        @Override
                                        public void attr(
                                                String ns, String name, int resourceId, int type, Object value) {
                                            if (name.equalsIgnoreCase("minSdkVersion") && mMinimumSdk > 0) {
                                                value = mMinimumSdk;
                                                type = TYPE_FIRST_INT;
                                            } else if (name.equalsIgnoreCase("targetSdkVersion") && mTargetSdk > 0) {
                                                value = mTargetSdk;
                                                type = TYPE_FIRST_INT;
                                            }
                                            super.attr(ns, name, resourceId, type, value);
                                        }
                                    };
                                } else if (name.equalsIgnoreCase("application")) {
                                    return new NodeVisitor(super.child(ns, name)) {
                                        public NodeVisitor child(String ns, String name) {
                                            if (name.equalsIgnoreCase("activity")) {
                                                return new NodeVisitor(super.child(ns, name)) {
                                                    @Override
                                                    public void attr(
                                                            String ns, String name, int resourceId, int type, Object value) {
                                                        if (name.equalsIgnoreCase("label")
                                                                && mAppName != null
                                                                && value.equals(targetReplaceAppName)) {
                                                            value = mAppName;
                                                            type = TYPE_STRING;
                                                        }
                                                        super.attr(ns, name, resourceId, type, value);
                                                    }

                                                    public NodeVisitor child(String ns, String name) {
                                                        if (name.equalsIgnoreCase("intent-filter")
                                                                && targetReplacePackageName != null
                                                                && mPackageName != null) {
                                                            return new NodeVisitor(super.child(ns, name)) {
                                                                public NodeVisitor child(String ns, String name) {
                                                                    if (name.equalsIgnoreCase("data")) {
                                                                        return new NodeVisitor(super.child(ns, name)) {
                                                                            @Override
                                                                            public void attr(
                                                                                    String ns,
                                                                                    String name,
                                                                                    int resourceId,
                                                                                    int type,
                                                                                    Object value) {
                                                                                if (name.equalsIgnoreCase("host")
                                                                                        && changeHost
                                                                                        && value.equals(targetReplacePackageName)) {
                                                                                    value = mPackageName;
                                                                                    type = TYPE_STRING;
                                                                                } else if (name.equalsIgnoreCase("scheme")
                                                                                        && targetScheme != null
                                                                                        && replaceScheme != null) {
                                                                                    value = replaceScheme;
                                                                                    type = TYPE_STRING;
                                                                                }
                                                                                super.attr(ns, name, resourceId, type, value);
                                                                            }
                                                                        };
                                                                    }
                                                                    return super.child(ns, name);
                                                                }
                                                            };
                                                        }
                                                        return super.child(ns, name);
                                                    }
                                                };
                                            }

                                            for (String component : components) {
                                                if (name.equalsIgnoreCase(component)) {
                                                    final String innerTag = component;
                                                    return new NodeVisitor(super.child(ns, name)) {
                                                        @Override
                                                        public void attr(
                                                                String ns, String name, int resourceId, int type, Object value) {
                                                            if (name.equalsIgnoreCase("name")
                                                                    && value instanceof String
                                                                    && mPackageName != null) {
                                                                int check = ((String) value).indexOf(".");
                                                                if (check < 0) {
                                                                    value = mPackageName + "." + value;
                                                                } else if (check == 0) {
                                                                    value = mPackageName + value;
                                                                }
                                                                type = TYPE_STRING;
                                                            } else if (innerTag.equalsIgnoreCase("provider")
                                                                    && name.equalsIgnoreCase("authorities")
                                                                    && mPackageName != null
                                                                    && targetReplacePackageName != null) {
                                                                if (targetReplacePackageName.equals(value)) {
                                                                    value = mPackageName;
                                                                    type = TYPE_STRING;
                                                                }
                                                            }
                                                            // 单独设置的事件，以他为准
                                                            if (innerTag.equalsIgnoreCase("provider")
                                                                    && providerKeys != null
                                                                    && providerNews != null
                                                                    && providerRaws != null) {
                                                                for (int i = 0; i < providerKeys.length; i++) {
                                                                    if (name.equalsIgnoreCase(providerKeys[i])) {
                                                                        if (value.equals(providerRaws[i])) {
                                                                            value = providerNews[i];
                                                                            type = TYPE_STRING;
                                                                            break;
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                            super.attr(ns, name, resourceId, type, value);
                                                        }
                                                    };
                                                }
                                            }
                                            return super.child(ns, name);
                                        }

                                        @Override
                                        public void attr(
                                                String ns, String name, int resourceId, int type, Object value) {
                                            if (targetReplaceAppName == null) {
                                                targetReplaceAppName = String.valueOf(value);
                                            }
                                            if (name.equalsIgnoreCase("label") && mAppName != null) {
                                                value = mAppName;
                                                type = TYPE_STRING;
                                            } else if (name.equalsIgnoreCase("extractNativeLibs")) {
                                                // return;
                                            }
                                            super.attr(ns, name, resourceId, type, value);
                                        }
                                    };
                                }
                                return super.child(ns, name);
                            }

                            @Override
                            public void attr(String ns, String name, int resourceId, int type, Object value) {
                                if (name.equalsIgnoreCase("package") && mPackageName != null) {
                                    targetReplacePackageName = String.valueOf(value);
                                    value = mPackageName;
                                    type = TYPE_STRING;
                                } else if (name.equalsIgnoreCase("installLocation")) {
                                    int loc = getRealInstallLocation(mInstallLocation);
                                    if (loc >= 0) {
                                        value = loc;
                                        type = TYPE_FIRST_INT;
                                    } else {
                                        return;
                                    }
                                } else if (name.equalsIgnoreCase("versionName") && mVersionName != null) {
                                    value = mVersionName;
                                    type = TYPE_STRING;
                                } else if (name.equalsIgnoreCase("versionCode") && mVersionCode > 0) {
                                    value = mVersionCode;
                                    type = TYPE_FIRST_INT;
                                }
                                super.attr(ns, name, resourceId, type, value);
                            }
                        };
                    }
                });
        mManifestData = usefix ? EntryPoint.fix(writer.toByteArray()) : writer.toByteArray();
    }

    public void writeTo(FileOutputStream manifestOutputStream) throws IOException {
        manifestOutputStream.write(mManifestData);
        manifestOutputStream.close();
    }

    public void writeTo(OutputStream manifestOutputStream) throws IOException {
        manifestOutputStream.write(mManifestData);
    }

    /*
    Return real install location from selected item in spinner
    */
    private int getRealInstallLocation(int installLocation) {
        return switch (installLocation) {
            case 0 -> -1; // default
            case 1 -> 0; // auto
            case 2 -> 1; // internal
            case 3 -> 2; // external
            default -> -1;
        };
    }

    public byte[] getManifestData() {
        return this.mManifestData;
    }
}
