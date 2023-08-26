package github.daisukiKaffuChino;

import android.database.DataSetObservable;
import android.database.DataSetObserver;
import android.view.View;
import android.view.ViewGroup;

import androidx.annotation.Keep;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.viewpager.widget.PagerAdapter;

import java.util.List;

@Keep
public class LuaPagerAdapter extends PagerAdapter {
    private final DataSetObservable mObservable = new DataSetObservable();
    List<View> pagerViews;
    List<String> titles;

    public LuaPagerAdapter(List<View> list) {
        this.pagerViews = list;
    }

    public LuaPagerAdapter(List<View> list, List<String> titles) {
        this.pagerViews = list;
        this.titles = titles;
    }

    @Nullable
    @Override
    public CharSequence getPageTitle(int position) {
        if (titles != null && titles.size() >= 0) {
            return titles.get(position);
        } else {
            return "No Title";
        }
    }

    public void destroyItem(@NonNull ViewGroup viewGroup, int i, @NonNull Object obj) {
        viewGroup.removeView(this.pagerViews.get(i));
    }

    public int getCount() {
        return this.pagerViews.size();
    }

    @NonNull
    public Object instantiateItem(@NonNull ViewGroup viewGroup, int i) {
        viewGroup.addView(this.pagerViews.get(i));
        return this.pagerViews.get(i);
    }

    public boolean isViewFromObject(@NonNull View view, @NonNull Object object) {
        return view == object;
    }

    public void notifyDataSetChanged() {
        mObservable.notifyChanged();
    }

    public void registerDataSetObserver(@NonNull DataSetObserver observer) {
        mObservable.registerObserver(observer);
    }

    public void unregisterDataSetObserver(@NonNull DataSetObserver observer) {
        mObservable.unregisterObserver(observer);
    }

    public void add(View view) {
        pagerViews.add(view);
    }

    public void insert(int index, View view) {
        pagerViews.add(index, view);
    }

    public View remove(int index) {
        return pagerViews.remove(index);
    }

    public boolean remove(View view) {
        return pagerViews.remove(view);
    }

    public View getItem(int index) {
        return pagerViews.get(index);
    }

    public List<View> getData() {
        return pagerViews;
    }
}
