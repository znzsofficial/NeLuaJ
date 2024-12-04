package com.androlua.adapter;

import android.annotation.SuppressLint;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.drawable.Drawable;
import android.net.Uri;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

import com.androlua.LuaContext;
import com.androlua.LuaLayout;

import org.luaj.LuaError;
import org.luaj.LuaTable;
import org.luaj.LuaValue;
import org.luaj.lib.jse.CoerceJavaToLua;

import java.io.File;

import coil3.ImageLoader;
import coil3.SingletonImageLoader;

public class LuaRecyclerAdapter extends RecyclerView.Adapter<LuaRecyclerAdapter.LuaViewHolder> {

    private final LuaContext mContext;
    private LuaTable mLayout;
    private LuaTable mData;
    private final LuaTable mBaseData;
    private final LuaLayout loadlayout;
    private final ImageLoader imageLoader;
    private boolean mNotifyOnChange = true;

    public LuaRecyclerAdapter(LuaContext context, LuaTable layout) throws LuaError {
        this(context, null, layout);
    }

    public LuaRecyclerAdapter(LuaContext context, LuaTable data, LuaTable layout) throws LuaError {
        mContext = context;
        if (data == null) data = new LuaTable();
        if (layout.length() == layout.size() && data.length() != data.size()) {
            mLayout = data;
            data = layout;
            layout = mLayout;
        }
        mLayout = layout;
        mData = data;
        mBaseData = data;
        Context context1 = mContext.getContext();
        imageLoader = SingletonImageLoader.get(context1);
        loadlayout = new LuaLayout(context1);
        //loadlayout.load(mLayout, new LuaTable());
    }

    @NonNull
    @Override
    public LuaViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        try {
            LuaTable holder = new LuaTable();
            LuaValue view = loadlayout.load(mLayout, holder);
            return new LuaViewHolder(view.touserdata(View.class), holder);
        } catch (LuaError e) {
            return new LuaViewHolder(new View(mContext.getContext()), new LuaTable());
        }
    }

    public interface DataBinder {
        void bind(LuaTable binding, LuaTable data);
    }

    private DataBinder dataBinder;

    public void setDataBinder(DataBinder binder) {
        this.dataBinder = binder;
    }

    @SuppressLint("PendingBindings")
    @Override
    public void onBindViewHolder(@NonNull LuaViewHolder holder, int position) {
        if (dataBinder != null) {
            dataBinder.bind(holder.binding, mData.get(position + 1).checktable());
        } else {
            // 默认绑定逻辑
            LuaValue item = mData.get(position + 1);
            if (item.istable()) {
                LuaTable itemTable = item.checktable();
                LuaValue[] keys = itemTable.keys();
                for (LuaValue key : keys) {
                    String field = key.tojstring();
                    Object value = itemTable.jget(field);
                    LuaValue view = holder.binding.get(field);
                    if (view.isuserdata(View.class)) {
                        setHelper(view.touserdata(View.class), value);
                    }
                }
            }
        }
    }

    @Override
    public int getItemCount() {
        return mData.length();
    }

    public void setNotifyOnChange(boolean notifyOnChange){
        mNotifyOnChange = notifyOnChange;
    }

    public void add(LuaTable item) {
        mBaseData.insert(mBaseData.length() + 1, item);
        if (mNotifyOnChange) notifyItemInserted(mData.length());
    }

    public void addAll(LuaTable items) throws Exception {
        int len = items.length();
        for (int i = 1; i <= len; i++) mBaseData.insert(mBaseData.length() + 1, items.get(i));
        if (mNotifyOnChange) notifyItemRangeInserted(0, len);
    }

    public void insert(int position, LuaTable item) throws Exception {
        mBaseData.insert(position + 1, item);
        if (mNotifyOnChange) notifyItemInserted(position);
    }

    public void remove(int position) throws Exception {
        mBaseData.remove(position + 1);
        if (mNotifyOnChange) notifyItemRemoved(position);
    }

    public void clear() {
        mBaseData.clear();
        if (mNotifyOnChange) notifyDataSetChanged();
    }

//    public void updateData(LuaTable newData) {
//        LuaTable oldData = this.mData;
//        this.mData = newData;
//
//        DiffUtil.DiffResult diffResult = DiffUtil.calculateDiff(new DiffUtil.Callback() {
//            @Override
//            public int getOldListSize() {
//                return oldData.length();
//            }
//
//            @Override
//            public int getNewListSize() {
//                return newData.length();
//            }
//
//            @Override
//            public boolean areItemsTheSame(int oldItemPosition, int newItemPosition) {
//                // 判断两项是否相同（如通过ID）
//                return oldData.get(oldItemPosition + 1).raweq(newData.get(newItemPosition + 1));
//            }
//
//            @Override
//            public boolean areContentsTheSame(int oldItemPosition, int newItemPosition) {
//                // 判断内容是否完全一致
//                return oldData.get(oldItemPosition + 1).raweq(newData.get(newItemPosition + 1));
//            }
//        });
//
//        diffResult.dispatchUpdatesTo(this);
//    }

    private void setFields(View view, LuaTable fields) throws LuaError {
        LuaValue[] sets = fields.keys();
        for (LuaValue set : sets) {
            String key2 = set.tojstring();
            Object value2 = fields.jget(key2);
            if (key2.equalsIgnoreCase("src")) setHelper(view, value2);
            else javaSetter(view, key2, value2);
        }
    }

    private void javaSetter(Object obj, String methodName, Object value) throws LuaError {
        CoerceJavaToLua.coerce(obj).jset(methodName, value);
    }

    private void setHelper(View view, Object value) {
        try {
            // 如果值是参数表
            if (value instanceof LuaTable) {
                setFields(view, (LuaTable) value);
            } else if (view instanceof TextView) {
                if (value instanceof CharSequence) ((TextView) view).setText((CharSequence) value);
                else ((TextView) view).setText(value.toString());
            } else if (view instanceof ImageView) {
                if (value instanceof Bitmap) ((ImageView) view).setImageBitmap((Bitmap) value);
                else if (value instanceof Drawable)
                    ((ImageView) view).setImageDrawable((Drawable) value);
                else if (value instanceof Number)
                    ((ImageView) view).setImageResource(((Number) value).intValue());
                else if (value instanceof String || value instanceof Uri || value instanceof File) {
                    AsyncLoader.INSTANCE.loadImage(mContext.getContext(), imageLoader, value, (ImageView) view);
                    //((ImageView) view).setImageDrawable(new LuaBitmapDrawable(mContext, (String) value));
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
            mContext.sendError("setHelper", e);
        }
    }

    public static class LuaViewHolder extends RecyclerView.ViewHolder {
        LuaTable binding;

        public LuaViewHolder(@NonNull View itemView, LuaTable binding) {
            super(itemView);
            this.binding = binding;
        }
    }

}
