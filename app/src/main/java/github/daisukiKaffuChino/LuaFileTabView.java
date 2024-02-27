package github.daisukiKaffuChino;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.AttributeSet;
import android.widget.TextView;

import com.google.android.material.tabs.TabLayout;

import java.util.ArrayList;
import java.util.Arrays;

import github.znzsofficial.neluaj.R;

public class LuaFileTabView extends TabLayout {
  private String nowPath = "";
  private FileTabInterface fileTabInterface;
  private final Looper looper = Looper.getMainLooper();

  public LuaFileTabView(Context context, AttributeSet attrs) {
    super(context, attrs);
    addListener();
  }

  public LuaFileTabView(Context context) {
    super(context);
    addListener();
  }

  public String getPath() {
    return nowPath;
  }

  public void addFileTabListener(FileTabInterface fileTabInterface) {
    this.fileTabInterface = fileTabInterface;
  }

  public void setDirectPath(String path) {
    nowPath = path;
  }

  public void setPath(String path) {
    setPath(path, true);
  }

  public void setPath(String path, final boolean selectable) {
    ArrayList<String> array = new ArrayList<>(Arrays.asList(path.split("/")));
    array.remove(0);
    ArrayList<String> lastArray = new ArrayList<>(Arrays.asList(nowPath.split("/")));
    lastArray.remove(0);

    if (array.size() <= lastArray.size()) {
      for (int i = 0; i < lastArray.size() - array.size(); i++) {
        removeTabAt(getTabCount() - 1);
      }
    }

    for (int i = 0; i < array.size(); i++) {
      Tab tab = getTabAt(i);
      if (tab != null) {
        tab.setText(array.get(i));
        TextView textView = (TextView) tab.view.getChildAt(1);
        textView.setAllCaps(false);
      } else {
        tab = newTab().setIcon(R.drawable.ic_round_chevron_left_24);
        addTab(tab);
        tab.setText(array.get(i));
        TextView textView = (TextView) tab.view.getChildAt(1);
        textView.setAllCaps(false);
      }
      if (i == array.size() - 1) {
        final Tab finalTab = tab;
        new Handler(looper)
            .postDelayed(
                () -> {
                  if (selectable) finalTab.select();
                  final float toX = finalTab.view.getX();
                  if (toX > 0) smoothScrollTo((int) toX, 0);
                },
                10);
      }
    }

    nowPath = path;
  }

  private void addListener() {
    addOnTabSelectedListener(
        new OnTabSelectedListener() {

          @Override
          public void onTabSelected(Tab tab) {
            int mTabCount = getTabCount();
            int mPosition = tab.getPosition();
            ArrayList<String> nowPaths = new ArrayList<>(Arrays.asList(nowPath.split("/")));
            nowPaths.remove(0);

            if (mPosition < mTabCount) {
              for (int i = 0; i < mTabCount - mPosition - 1; i++) {
                removeTabAt(getTabCount() - 1);
                nowPaths.remove(nowPaths.size() - 1);
              }

              StringBuilder path = new StringBuilder();
              for (int i = 0; i < nowPaths.size(); i++) path.append("/").append(nowPaths.get(i));

              if (fileTabInterface != null) fileTabInterface.onSelected(path.toString());

              new Handler(looper)
                  .postDelayed(
                      () -> {
                        Tab finalTab = getTabAt(getTabCount() - 1);
                        assert finalTab != null;
                        final float toX = finalTab.view.getX();
                        if (toX > 0) smoothScrollTo((int) toX, 0);
                      },
                      1);
              setDirectPath(path.toString());
              // selectListener(path);
            }
          }

          @Override
          public void onTabUnselected(Tab tab) {}

          @Override
          public void onTabReselected(Tab tab) {}
        });
  }

  public interface FileTabInterface {
    void onSelected(String path);
  }
}
