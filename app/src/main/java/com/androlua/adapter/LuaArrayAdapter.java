package com.androlua.adapter;

import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.Rect;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.os.Handler;
import android.text.TextUtils;
import android.view.View;
import android.view.ViewGroup;
import android.view.animation.Animation;
import android.widget.BaseAdapter;
import android.widget.Filter;
import android.widget.Filterable;
import android.widget.ImageView;
import android.widget.TextView;

import androidx.core.content.res.ResourcesCompat;

import com.androlua.LoadingDrawable;
import com.androlua.LuaActivity;
import com.androlua.LuaBitmap;
import com.androlua.LuaBitmapDrawable;
import com.androlua.LuaContext;
import com.androlua.LuaLayout;

import org.luaj.Globals;
import org.luaj.LuaError;
import org.luaj.LuaFunction;
import org.luaj.LuaTable;
import org.luaj.LuaValue;
import org.luaj.lib.jse.CoerceJavaToLua;
import org.luaj.lib.jse.CoerceLuaToJava;

import java.io.IOException;
import java.util.HashMap;

public class LuaArrayAdapter extends BaseAdapter implements Filterable {

    private LuaTable mData;
    private LuaTable mBaseData;
    private final Resources mRes;
    private final LuaContext mContext;

    private final Globals L;

    private final LuaTable mResource;

    private final LuaLayout loadlayout;

    private Animation mAnimation;

    private Drawable mDraw;
    private LuaFunction mLuaFilter;
    private ArrayFilter mFilter;
    private boolean mNotifyOnChange;

    public LuaArrayAdapter(LuaContext context, LuaTable resource) throws LuaError {
        this(context, resource, new LuaTable());
    }

    public LuaArrayAdapter(LuaContext context, LuaTable resource, LuaTable data) throws LuaError {
        mContext = context;
        mResource = resource;
        mData = data;
        mRes = mContext.getContext().getResources();
        mBaseData = mData;
        L = context.getLuaState();
        loadlayout = new LuaLayout(context.getContext());
        loadlayout.load(mResource, new LuaTable());
    }

    @Override
    public View getDropDownView(int position, View convertView, ViewGroup parent) {
        // TODO: Implement this method
        return getView(position, convertView, parent);
    }

    @Override
    public int getCount() {
        return mData.length();
    }

    @Override
    public Object getItem(int position) {
        return CoerceLuaToJava.coerce(mData.get(position + 1), Object.class);
    }

    @Override
    public long getItemId(int position) {
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

    public void add(LuaValue item) {
        mBaseData.insert(mBaseData.length() + 1, item);
        if (mNotifyOnChange) notifyDataSetChanged();
    }

    public void addAll(LuaTable items) {
        int len = items.length();
        for (int i = 1; i <= len; i++) mBaseData.insert(mBaseData.length() + 1, items.get(i));
        if (mNotifyOnChange) notifyDataSetChanged();
    }

    public void insert(int position, Object item) throws Exception {
        mBaseData.insert(position + 1, CoerceJavaToLua.coerce(item));
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

    @Override
    public View getView(int position, View convertView, ViewGroup parent) {
        LuaValue lview;
        View view;
        LuaTable holder;
        if (convertView == null) {
            try {
                holder = new LuaTable();
                lview = loadlayout.load(mResource, holder);
                view = lview.touserdata(View.class);
                view.setTag(holder);
            } catch (LuaError e) {
                return new View(mContext.getContext());
            }
        } else {
            view = convertView;
            holder = (LuaTable) view.getTag();
        }
        setHelper(view, getItem(position));
        if (mAnimation != null) view.startAnimation(mAnimation);
        return view;
    }

    public void setNotifyOnChange(boolean notifyOnChange) {
        mNotifyOnChange = notifyOnChange;
    }

    public void setAnimation(Animation animation) {
        this.mAnimation = animation;
    }

    public Animation getAnimation() {
        return mAnimation;
    }

    private void setHelper(View view, Object value) {
        if (view instanceof TextView) {
            if (value instanceof CharSequence) ((TextView) view).setText((CharSequence) value);
            else ((TextView) view).setText(value.toString());
        } else if (view instanceof ImageView) {
            try {
                ImageView img = (ImageView) view;
                Drawable drawable = null;
                if (value instanceof Bitmap) drawable = new BitmapDrawable(mRes, (Bitmap) value);
                else if (value instanceof String)
                    drawable = new AsyncLoader().getBitmap(mContext, (String) value);
                else if (value instanceof Drawable) drawable = (Drawable) value;
                else if (value instanceof Number)
                    drawable = ResourcesCompat.getDrawable(mRes, ((Number) value).intValue(), null);

                img.setImageDrawable(drawable);
                if (drawable instanceof BitmapDrawable) {
                    Bitmap bmp = ((BitmapDrawable) drawable).getBitmap();
                    int w = bmp.getWidth();
                    int h = bmp.getHeight();
                    if (img.getScaleType() == ImageView.ScaleType.FIT_XY) {
                        h = (int) (mContext.getWidth() * ((float) h) / ((float) w));
                        w = mContext.getWidth();
                        img.setLayoutParams(new ViewGroup.LayoutParams(w, h));
                    }
                } else if (drawable instanceof LoadingDrawable) {
                    int w = mContext.getWidth();
                    int h = w / 4;
                    img.setLayoutParams(new ViewGroup.LayoutParams(w, h));
                } else if (drawable instanceof LuaBitmapDrawable dw) {
                    int w = dw.getWidth();
                    int h = dw.getHeight();
                    if (w < 0 || h < 0) {
                        w = mContext.getWidth();
                        h = w / 4;
                        img.setLayoutParams(new ViewGroup.LayoutParams(w, h));
                    } else if (img.getScaleType() == ImageView.ScaleType.FIT_XY) {
                        h = (int) (mContext.getWidth() * ((float) h) / ((float) w));
                        w = mContext.getWidth();
                        img.setLayoutParams(new ViewGroup.LayoutParams(w, h));
                    }
                } else if (drawable != null) {
                    Rect rect = drawable.getBounds();
                    int w = rect.width();
                    int h = rect.height();

                    if (img.getScaleType() == ImageView.ScaleType.FIT_XY) {
                        h = (int) (mContext.getWidth() * ((float) h) / ((float) w));
                        w = mContext.getWidth();
                        img.setLayoutParams(new ViewGroup.LayoutParams(w, h));
                    }
                }
            } catch (Exception e) {
                LuaActivity.logs.add("setHelper error: " + e);
            }
        }
    }

    private final Handler mHandler =
            new Handler(msg -> {
                notifyDataSetChanged();
                return false;
            });
    private final HashMap<String, Boolean> loaded = new HashMap<>();

    private class AsyncLoader extends Thread {

        private String mPath;

        private LuaContext mContext;

        public Drawable getBitmap(LuaContext context, String path) throws IOException {
            // TODO: Implement this method
            mContext = context;
            mPath = path;
            if (!path.toLowerCase().startsWith("http://") && !path.toLowerCase().startsWith("https://"))
                return new LuaBitmapDrawable(context, path);
            if (LuaBitmap.checkCache(context, path)) return new LuaBitmapDrawable(context, path);
            if (!loaded.containsKey(mPath)) {
                start();
                loaded.put(mPath, true);
            }

            return new LoadingDrawable(mContext.getContext());
        }

        @Override
        public void run() {
            try {
                LuaBitmap.getBitmap(mContext, mPath);
                mHandler.sendEmptyMessage(0);
            } catch (LuaError e) {
                mContext.sendError("AsyncLoader error", e);
            }
        }
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

            if (mBaseData == null) {
                synchronized (mBaseData) {
                    mBaseData = new LuaTable(mData);
                }
            } else if (TextUtils.isEmpty(prefix)) {
                results.values = new LuaTable(mBaseData);
                results.count = mBaseData.size();
                mBaseData = null;
                return results;
            }
            if (mLuaFilter != null) {
                final LuaTable newValues = new LuaTable();
                try {
                    mLuaFilter.jcall(new LuaTable(mBaseData), newValues, prefix);
                } catch (LuaError e) {

                    e.printStackTrace();
                }
                results.values = newValues;
                results.count = newValues.size();
                return results;
            }
            if (prefix == null || prefix.length() == 0) {
                LuaTable list;
                synchronized (mBaseData) {
                    list = new LuaTable(mBaseData);
                }
                results.values = list;
                results.count = list.size();
            } else {
                String prefixString = prefix.toString().toLowerCase();

                LuaTable values;
                synchronized (mBaseData) {
                    values = new LuaTable(mBaseData);
                }

                final int count = values.size();
                final LuaTable newValues = new LuaTable();

                for (int i = 0; i < count; i++) {
                    final LuaValue value = values.get(i);
                    final String valueText = value.toString().toLowerCase();

                    // First match against the whole, non-splitted value
                    if (valueText.contains(prefixString)) {
                        newValues.add(value);
                    } /* else {
                final String[] words = valueText.split(" ");
                final int wordCount = words.length;

                // Start at index 0, in case valueText starts with space(s)
                for (int k = 0; k < wordCount; k++) {
                    if (words[k].startsWith(prefixString)) {
                        newValues.add(value);
                        break;
                    }
                }
            }*/
                }

                results.values = newValues;
                results.count = newValues.size();
            }

            return results;
        }

        @Override
        protected void publishResults(CharSequence constraint, FilterResults results) {
            //noinspection unchecked
            mData = (LuaTable) results.values;
            if (results.count > 0) {
                notifyDataSetChanged();
            } else {
                notifyDataSetInvalidated();
            }
        }
    }
}
