package com.androlua.adapter;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.drawable.Drawable;
import android.os.Handler;
import android.view.View;
import android.view.ViewGroup;
import android.view.animation.Animation;
import android.widget.BaseAdapter;
import android.widget.Filter;
import android.widget.Filterable;
import android.widget.ImageView;
import android.widget.TextView;

import com.androlua.LuaActivity;
import com.androlua.LuaContext;
import com.androlua.LuaLayout;

import org.luaj.LuaError;
import org.luaj.LuaFunction;
import org.luaj.LuaTable;
import org.luaj.LuaValue;
import org.luaj.lib.jse.CoerceJavaToLua;
import org.luaj.lib.jse.CoerceLuaToJava;

import java.util.HashMap;

import coil3.ImageLoader;
import coil3.SingletonImageLoader;

public class LuaAdapter extends BaseAdapter implements Filterable {

    private final LuaTable mBaseData;
    //private BitmapDrawable mDraw;
    //private final Resources mRes;
    //private final Globals L;
    private final LuaContext mContext;

    //private final Object mLock = new Object();

    private LuaTable mLayout;
    private LuaTable mData;
    private LuaTable mTheme;

    private CharSequence mPrefix;

    private final LuaLayout loadlayout;

    private LuaFunction mAnimationUtil;

    private final HashMap<View, Animation> mAnimCache = new HashMap<View, Animation>();

    private final HashMap<View, Boolean> mStyleCache = new HashMap<View, Boolean>();

    private boolean mNotifyOnChange = true;

    private boolean updateing;

    private final Handler mHandler;

    //private final HashMap<String, Boolean> loaded = new HashMap<String, Boolean>();
    private ArrayFilter mFilter;
    private LuaFunction mLuaFilter;
    private final ImageLoader imageLoader;

    public LuaAdapter(LuaContext context, LuaTable layout) throws LuaError {
        this(context, null, layout);
    }

    public LuaAdapter(LuaContext context, LuaTable data, LuaTable layout) throws LuaError {
        mContext = context;
        if (data == null) data = new LuaTable();
        if (layout.length() == layout.size() && data.length() != data.size()) {
            mLayout = data;
            data = layout;
            layout = mLayout;
        }
        mLayout = layout;
        Context context1 = mContext.getContext();
        //mRes = mContext.getContext().getResources();
        imageLoader = SingletonImageLoader.get(context1);
        //L = context.getLuaState();
        mData = data;
        mBaseData = mData;
        mHandler = new Handler((msg) -> {
            if (msg.what == 0) {
                notifyDataSetChanged();
            } else {
                try {
                    LuaTable newValues = new LuaTable();
                    mLuaFilter.jcall(mBaseData, newValues, mPrefix);
                    mData = newValues;
                    notifyDataSetChanged();
                } catch (LuaError e) {
                    mContext.sendError("performFiltering", e);
                }
            }
            return false;
        });
        loadlayout = new LuaLayout(context1);
        loadlayout.load(mLayout, new LuaTable());
    }

    public void setAnimation(LuaFunction animation) {
        setAnimationUtil(animation);
    }

    public void setAnimationUtil(LuaFunction animation) {
        mAnimCache.clear();
        mAnimationUtil = animation;
    }

    @Override
    public int getCount() {
        // TODO: Implement this method
        return mData.length();
    }

    @Override
    public Object getItem(int position) {
        // TODO: Implement this method
        return CoerceLuaToJava.coerce(mData.get(position + 1), Object.class);
    }

    @Override
    public long getItemId(int position) {
        // TODO: Implement this method
        return position + 1;
    }

    public LuaTable getData() {
        return mData;
    }

    public void setItem(int index, LuaValue object) {
        synchronized (mBaseData) {
            mBaseData.set(index + 1, object);
        }
        if (mNotifyOnChange) notifyDataSetChanged();
    }

    public void add(LuaTable item) throws Exception {
        mBaseData.insert(mBaseData.length() + 1, item);
        if (mNotifyOnChange) notifyDataSetChanged();
    }

    public void addAll(LuaTable items) throws Exception {
        int len = items.length();
        for (int i = 1; i <= len; i++) mBaseData.insert(mBaseData.length() + 1, items.get(i));
        if (mNotifyOnChange) notifyDataSetChanged();
    }

    public void insert(int position, LuaTable item) throws Exception {
        mBaseData.insert(position + 1, item);
        if (mNotifyOnChange) notifyDataSetChanged();
    }

    public void remove(int position) throws Exception {
        mBaseData.remove(position + 1);
        if (mNotifyOnChange) notifyDataSetChanged();
    }

    public void clear() {
        mBaseData.clear();
        if (mNotifyOnChange) notifyDataSetChanged();
    }

    public void setNotifyOnChange(boolean notifyOnChange) {
        mNotifyOnChange = notifyOnChange;
        if (mNotifyOnChange) notifyDataSetChanged();
    }

    @Override
    public void notifyDataSetChanged() {
        // TODO: Implement this method
        super.notifyDataSetChanged();
        if (!updateing) {
            updateing = true;
            new Handler()
                    .postDelayed(
                            () -> updateing = false,
                            500);
        }
    }

    @Override
    public View getDropDownView(int position, View convertView, ViewGroup parent) {
        // TODO: Implement this method
        return getView(position, convertView, parent);
    }

    public void setStyle(LuaTable theme) {
        mStyleCache.clear();
        mTheme = theme;
    }

    @Override
    public View getView(int position, View convertView, ViewGroup parent) {
        // TODO: Implement this method
        View view = null;
        LuaValue lview = null;
        LuaTable holder = null;
        if (convertView == null) {
            try {
                holder = new LuaTable();
                lview = loadlayout.load(mLayout, holder);
                view = lview.touserdata(View.class);
                view.setTag(holder);
            } catch (LuaError e) {
                return new View(mContext.getContext());
            }
        } else {
            view = convertView;
            holder = (LuaTable) view.getTag();
        }

        LuaValue hm = mData.get(position + 1);

        if (!hm.istable()) {
            LuaActivity.logs.add("setHelper error: " + position + " is not a table");
            return view;
        }

        boolean bool = mStyleCache.get(view) == null;
        if (bool) mStyleCache.put(view, true);

        LuaValue[] sets = ((LuaTable) hm).keys();
        for (LuaValue set : sets) {
            try {
                String key = set.tojstring();
                Object value = hm.jget(key);
                LuaValue obj = holder.get(key);
                if (obj.isuserdata()) {
                    if (mTheme != null && bool) {
                        setHelper(obj.touserdata(View.class), mTheme.get(key));
                    }
                    setHelper(obj.touserdata(View.class), value);
                }
            } catch (Exception e) {

                e.printStackTrace();
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
                    mContext.sendError("setAnimation", e);
                }
            }
            if (anim != null) {
                view.clearAnimation();
                view.startAnimation(anim);
            }
        }
        return view;
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
                else if (value instanceof String) {
                    AsyncLoader.INSTANCE.loadImage(mContext.getContext(), imageLoader, (String) value, (ImageView) view);
                    //((ImageView) view).setImageDrawable(new LuaBitmapDrawable(mContext, (String) value));
                } else if (value instanceof Drawable)
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

    /**
     * {@inheritDoc}
     */
    @Override
    public Filter getFilter() {
        if (mFilter == null) {
            mFilter = new ArrayFilter();
        }
        return mFilter;
    }

    public void filter(CharSequence constraint) {
        getFilter().filter(constraint);
    }

    public void setFilter(LuaFunction filter) {
        mLuaFilter = filter;
    }

    /**
     * An array filter constrains the content of the array adapter with a prefix. Each item that does
     * not start with the supplied prefix is removed from the list.
     */
    private class ArrayFilter extends Filter {

        @Override
        protected FilterResults performFiltering(CharSequence prefix) {
            FilterResults results = new FilterResults();
            mPrefix = prefix;
            if (mData == null) return results;
            if (mLuaFilter != null) {
                mHandler.sendEmptyMessage(1);
                return null;
            }

            results.values = mData;
            results.count = mData.length();
            return results;
        }

        @Override
        protected void publishResults(CharSequence constraint, FilterResults results) {
      /*noinspection unchecked
      mData = (LuaTable<Integer, LuaTable<String, Object>>) results.values;
      if (results.count > 0) {
          notifyDataSetChanged();
      } else {
          notifyDataSetInvalidated();
      }*/
        }
    }
}
