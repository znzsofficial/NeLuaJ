package com.androlua.adapter;

import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.os.Handler;
import android.os.Message;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.view.animation.Animation;
import android.widget.AdapterView;
import android.widget.BaseAdapter;
import android.widget.ImageView;
import android.widget.TextView;
import com.androlua.LoadingDrawable;
import com.androlua.LuaBitmap;
import com.androlua.LuaBitmapDrawable;
import com.androlua.LuaContext;
import com.androlua.LuaLayout;
import java.io.IOException;
import java.util.HashMap;
import org.luaj.Globals;
import org.luaj.LuaError;
import org.luaj.LuaTable;
import org.luaj.LuaValue;
import org.luaj.lib.jse.CoerceJavaToLua;

/** Created by Administrator on 2017/02/27 0027. */
public class LuaMultiAdapter extends BaseAdapter {

  private BitmapDrawable mDraw;
  private Resources mRes;
  private Globals L;
  private LuaContext mContext;
  private LuaValue mLayout;
  private LuaTable mData;
  private LuaValue mTheme;
  private LuaLayout loadLayout;
  private LuaValue insert;
  private LuaValue remove;
  private LuaValue mAnimationUtil;
  private HashMap<View, Animation> mAnimCache = new HashMap<View, Animation>();
  private HashMap<View, Boolean> mStyleCache = new HashMap<View, Boolean>();

  private boolean mNotifyOnChange = true;
  private boolean updateing;
  private Handler mHandler =
      new Handler() {
        @Override
        public void handleMessage(Message msg) {
          notifyDataSetChanged();
        }
      };
  private HashMap<String, Boolean> loaded = new HashMap<String, Boolean>();
  private LuaValue LayoutParams = CoerceJavaToLua.coerce(AdapterView.LayoutParams.class);

  public LuaMultiAdapter(LuaContext context, LuaValue layout) throws LuaError {
    this(context, null, layout);
  }

  public LuaMultiAdapter(LuaContext context, LuaTable data, LuaValue layout) throws LuaError {
    mContext = context;
    mLayout = layout;
    mRes = mContext.getContext().getResources();

    L = context.getLuaState();
    if (data == null) data = new LuaTable();
    mData = data;
    loadLayout = new LuaLayout(mContext.getContext());
    insert = L.get("table").get("insert");
    remove = L.get("table").get("remove");
    int len = mLayout.length();
    for (int i = 1; i <= len; i++) {
      LuaTable t = new LuaTable();
      loadLayout.load(mLayout.get(i), t, LayoutParams);
    }
  }

  @Override
  public int getViewTypeCount() {
    return mLayout.length();
  }

  @Override
  public int getItemViewType(int position) {
    try {
      int t = mData.get(position + 1).get("__type").toint() - 1;
      return t < 0 ? 0 : t;
    } catch (Exception e) {

      e.printStackTrace();
      return 0;
    }
  }

  public void setAnimation(LuaValue animation) {
    setAnimationUtil(animation);
  }

  public void setAnimationUtil(LuaValue animation) {
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
    return mData.get(position + 1);
  }

  @Override
  public long getItemId(int position) {
    // TODO: Implement this method
    return position + 1;
  }

  public LuaValue getData() {
    return mData;
  }

  public void add(LuaValue item) throws Exception {
    insert.jcall(mData, item);
    if (mNotifyOnChange) notifyDataSetChanged();
  }

  public void addAll(LuaValue items) throws Exception {
    int len = items.length();
    for (int i = 1; i <= len; i++) insert.jcall(mData, items.get(i));
    if (mNotifyOnChange) notifyDataSetChanged();
  }

  public void insert(int position, LuaValue item) throws Exception {
    insert.jcall(mData, position + 1, item);
    if (mNotifyOnChange) notifyDataSetChanged();
  }

  public void remove(int position) throws Exception {
    remove.jcall(mData, position + 1);
    if (mNotifyOnChange) notifyDataSetChanged();
  }

  public void clear() {
    mData.clear();
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
                  () -> {
                    // TODO: Implement this method
                    updateing = false;
                  },
              500);
    }
  }

  @Override
  public View getDropDownView(int position, View convertView, ViewGroup parent) {
    // TODO: Implement this method
    return getView(position, convertView, parent);
  }

  public void setStyle(LuaValue theme) {
    mStyleCache.clear();
    mTheme = theme;
  }

  @Override
  public View getView(int position, View convertView, ViewGroup parent) {
    // TODO: Implement this method
    View view = null;
    LuaTable holder = null;
    int t = mData.get(position + 1).get("__type").toint();
    t = t < 1 ? 1 : t;
    if (convertView == null) {
      try {
        LuaValue layout = mLayout.get(t);
        holder = new LuaTable();
        view = loadLayout.load(layout, holder, LayoutParams).touserdata(View.class);
        view.setTag(holder);
        // mHolderCache.put(view,holder);
      } catch (LuaError e) {
        return new View(mContext.getContext());
      }
    } else {
      view = convertView;
      holder = (LuaTable) view.getTag();
      // holder = mHolderCache.get(view);
    }

    LuaTable hm = mData.get(position + 1).checktable();

    if (hm == null) {
      Log.i("lua", position + " is null");
      return view;
    }

    boolean bool = mStyleCache.get(view) == null;
    if (bool) mStyleCache.put(view, true);

    LuaValue[] sets = hm.keys();
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
        Log.i("lua", e.getMessage());
      }
    }

    if (updateing) {
      return view;
    }

    if (mAnimationUtil != null && convertView != null) {
      Animation anim = mAnimCache.get(convertView);
      if (anim == null) {
        try {
          anim = mAnimationUtil.get(t).call().touserdata(Animation.class);
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
      if (key2.toLowerCase().equals("src")) setHelper(view, value2);
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
        else if (value instanceof Drawable) ((ImageView) view).setImageDrawable((Drawable) value);
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

      return new LoadingDrawable(mContext.getContext());
    }

    @Override
    public void run() {
      // TODO: Implement this method
      try {
        LuaBitmap.getBitmap(mContext, mPath);
        mHandler.sendEmptyMessage(0);
      } catch (LuaError e) {
        mContext.sendError("AsyncLoader", e);
      }
    }
  }
}
