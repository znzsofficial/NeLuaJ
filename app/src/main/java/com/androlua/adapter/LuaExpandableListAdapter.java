package com.androlua.adapter;

import android.annotation.SuppressLint;
import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.PorterDuff;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.os.Handler;
import android.os.Message;
import android.view.View;
import android.view.ViewGroup;
import android.view.animation.Animation;
import android.widget.AdapterView;
import android.widget.BaseExpandableListAdapter;
import android.widget.ImageView;
import android.widget.TextView;

import com.androlua.LuaActivity;
import com.androlua.LuaBitmap;
import com.androlua.LuaBitmapDrawable;
import com.androlua.LuaContext;
import com.androlua.LuaLayout;

import org.luaj.Globals;
import org.luaj.LuaError;
import org.luaj.LuaTable;
import org.luaj.LuaValue;
import org.luaj.lib.jse.CoerceJavaToLua;
import org.luaj.lib.jse.CoerceLuaToJava;

import java.io.IOException;
import java.util.HashMap;

public class LuaExpandableListAdapter extends BaseExpandableListAdapter {

    private final BitmapDrawable mDraw;
    private final Resources mRes;
    private final Globals L;
    private final LuaContext mContext;

    private final LuaTable mGroupData;
    private final LuaTable mChildData;

    private final HashMap<View, Animation> mAnimCache = new HashMap<View, Animation>();

    private final LuaTable mGroupLayout;
    private final LuaTable mChildLayout;

    private final LuaLayout loadlayout;

    private boolean updateing;

    private LuaValue mAnimationUtil;
    private final LuaValue LayoutParams = CoerceJavaToLua.coerce(AdapterView.LayoutParams.class);

    private boolean mNotifyOnChange;

    @SuppressLint("HandlerLeak")
    private final Handler mHandler =
            new Handler() {
                @Override
                public void handleMessage(Message msg) {
                    notifyDataSetChanged();
                }
            };

    private final HashMap<String, Boolean> loaded = new HashMap<String, Boolean>();

    public LuaExpandableListAdapter(LuaContext context, LuaTable groupLayout, LuaTable childLayout)
            throws LuaError {
        this(context, null, null, groupLayout, childLayout);
    }

    public LuaExpandableListAdapter(
            LuaContext context,
            LuaTable groupLayout,
            LuaTable childLayout,
            LuaTable groupData,
            LuaTable childData)
            throws LuaError {
        mContext = context;
        L = context.getLuaState();
        mRes = mContext.getContext().getResources();

        mDraw = new BitmapDrawable(mRes, getClass().getResourceAsStream("/res/drawable/icon.png"));
        mDraw.setColorFilter(0x88ffffff, PorterDuff.Mode.SRC_ATOP);

        mGroupLayout = groupLayout;
        mChildLayout = childLayout;

        if (groupData == null) groupData = new LuaTable(L);
        if (childData == null) childData = new LuaTable(L);
        mGroupData = groupData;
        mChildData = childData;

        loadlayout = new LuaLayout(context.getContext());
        loadlayout.load(mGroupLayout, new LuaTable(), LayoutParams);
        loadlayout.load(mChildLayout, new LuaTable(), LayoutParams);
    }

    public void setAnimationUtil(LuaValue animation) {
        mAnimCache.clear();
        mAnimationUtil = animation;
    }

    @Override
    public int getGroupCount() {
        // TODO: Implement this method
        return mGroupData.length();
    }

    @Override
    public int getChildrenCount(int groupPosition) {
        // TODO: Implement this method
        return mChildData.get(groupPosition + 1).length();
    }

    @Override
    public Object getGroup(int groupPosition) {
        // TODO: Implement this method
        return CoerceLuaToJava.coerce(mGroupData.get(groupPosition + 1), Object.class);
    }

    @Override
    public Object getChild(int groupPosition, int childPosition) {
        // TODO: Implement this method
        return CoerceLuaToJava.coerce(
                mChildData.get(groupPosition + 1).get(childPosition + 1), Object.class);
    }

    @Override
    public long getGroupId(int groupPosition) {
        // TODO: Implement this method
        return groupPosition + 1;
    }

    @Override
    public long getChildId(int groupPosition, int childPosition) {
        // TODO: Implement this method
        return childPosition + 1;
    }

    @Override
    public boolean hasStableIds() {
        // TODO: Implement this method
        return false;
    }

    public GroupItem getGroupItem(int groupPosition) {
        // TODO: Implement this method
        return new GroupItem((LuaTable) mChildData.get(groupPosition + 1));
    }

    public LuaTable getGroupData() {
        return mGroupData;
    }

    public LuaTable getChildData() {
        return mChildData;
    }

    public GroupItem add(LuaTable groupItem) throws Exception {
        mGroupData.set(mGroupData.length() + 1, groupItem);
        LuaTable childItem = new LuaTable(L);
        mChildData.set(mGroupData.length(), childItem);
        if (mNotifyOnChange) notifyDataSetChanged();
        return new GroupItem(childItem);
    }

    public GroupItem add(LuaTable groupItem, LuaTable childItem) throws Exception {
        mGroupData.set(mGroupData.length() + 1, groupItem);
        mChildData.set(mGroupData.length(), childItem);
        if (mNotifyOnChange) notifyDataSetChanged();
        return new GroupItem(childItem);
    }

    public GroupItem insert(int position, LuaTable groupItem, LuaTable childItem) throws Exception {
        mGroupData.insert(position + 1, groupItem);
        mChildData.insert(position + 1, childItem);
        if (mNotifyOnChange) notifyDataSetChanged();
        return new GroupItem(childItem);
    }

    public void remove(int idx) throws Exception {
        mGroupData.remove(idx + 1);
        if (mNotifyOnChange) notifyDataSetChanged();
    }

    public void clear() {
        mGroupData.clear();
        mChildData.clear();
        if (mNotifyOnChange) notifyDataSetChanged();
    }

    public void setNotifyOnChange(boolean notifyOnChange) {
        mNotifyOnChange = notifyOnChange;
        if (mNotifyOnChange) notifyDataSetChanged();
    }

    @Override
    public View getGroupView(
            int groupPosition, boolean isExpanded, View convertView, ViewGroup parent) {
        // TODO: Implement this method
        View view = null;
        LuaTable holder = null;
        if (convertView == null) {
            try {
                holder = new LuaTable(L);
                view = loadlayout.load(mGroupLayout, holder).touserdata(View.class);
                view.setTag(holder);
            } catch (LuaError e) {
                return new View(mContext.getContext());
            }
        } else {
            view = convertView;
            holder = (LuaTable) view.getTag();
        }

        LuaTable hm = (LuaTable) mGroupData.get(groupPosition + 1);

        if (!hm.istable()) {
            LuaActivity.logs.add("setHelper error: group " + groupPosition + " is not a table");
            return view;
        }

        LuaValue[] ks = hm.keys();
        for (LuaValue k : ks) {
            try {
                String key = k.tojstring();
                Object value = hm.jget(key);
                View obj = holder.get(key).touserdata(View.class);
                if (obj != null) {
                    setHelper(obj, value);
                }
            } catch (Exception e) {
                LuaActivity.logs.add("setHelper error: " + e);
            }
        }

        if (updateing) {
            return view;
        }

        if (mAnimationUtil != null && convertView != null) {
            Animation anim = mAnimCache.get(convertView);
            if (anim == null) {
                try {
                    anim = mAnimationUtil.call().touserdata(Animation.class);
                    mAnimCache.put(convertView, anim);
                } catch (Exception e) {
                    LuaActivity.logs.add("setHelper error: " + e);
                }
            }
            if (anim != null) {
                view.clearAnimation();
                view.startAnimation(anim);
            }
        }
        return view;
    }

    @Override
    public View getChildView(
            int groupPosition,
            int childPosition,
            boolean isLastChild,
            View convertView,
            ViewGroup parent) {
        // TODO: Implement this method
        View view = null;
        LuaTable holder = null;
        if (convertView == null) {
            try {
                holder = new LuaTable(L);
                view = loadlayout.load(mChildLayout, holder).touserdata(View.class);
                view.setTag(holder);
            } catch (LuaError e) {
                return new View(mContext.getContext());
            }
        } else {
            view = convertView;
            holder = (LuaTable) view.getTag();
        }

        LuaTable hm = (LuaTable) mChildData.get(groupPosition + 1).get(childPosition + 1);

        if (!hm.istable()) {
            LuaActivity.logs.add("setHelper error: child " + childPosition + " is not a table");
            return view;
        }

        LuaValue[] sets = hm.keys();
        for (LuaValue k : sets) {
            try {
                String key = k.tojstring();
                Object value = hm.jget(key);
                View obj = holder.get(key).touserdata(View.class);
                if (obj != null) {
                    setHelper(obj, value);
                }
            } catch (Exception e) {
                LuaActivity.logs.add("setHelper error: " + e);
            }
        }

        if (updateing) {
            return view;
        }

        if (mAnimationUtil != null && convertView != null) {
            Animation anim = mAnimCache.get(convertView);
            if (anim == null) {
                try {
                    anim = mAnimationUtil.call().touserdata(Animation.class);
                    mAnimCache.put(convertView, anim);
                } catch (Exception e) {
                    LuaActivity.logs.add("setHelper error: " + e);
                }
            }
            if (anim != null) {
                view.clearAnimation();
                view.startAnimation(anim);
            }
        }
        return view;
    }

    @Override
    public boolean isChildSelectable(int groupPosition, int childPosition) {
        // TODO: Implement this method
        return false;
    }

    private void setFields(View view, LuaTable fields) throws LuaError {
        LuaValue[] sets = fields.keys();
        for (LuaValue set : sets) {
            String key2 = set.tojstring();
            Object value2 = fields.jget(key2);
            if (key2.equalsIgnoreCase("src")) setHelper(view, value2);
            else javaSetter(view, key2, value2);
        }
    }

    private void setHelper(View view, Object value) {
        try {
            if (value instanceof LuaTable) {
                setFields(view, (LuaTable) value);
            } else if (view instanceof TextView) {
                if (value instanceof CharSequence) ((TextView) view).setText((CharSequence) value);
                else ((TextView) view).setText(value.toString());
            } else if (view instanceof ImageView) {
                if (value instanceof Bitmap) ((ImageView) view).setImageBitmap((Bitmap) value);
                else if (value instanceof String)
                    ((ImageView) view).setImageDrawable(new LuaBitmapDrawable(mContext, (String) value));
                else if (value instanceof Drawable)
                    ((ImageView) view).setImageDrawable((Drawable) value);
                else if (value instanceof Number)
                    ((ImageView) view).setImageResource(((Number) value).intValue());
            }
        } catch (Exception e) {

            e.printStackTrace();
            mContext.sendError("setHelper", e);
        }
    }

    private void javaSetter(Object obj, String methodName, Object value) throws LuaError {
        CoerceJavaToLua.coerce(obj).jset(methodName, value);
    }

    private class GroupItem {
        private final LuaTable mData;

        public GroupItem(LuaTable item) {
            mData = item;
        }

        public LuaTable getData() {
            return mData;
        }

        public void add(LuaTable item) throws Exception {
            mData.set(mData.length() + 1, item);
            if (mNotifyOnChange) notifyDataSetChanged();
        }

        public void insert(int position, LuaTable item) throws Exception {
            mData.insert(position + 1, item);
            if (mNotifyOnChange) notifyDataSetChanged();
        }

        public void remove(int position) throws Exception {
            mData.remove(position + 1);
            if (mNotifyOnChange) notifyDataSetChanged();
        }

        public void clear() {
            mData.clear();
            if (mNotifyOnChange) notifyDataSetChanged();
        }
    }

    private class AsyncLoader extends Thread {

        private String mPath;

        private LuaContext mContext;

        public Drawable getBitmap(LuaContext context, String path) throws IOException {
            // TODO: Implement this method
            mContext = context;
            mPath = path;
            if (!path.toLowerCase().startsWith("http://") && !path.toLowerCase().startsWith("https://"))
                return new BitmapDrawable(mRes, LuaBitmap.getBitmap(context, path));
            if (LuaBitmap.checkCache(context, path))
                return new BitmapDrawable(mRes, LuaBitmap.getBitmap(context, path));
            if (!loaded.containsKey(mPath)) {
                start();
                loaded.put(mPath, true);
            }

            return mDraw;
        }

        @Override
        public void run() {
            try {
                LuaBitmap.getBitmap(mContext, mPath);
                mHandler.sendEmptyMessage(0);
            } catch (LuaError e) {
                mContext.sendError("AsyncLoader", e);
            }
        }
    }
}
