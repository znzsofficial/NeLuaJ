package github.daisukiKaffuChino;

import android.view.View;
import android.view.ViewGroup;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.viewpager.widget.PagerAdapter;

import java.util.ArrayList;
import java.util.List;

public final class LuaPagerAdapter extends PagerAdapter {
    private final List<View> pagerViews = new ArrayList<>();
    private final List<String> titles = new ArrayList<>();

    public LuaPagerAdapter() {
    }

    @Nullable
    @Override
    public CharSequence getPageTitle(int position) {
        if (position >= 0 && position < titles.size()) {
            return titles.get(position);
        }
        return "";
    }

    @Override
    public void destroyItem(@NonNull ViewGroup container, int position, @NonNull Object object) {
        container.removeView((View) object);
    }

    @Override
    public int getCount() {
        return this.pagerViews.size();
    }

    @NonNull
    @Override
    public Object instantiateItem(@NonNull ViewGroup container, int position) {
        View view = pagerViews.get(position);
        container.addView(view);
        return view;
    }

    @Override
    public boolean isViewFromObject(@NonNull View view, @NonNull Object object) {
        return view == object;
    }

    @Override
    public int getItemPosition(@NonNull Object object) {
        int index = pagerViews.indexOf(object);
        return index >= 0 ? index : POSITION_NONE;
    }

    public void setData(List<View> list) {
        pagerViews.clear();
        titles.clear();
        if (list != null) pagerViews.addAll(list);
        normalizeTitles();
        notifyDataSetChanged();
    }

    public void setData(List<View> list, List<String> titleList) {
        pagerViews.clear();
        titles.clear();
        if (list != null) pagerViews.addAll(list);
        if (titleList != null) titles.addAll(titleList);
        normalizeTitles();
        notifyDataSetChanged();
    }


    public void add(View view) {
        pagerViews.add(view);
        titles.add("");
        notifyDataSetChanged();  // 通知数据已更改
    }

    public void add(View view, String title) {
        pagerViews.add(view);
        titles.add(normalizeTitle(title));
        notifyDataSetChanged();  // 通知数据已更改
    }

    public void insert(int index, View view) {
        insert(index, view, "");
    }

    public void insert(int index, View view, String title) {
        if (index < 0 || index > pagerViews.size()) return;
        pagerViews.add(index, view);
        titles.add(index, normalizeTitle(title));
        notifyDataSetChanged();  // 通知数据已更改
    }

    public void set(int index, View view) {
        set(index, view, index < titles.size() ? titles.get(index) : "");
    }

    public void set(int index, View view, String title) {
        if (index < 0 || index >= pagerViews.size()) return;
        pagerViews.set(index, view);
        if (index < titles.size()) {
            titles.set(index, normalizeTitle(title));
        } else {
            normalizeTitles();
            titles.set(index, normalizeTitle(title));
        }
        notifyDataSetChanged();
    }

    public View remove(int index) {
        if (index < 0 || index >= pagerViews.size()) return null;
        View removedView = pagerViews.remove(index);
        if (index < titles.size()) titles.remove(index);
        notifyDataSetChanged();  // 通知数据已更改
        return removedView;
    }

    public boolean remove(View view) {
        int index = pagerViews.indexOf(view);
        if (index >= 0) {
            pagerViews.remove(index);
            if (index < titles.size()) titles.remove(index);
            notifyDataSetChanged();  // 通知数据已更改
            return true;
        }
        return false;
    }

    public void clear() {
        pagerViews.clear();
        titles.clear();
        notifyDataSetChanged();
    }

    public View getItem(int index) {
        return pagerViews.get(index);
    }

    public List<View> getData() {
        return pagerViews;
    }

    public List<String> getTitles() {
        return titles;
    }

    private void normalizeTitles() {
        while (titles.size() > pagerViews.size()) {
            titles.remove(titles.size() - 1);
        }
        while (titles.size() < pagerViews.size()) {
            titles.add("");
        }
        for (int i = 0; i < titles.size(); i++) {
            titles.set(i, normalizeTitle(titles.get(i)));
        }
    }

    private String normalizeTitle(String title) {
        return title != null ? title : "";
    }
}
