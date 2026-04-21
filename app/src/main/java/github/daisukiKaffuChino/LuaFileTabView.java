package github.daisukiKaffuChino;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.AttributeSet;
import android.widget.TextView;

import com.google.android.material.tabs.TabLayout;

import java.util.ArrayList;
import github.znzsofficial.neluaj.R;

public class LuaFileTabView extends TabLayout {
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ArrayList<String> pathSegments = new ArrayList<>();
    private String nowPath = "";
    private FileTabInterface fileTabInterface;
    private boolean updating;

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
        nowPath = path == null ? "" : path;
        pathSegments.clear();
        pathSegments.addAll(splitPath(nowPath));
    }

    public void setPath(String path) {
        setPath(path, true);
    }

    public void setPath(String path, final boolean selectable) {
        final String safePath = path == null ? "" : path;
        if (safePath.equals(nowPath) && getTabCount() == pathSegments.size()) {
            return;
        }

        final ArrayList<String> newSegments = splitPath(safePath);
        int commonPrefix = 0;
        int maxCommon = Math.min(pathSegments.size(), newSegments.size());
        while (commonPrefix < maxCommon && pathSegments.get(commonPrefix).equals(newSegments.get(commonPrefix))) {
            commonPrefix++;
        }

        updating = true;
        try {
            while (getTabCount() > commonPrefix) {
                removeTabAt(getTabCount() - 1);
            }
            while (pathSegments.size() > commonPrefix) {
                pathSegments.remove(pathSegments.size() - 1);
            }

            for (int i = 0; i < newSegments.size(); i++) {
                final String segment = newSegments.get(i);
                Tab tab = getTabAt(i);
                if (tab == null) {
                    tab = newTab().setIcon(R.drawable.chevron_left);
                    addTab(tab, false);
                }
                tab.setText(segment);
                TextView textView = (TextView) tab.view.getChildAt(1);
                if (textView != null) {
                    textView.setAllCaps(false);
                }
            }

            pathSegments.clear();
            pathSegments.addAll(newSegments);
            nowPath = safePath;

            if (selectable && getTabCount() > 0) {
                final Tab finalTab = getTabAt(getTabCount() - 1);
                if (finalTab != null) {
                    finalTab.select();
                    mainHandler.postDelayed(() -> {
                        final float toX = finalTab.view.getX();
                        if (toX > 0) smoothScrollTo((int) toX, 0);
                    }, 10);
                }
            }
        } finally {
            updating = false;
        }
    }

    private void addListener() {
        addOnTabSelectedListener(
                new OnTabSelectedListener() {

                    @Override
                    public void onTabSelected(Tab tab) {
                        if (updating) {
                            return;
                        }
                        int mTabCount = getTabCount();
                        int mPosition = tab.getPosition();
                        if (mPosition < mTabCount) {
                            int targetSize = mPosition + 1;
                            StringBuilder path = new StringBuilder();
                            for (int i = 0; i < targetSize && i < pathSegments.size(); i++) {
                                path.append('/').append(pathSegments.get(i));
                            }

                            updating = true;
                            try {
                                while (getTabCount() > targetSize) {
                                    removeTabAt(getTabCount() - 1);
                                }
                                while (pathSegments.size() > targetSize) {
                                    pathSegments.remove(pathSegments.size() - 1);
                                }

                                nowPath = path.toString();
                            } finally {
                                updating = false;
                            }

                            if (fileTabInterface != null) {
                                fileTabInterface.onSelected(nowPath);
                            }

                            mainHandler.postDelayed(() -> {
                                Tab finalTab = getTabAt(getTabCount() - 1);
                                if (finalTab != null) {
                                    final float toX = finalTab.view.getX();
                                    if (toX > 0) smoothScrollTo((int) toX, 0);
                                }
                            }, 1);
                        }
                    }

                    @Override
                    public void onTabUnselected(Tab tab) {
                    }

                    @Override
                    public void onTabReselected(Tab tab) {
                    }
                });
    }

    private ArrayList<String> splitPath(String path) {
        ArrayList<String> segments = new ArrayList<>();
        if (path == null || path.isEmpty()) {
            return segments;
        }
        for (String part : path.split("/")) {
            if (part != null && !part.isEmpty()) {
                segments.add(part);
            }
        }
        return segments;
    }

    public interface FileTabInterface {
        void onSelected(String path);
    }
}
