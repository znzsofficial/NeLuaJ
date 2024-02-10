import "com.androlua.LuaEditor";
import "android.widget.LinearLayout";
import "android.widget.HorizontalScrollView";
import "androidx.appcompat.widget.AppCompatImageView"
import "androidx.coordinatorlayout.widget.CoordinatorLayout";
import "androidx.drawerlayout.widget.DrawerLayout";
import "androidx.recyclerview.widget.RecyclerView";
import "androidx.swiperefreshlayout.widget.SwipeRefreshLayout";
import "com.google.android.material.appbar.AppBarLayout"
import "com.google.android.material.appbar.MaterialToolbar"
import "com.google.android.material.card.MaterialCardView"
import "com.google.android.material.navigation.NavigationView";
import "com.google.android.material.divider.MaterialDivider";
import "com.google.android.material.tabs.TabLayout"
import "github.znzsofficial.widget.container.MyFullDraggableContainer"
import "vinx.material.textfield.MaterialTextField"
import "com.google.android.material.navigation.NavigationView"

local ColorUtil = this.globalData.ColorUtil
local LuaFileTabView = bindClass "github.daisukiKaffuChino.LuaFileTabView"
local MyFileTabView = LuaFileTabView.override{
  function onInterceptTouchEvent(super, event)
    return true
  end
}

local rippleRes = activity.obtainStyledAttributes({android.R.attr.selectableItemBackgroundBorderless}).getResourceId(0,0)

local ColorBackground = ColorUtil.getColorBackground()

return {
  CoordinatorLayout;
  layout_height="match";
  layout_width="match";
  id="coordinatorLayout";
  {
    LinearLayout;
    gravity="center";
    layout_height="fill";
    layout_width="fill";
    orientation="vertical";
    {
      AppBarLayout;
      layout_height="wrap";
      layout_width="match";
      id="appBar",
      {
        MaterialToolbar;
        layout_height="64dp";
        layout_width="match";
        BackgroundColor=ColorBackground,
        id="mToolBar";
      };
      {
        MaterialCardView,
        id="mSearch";
        radius="36dp",
        strokeWidth="0dp",
        layout_width="match",
        layout_height="56dp",
        layout_marginLeft="8dp",
        layout_marginRight="8dp",
        CardBackgroundColor=ColorUtil.getColorSurfaceVariant(),
        {
          LinearLayout,
          layout_width="match",
          layout_height="match",
          orientation="horizontal";
          gravity="center",
          {
            MaterialTextField,
            layout_width="64%w",
            layout_height="match",
            layout_marginLeft="12dp",
            Hint="Search Code",
            id="mSearchEdit",
            style=MDC_R.style.Widget_Material3_TextInputLayout_FilledBox,
            TintColor=ColorUtil.getColorPrimary(),
            singleLine=true,
          },
          {
            AppCompatImageView,
            id="search_up",
            layout_width="14%w",
            layout_height="14%w",
            src=activity.getLuaDir().."/res/drawable/s_up.png",
            BackgroundResource=rippleRes,
            clickable=true,
          },
          {
            AppCompatImageView,
            id="search_down",
            layout_width="14%w",
            layout_height="14%w",
            src=activity.getLuaDir().."/res/drawable/s_down.png",
            BackgroundResource=rippleRes,
            clickable=true,
          },
        },
      },
      {
        TabLayout,
        id="mTab",
        layout_height="36dp",
        layout_width="match",
        TabMode=TabLayout.MODE_SCROLLABLE,
        BackgroundColor=ColorBackground,
        Elevation="0dp",
      };
      {
        MaterialDivider,
        layout_width="fill",
        layout_height="1dp";
      },
    };
    {
      DrawerLayout;
      id="drawer";
      layout_height="match_parent";
      layout_width="match_parent";
      {
        MyFullDraggableContainer,
        Swipeable=false,
        {
          LinearLayout;
          gravity="center";
          layout_height="fill";
          layout_width="fill";
          orientation="vertical";
          {
            LuaEditor;
            layout_height="fill";
            layout_width="fill";
            layout_gravity="center",
            id="mLuaEditor";
            layout_weight=1,
            -- clickable=true,
          };

          {
            MaterialDivider,
            layout_width="fill",
            layout_height="1dp";
          },
          {
            HorizontalScrollView,
            horizontalScrollBarEnabled=false,
            layout_width="match",
            {
              LinearLayout,
              layout_width="match",
              id="ps_bar",
            },
          },
        };
      };

      {
        LinearLayout;
        layout_gravity="start";
        orientation="vertical";
        layout_width="match_parent";
        layout_height="match_parent";
        id="head";
        {
          MyFileTabView,
          id="filetab",
          layout_width="match",
          layout_height="48dp",
          tabMode=LuaFileTabView.MODE_SCROLLABLE,
          selectedTabIndicatorHeight=0,
          inlineLabel=true,
          clipToPadding=false,
        },

        {
          NavigationView,
          layout_width="match_parent";
          layout_height="match_parent";
          {
            SwipeRefreshLayout;
            layout_gravity="start";
            layout_width="match_parent";
            layout_height="match_parent";
            id="swipeRefresh";
            ProgressBackgroundColorSchemeColor=ColorBackground,
            ColorSchemeColors={ColorUtil.getColorPrimary()},
            {
              RecyclerView,
              layout_width="match_parent",
              layout_height="match_parent",
              dividerHeight="0",
              id="mRecycler",
            },

          };
        },
      }
    };
  };
}