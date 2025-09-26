package github.daisukiKaffuChino;

import android.view.View;
import android.view.ViewGroup;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.viewpager.widget.PagerAdapter;

import java.util.ArrayList;
import java.util.List;

public final class LuaPagerAdapter extends PagerAdapter {
    final List<View> pagerViews;
    List<String> titles;

    public LuaPagerAdapter(List<View> list) {
        this.pagerViews = list;
    }

    public LuaPagerAdapter(List<View> list, List<String> titles) {
        this.pagerViews = list;
        this.titles = titles != null ? titles : new ArrayList<>(); // 避免 titles 为 null
    }

    @Nullable
    @Override
    public CharSequence getPageTitle(int position) {
        if (titles != null && position < titles.size()) {
            return titles.get(position);
        } else {
            return "No Title";
        }
    }

    @Override
    public void destroyItem(@NonNull ViewGroup viewGroup, int position, @NonNull Object object) {
        viewGroup.removeView(this.pagerViews.get(position));
    }

    @Override
    public int getCount() {
        return this.pagerViews.size();
    }

    @NonNull
    @Override
    public Object instantiateItem(@NonNull ViewGroup viewGroup, int position) {
        viewGroup.addView(this.pagerViews.get(position));
        return this.pagerViews.get(position);
    }

    @Override
    public boolean isViewFromObject(@NonNull View view, @NonNull Object object) {
        return view == object;
    }


    public void add(View view) {
        pagerViews.add(view);
        notifyDataSetChanged();  // 通知数据已更改
    }

    public void add(View view, String title) {
        pagerViews.add(view);
        titles.add(title);
        notifyDataSetChanged();  // 通知数据已更改
    }

    public void insert(int index, View view) {
        pagerViews.add(index, view);
        notifyDataSetChanged();  // 通知数据已更改
    }

    public void insert(int index, View view, String title) {
        pagerViews.add(index, view);
        titles.add(index, title);
        notifyDataSetChanged();  // 通知数据已更改
    }

    public View remove(int index) {
        View removedView = pagerViews.remove(index);
        if (titles != null) titles.remove(index);
        notifyDataSetChanged();  // 通知数据已更改
        return removedView;
    }

    public boolean remove(View view) {
        boolean removed = pagerViews.remove(view);
        if (removed) {
            notifyDataSetChanged();  // 通知数据已更改
        }
        return removed;
    }

    public View getItem(int index) {
        return pagerViews.get(index);
    }

    public List<View> getData() {
        return pagerViews;
    }
}
