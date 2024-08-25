package github.znzsofficial.utils;

import android.app.ProgressDialog;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.appcompat.view.ContextThemeWrapper;

import com.androlua.LuaActivity;
import com.androlua.LuaUtil;
import com.google.android.material.dialog.MaterialAlertDialogBuilder;

import org.luaj.Globals;
import org.luaj.LuaClosure;
import org.luaj.LuaError;
import org.luaj.LuaTable;
import org.luaj.LuaValue;
import org.luaj.compiler.DumpState;
import org.luaj.lib.jse.JsePlatform;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.Enumeration;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipOutputStream;

public class LuaBuildUtil {
    private final LuaActivity mContext;
    private ProgressDialog mDlg;
    private final Globals mGlobals = JsePlatform.standardGlobals();

    public LuaBuildUtil(@NonNull LuaActivity luaActivity) {
        this.mContext = luaActivity;
    }

    public void startBin(String mProjDir, String mRootDir) {
        try {
            bin(mProjDir, mRootDir);
        } catch (Exception e) {
            e.printStackTrace();
            new MaterialAlertDialogBuilder(mContext)
                    .setTitle("Error")
                    .setMessage(e.toString())
                    .setPositiveButton(android.R.string.ok, null)
                    .show();
        }
    }

    public static String toString(Class<?>[] a) {
        if (a == null) return "null";

        int iMax = a.length - 1;
        if (iMax == -1) return "()";

        StringBuilder builder = new StringBuilder();
        builder.append('(');
        for (int i = 0; ; i++) {
            builder.append(a[i].getSimpleName());
            if (i == iMax) return builder.append(')').toString();
            builder.append(", ");
        }
    }

    public void bin(String mProjDir, String mRootDir) {
        LuaTable env = new LuaTable();
        mGlobals.loadfile(new File(mProjDir, "init.lua").getAbsolutePath(), env).call();
        String appName = "demo";
        String verName = "1.0";
        String verCode = "1";
        String pkgName = "org.luaj.demo";
        LuaValue value = env.get("appname");
        if (!value.isstring()) value = env.get("app_name");
        if (value.isstring()) appName = value.tojstring();

        value = env.get("appver");
        if (!value.isstring()) value = env.get("app_ver");
        if (!value.isstring()) value = env.get("ver_name");
        if (value.isstring()) verName = value.tojstring();

        value = env.get("appcode");
        if (!value.isstring()) value = env.get("app_code");
        if (!value.isstring()) value = env.get("ver_code");
        if (value.isstring()) verCode = value.tojstring();

        value = env.get("packagename");
        if (!value.isstring()) value = env.get("package_name");
        if (value.isstring()) pkgName = value.tojstring();

        String[] ps = new String[0];
        value = env.get("permissions");
        if (!value.istable()) value = env.get("user_permission");
        if (value.istable()) {
            LuaTable tb = value.checktable();
            int len = tb.length();
            ps = new String[len];
            for (int i = 0; i < len; i++) {
                String p = tb.get(i + 1).tojstring();
                if (!p.contains(".")) p = "android.permission." + p;
                ps[i] = p;
            }
        }

        String fappName = appName;
        String fpkgName = pkgName;
        String fverName = verName;
        final String[] finalPs = ps;
        String finalVerCode = verCode;
        mDlg = new ProgressDialog(new ContextThemeWrapper(mContext, android.R.style.Theme_DeviceDefault_Dialog));
        mDlg.setMessage("正在打包...");
        mDlg.show();
        new Thread(
                () -> bin(
                        fappName,
                        fpkgName,
                        fverName,
                        finalVerCode,
                        finalPs,
                        mRootDir,
                        new File(mProjDir)))
                .start();
    }

    public void bin(
            String appName,
            String pkg,
            String ver,
            String code,
            String[] ps,
            String mRootDir,
            File mProjDir) {
        File bf = new File(mRootDir, "bin");
        bf.mkdirs();
        File op = new File(bf, mProjDir.getName());
//        Log.i("luaj", "bin: " + op);
//        CharSequence lb = mContext.getApplicationInfo().nonLocalizedLabel;
//        String apkg = mContext.getPackageName();
//        String vr = "1.0";
//        try {
//            vr = mContext.getPackageManager().getPackageInfo(mContext.getPackageName(), 0).versionName;
//        } catch (PackageManager.NameNotFoundException e) {
//            e.printStackTrace();
//        }
        try {
            ZipOutputStream zip = new ZipOutputStream(new FileOutputStream(op));
            File[] fs = mProjDir.listFiles();
            for (File f : fs) {
                addZip(zip, f, "assets");
            }
            // ZipInputStream zin = new ZipInputStream(new FileInputStream(getPackageCodePath()));
            ZipFile apkZipFile = new ZipFile(mContext.getPackageCodePath());
            Enumeration<? extends ZipEntry> es = apkZipFile.entries();
            while (es.hasMoreElements()) {
                ZipEntry z = es.nextElement();
                if (z.getName().startsWith("assets")) continue;
                zip.putNextEntry(new ZipEntry(z.getName()));
                if (z.getName().equals("AndroidManifest.xml")) {

                    if (mDlg != null) {
                        mContext.runOnUiThread(
                                () -> mDlg.setMessage("AndroidManifest"));
                    }
                    try {
                        com.nwdxlgzs.AxmlEditor axml = new com.nwdxlgzs.AxmlEditor(apkZipFile.getInputStream(z));
                        axml.setAppName(appName);
                        axml.setPackageName(pkg);
                        axml.setVersionName(ver);
                        axml.setVersionCode(Integer.parseInt(code));
                        axml.setUsePermissions(ps);
                        axml.setProviderHandleTask(
                                new String[]{"mimeType"},
                                new String[]{"application/zip"},
                                new String[]{"application/nothing"});
                        axml.commit();
                        axml.writeTo(zip);
                    } catch (IOException e) {
                        e.printStackTrace();
                    }

                } else {
                    if (mDlg != null) {
                        mContext.runOnUiThread(
                                () -> mDlg.setMessage(z.getName()));
                        if (z.getName().endsWith("icon.png") && new File(mProjDir, "icon.png").exists())
                            LuaUtil.copyFile(new FileInputStream(new File(mProjDir, "icon.png")), zip);
                        else LuaUtil.copyFile(apkZipFile.getInputStream(z), zip);
                    }
                }
            }
            apkZipFile.close();
            zip.closeEntry();
            zip.close();
            File finalApk = new File(op.getAbsolutePath() + ".apk");
            if (mDlg != null) {
                mContext.runOnUiThread(
                        () -> mDlg.setMessage("正在改名..."));
            }
            op.renameTo(finalApk);
            if (mDlg != null) {
                mContext.runOnUiThread(
                        () -> {
                            mDlg.dismiss();
                            mDlg = null;
                        });
            }
            Log.i("luaj", "bin: finish " + op);
        } catch (Exception e) {
            mContext.runOnUiThread(
                    () -> {
                        mDlg.dismiss();
                        mDlg = null;
                        new MaterialAlertDialogBuilder(mContext)
                                .setTitle("Error")
                                .setMessage(e.getMessage())
                                .setPositiveButton(android.R.string.ok, null)
                                .show();
                    });
            e.printStackTrace();
        }
    }

    private void addZip(ZipOutputStream zip, File dir, String root) {
        Log.i("luaj", "addZip: " + root + ";" + dir);
        if (dir.getName().startsWith(".")) return;
        if (mDlg != null) {
            mContext.runOnUiThread(
                    () -> mDlg.setMessage(dir.getName()));
        }
        String name = root + "/" + dir.getName();
        if (name.endsWith(".apk")) return;
        if (dir.isDirectory()) {
            File[] fs = dir.listFiles();
            if (fs != null) {
                for (File f : fs) {
                    addZip(zip, f, name);
                }
            }
        } else {
            try {
                zip.putNextEntry(new ZipEntry(name));
            } catch (Exception e) {
                throw new LuaError(e);
            }
            if (name.endsWith(".lua")) {
                LuaValue args = mGlobals.loadfile(dir.getAbsolutePath());
                LuaValue f = args.checkfunction(1);
                ByteArrayOutputStream baos = new ByteArrayOutputStream();
                try {
                    DumpState.dump(((LuaClosure) f).c, baos, true);
                    zip.write(baos.toByteArray());
                    zip.flush();
                } catch (Exception e) {
                    throw new LuaError(e);
                }
            } else {
                try {
          /*byte[] b = LuaUtil.readAll(dir.getAbsolutePath());
          zip.write(b, 0, b.length);
          zip.flush();*/
                    FileInputStream in = new FileInputStream(dir);
                    LuaUtil.copyFile(in, zip);
                    in.close();
                } catch (Exception e) {
                    throw new LuaError(e);
                }
            }
        }
    }
}
