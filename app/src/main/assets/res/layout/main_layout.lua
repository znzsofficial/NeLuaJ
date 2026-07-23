import "com.androlua.LuaEditor";
import "com.androlua.LuaCodeMinimapView";
import "android.widget.LinearLayout";
import "android.widget.FrameLayout";
import "android.widget.HorizontalScrollView";
import "androidx.appcompat.widget.AppCompatImageView"
import "androidx.appcompat.widget.AppCompatEditText"
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
import "com.google.android.material.textview.MaterialTextView"
import "com.google.android.material.button.MaterialButton"
import "github.daisukiKaffuChino.LuaFileTabView"
import "android.view.View"
--import "vinx.material.textfield.MaterialTextField"

local ColorUtil = this.themeUtil

local rippleRes = activity.obtainStyledAttributes({ android.R.attr.selectableItemBackgroundBorderless }).getResourceId(0, 0)

local ColorBackground = ColorUtil.getColorBackground()
local ColorPrimary = ColorUtil.getColorPrimary()
local ColorOnSurfaceVar = ColorUtil.getColorOnSurfaceVariant()
local ColorOnSurface = ColorUtil.getColorOnSurface()
local ColorPrimaryContainer = ColorUtil.getColorPrimaryContainer()
local ColorOnPrimaryContainer = ColorUtil.getColorOnPrimaryContainer()
local ColorError = ColorUtil.getColorError()

local function fileIcon(id, drawableName, tint, desc)
  return {
    AppCompatImageView,
    id = id,
    layout_width = "40dp",
    layout_height = "40dp",
    padding = "8dp",
    src = res.drawable(drawableName, tint),
    BackgroundResource = rippleRes,
    clickable = true,
    longClickable = true,
    focusable = true,
    contentDescription = desc,
  }
end

return {
  CoordinatorLayout;
  layout_height = "match";
  layout_width = "match";
  id = "coordinatorLayout";
  {
    LinearLayout;
    gravity = "center";
    layout_height = "fill";
    layout_width = "fill";
    orientation = "vertical";
    {
      AppBarLayout;
      layout_height = "wrap";
      layout_width = "match";
      id = "appBar",
      {
        MaterialToolbar;
        layout_height = "64dp";
        layout_width = "match";
        BackgroundColor = ColorBackground,
        id = "mToolBar";
      };
      {
        MaterialCardView,
        id = "mSearch";
        radius = "20dp",
        strokeWidth = "0dp",
        layout_width = "match",
        layout_height = "wrap",
        layout_marginLeft = "10dp",
        layout_marginRight = "10dp",
        layout_marginBottom = "6dp",
        CardBackgroundColor = ColorUtil.getColorSurfaceVariant(),
        {
          LinearLayout,
          layout_width = "match",
          layout_height = "wrap",
          orientation = "vertical",
          paddingLeft = "10dp",
          paddingRight = "6dp",
          paddingTop = "8dp",
          paddingBottom = "8dp",
          -- 查找行
          {
            LinearLayout,
            layout_width = "match",
            layout_height = "40dp",
            orientation = "horizontal",
            gravity = "center_vertical",
            {
              AppCompatImageView,
              layout_width = "22dp",
              layout_height = "22dp",
              layout_marginRight = "6dp",
              src = res.drawable("search", ColorUtil.getColorOnSurfaceVariant()),
            },
            {
              AppCompatEditText,
              id = "mSearchEdit",
              layout_width = "0dp",
              layout_height = "match",
              layout_weight = 1,
              background = 0,
              singleLine = true,
              textSize = "15sp",
              hint = res.string.search_hint,
              TintColor = ColorUtil.getColorPrimary(),
              imeOptions = "actionSearch",
            },
            {
              MaterialTextView,
              id = "search_count",
              layout_width = "wrap",
              layout_height = "wrap",
              layout_marginLeft = "4dp",
              layout_marginRight = "4dp",
              textSize = "12sp",
              text = "0/0",
              textColor = ColorUtil.getColorOnSurfaceVariant(),
            },
            {
              AppCompatImageView,
              id = "search_clear",
              layout_width = "36dp",
              layout_height = "36dp",
              padding = "7dp",
              src = res.drawable("clear", ColorUtil.getColorOnSurfaceVariant()),
              BackgroundResource = rippleRes,
              clickable = true,
            },
            {
              AppCompatImageView,
              id = "search_up",
              layout_width = "36dp",
              layout_height = "36dp",
              padding = "7dp",
              src = res.drawable("s_up", ColorUtil.getColorOnSurface()),
              BackgroundResource = rippleRes,
              clickable = true,
            },
            {
              AppCompatImageView,
              id = "search_down",
              layout_width = "36dp",
              layout_height = "36dp",
              padding = "7dp",
              src = res.drawable("s_down", ColorUtil.getColorOnSurface()),
              BackgroundResource = rippleRes,
              clickable = true,
            },
            {
              AppCompatImageView,
              id = "search_close",
              layout_width = "36dp",
              layout_height = "36dp",
              padding = "7dp",
              src = res.drawable("close", ColorUtil.getColorOnSurface()),
              BackgroundResource = rippleRes,
              clickable = true,
            },
          },
          -- 替换行（默认隐藏，展开后显示）
          {
            LinearLayout,
            id = "search_replace_row",
            layout_width = "match",
            layout_height = "wrap",
            minHeight = "44dp",
            orientation = "horizontal",
            gravity = "center_vertical",
            visibility = 8,
            {
              AppCompatImageView,
              layout_width = "22dp",
              layout_height = "22dp",
              layout_marginRight = "6dp",
              src = res.drawable("replace", ColorUtil.getColorOnSurfaceVariant()),
            },
            {
              AppCompatEditText,
              id = "mReplaceEdit",
              layout_width = "0dp",
              layout_height = "wrap",
              layout_weight = 1,
              minHeight = "40dp",
              background = 0,
              singleLine = true,
              textSize = "15sp",
              hint = res.string.replace_hint,
              TintColor = ColorUtil.getColorPrimary(),
            },
            {
              MaterialButton,
              id = "search_replace_one",
              layout_width = "wrap",
              layout_height = "40dp",
              minHeight = "40dp",
              text = res.string.replace,
              textSize = "12sp",
              paddingLeft = "12dp",
              paddingRight = "12dp",
              insetTop = 0,
              insetBottom = 0,
            },
            {
              MaterialButton,
              id = "search_replace_all",
              layout_width = "wrap",
              layout_height = "40dp",
              minHeight = "40dp",
              layout_marginLeft = "4dp",
              text = res.string.replace_all,
              textSize = "12sp",
              paddingLeft = "12dp",
              paddingRight = "12dp",
              insetTop = 0,
              insetBottom = 0,
            },
          },
          -- 选项行
          {
            LinearLayout,
            layout_width = "match",
            layout_height = "wrap",
            orientation = "horizontal",
            gravity = "center_vertical",
            layout_marginTop = "4dp",
            {
              MaterialButton,
              id = "search_toggle_replace",
              layout_width = "wrap",
              layout_height = "36dp",
              minHeight = "36dp",
              text = res.string.replace,
              textSize = "12sp",
              paddingLeft = "10dp",
              paddingRight = "10dp",
              insetTop = 0,
              insetBottom = 0,
            },
            {
              MaterialButton,
              id = "search_opt_case",
              layout_width = "wrap",
              layout_height = "36dp",
              minHeight = "36dp",
              layout_marginLeft = "4dp",
              text = res.string.search_match_case,
              textSize = "12sp",
              paddingLeft = "10dp",
              paddingRight = "10dp",
              insetTop = 0,
              insetBottom = 0,
            },
            {
              MaterialButton,
              id = "search_opt_word",
              layout_width = "wrap",
              layout_height = "36dp",
              minHeight = "36dp",
              layout_marginLeft = "4dp",
              text = res.string.search_whole_word,
              textSize = "12sp",
              paddingLeft = "10dp",
              paddingRight = "10dp",
              insetTop = 0,
              insetBottom = 0,
            },
          },
        },
      },
      {
        HorizontalScrollView,
        horizontalScrollBarEnabled = false,
        layout_width = "match",
        {
          LinearLayout,
          layout_width="match",
          id="mFunctionTab",
        },
      },
      {
        TabLayout,
        id = "mTab",
        layout_height = "36dp",
        layout_width = "match",
        TabMode = 0,
        BackgroundColor = ColorBackground,
        Elevation = "0dp",
      };
      {
        MaterialDivider,
        layout_width = "fill",
        layout_height = "1dp";
      },
    };
    {
      DrawerLayout;
      id = "drawer";
      layout_height = "match_parent";
      layout_width = "match_parent";
      {
        -- 主内容：手机=全宽编辑区；平板=左侧 side_host 插文件栏 + 右侧编辑区
        LinearLayout;
        layout_height = "fill";
        layout_width = "fill";
        orientation = "horizontal";
        id = "workspace";
        {
          FrameLayout;
          id = "side_host";
          layout_width = "0dp";
          layout_height = "fill";
          visibility = 8;
        };
        {
          LinearLayout;
          gravity = "center";
          layout_height = "fill";
          layout_width = "0dp";
          layout_weight = 1;
          orientation = "vertical";
          id = "editor_content";
          {
            HorizontalScrollView,
            horizontalScrollBarEnabled = false,
            layout_width = "match",
            visibility = 8,
            id = "select_hint_scroll",
            {
              LinearLayout,
              layout_width = "match",
              id = "select_hint_bar",
            },
          },
          {
            FrameLayout,
            layout_width = "match",
            layout_height = "fill",
            layout_weight = 1,
            {
              LuaEditor;
              layout_height = "fill";
              layout_width = "fill";
              id = "mLuaEditor";
            };
            {
              LinearLayout;
              id = "editor_empty_state";
              layout_width = "match";
              layout_height = "match";
              orientation = "vertical";
              gravity = "center";
              clickable = true;
              focusable = true;
              {
                MaterialTextView,
                layout_width = "wrap",
                layout_height = "wrap",
                text = res.string.no_file,
                textSize = "16sp",
                gravity = "center",
                layout_marginBottom = "16dp",
              };
              {
                MaterialButton,
                id = "open_drawer_btn";
                layout_width = "wrap";
                layout_height = "wrap";
                text = res.string.open_file_drawer,
              };
            };
            {
              MaterialDivider,
              layout_width = "1dp",
              layout_height = "fill",
              layout_gravity = "end",
              layout_marginRight = "52dp",
              id = "minimap_divider",
              visibility = 8,
            },
            {
              LuaCodeMinimapView,
              layout_width = "52dp",
              layout_height = "fill",
              layout_gravity = "end",
              id = "mCodeMinimap",
              visibility = 8,
            };
          };

          {
            MaterialDivider,
            layout_width = "fill",
            layout_height = "1dp";
          },
          {
            LinearLayout,
            visibility = 8,
            backgroundColor = ColorUtil.getColorSurface(),
            layout_width = "match",
            layout_height = "wrap",
            {
              MaterialTextView,
              id = "error_Text",
              layout_width = "match",
              layout_height = "wrap",
            }
          },
          {
            HorizontalScrollView,
            horizontalScrollBarEnabled = false,
            layout_width = "match",
            {
              LinearLayout,
              layout_width = "match",
              id = "ps_bar",
            },
          },
        };
      };

      {
        -- 手机：抽屉面板；平板：reparent 到 side_host
        LinearLayout;
        backgroundColor = ColorBackground;
        layout_gravity = "start";
        orientation = "horizontal";
        layout_width = "280dp";
        layout_height = "match_parent";
        id = "head";
        {
          LinearLayout;
          orientation = "vertical";
          layout_width = "0dp";
          layout_height = "match";
          layout_weight = 1;
          -- 常态：工程 / 新建 · 粘贴(有剪贴板) / 多选
          {
            LinearLayout,
            id = "fileNormalBar",
            orientation = "horizontal",
            layout_width = "match",
            layout_height = "44dp",
            gravity = "center_vertical",
            paddingLeft = "2dp",
            paddingRight = "2dp",
            fileIcon("btnFileHome", "android_studio", ColorPrimary, res.string.file_at_project),
            fileIcon("btnFileNewFile", "new_file", ColorPrimary, res.string.new_file),
            fileIcon("btnFileNewDir", "new_folder", ColorPrimary, res.string.new_dir),
            {
              View,
              layout_width = "0dp",
              layout_height = "1dp",
              layout_weight = 1,
            },
            fileIcon("btnFilePaste", "ic_paste", ColorPrimary, res.string.file_paste),
            {
              MaterialTextView,
              id = "btnFileSelect",
              layout_width = "wrap",
              layout_height = "40dp",
              gravity = "center",
              paddingLeft = "12dp",
              paddingRight = "12dp",
              textSize = "13sp",
              text = res.string.media_select,
              textColor = ColorPrimary,
              BackgroundResource = rippleRes,
              clickable = true,
              longClickable = true,
              focusable = true,
              contentDescription = res.string.media_select,
            },
          },
          -- 多选栏：取消 / 全选 · 复制 / 剪切 / 删除（粘贴在常态栏）
          {
            LinearLayout,
            id = "fileSelectBar",
            orientation = "horizontal",
            layout_width = "match",
            layout_height = "44dp",
            gravity = "center_vertical",
            paddingLeft = "2dp",
            paddingRight = "2dp",
            BackgroundColor = ColorPrimaryContainer,
            visibility = 8, -- GONE
            fileIcon("btnFileCancelSel", "close", ColorOnPrimaryContainer, res.string.media_cancel_select),
            fileIcon("btnFileSelectAll", "ic_select_all", ColorOnPrimaryContainer, res.string.media_select_all),
            {
              View,
              layout_width = "0dp",
              layout_height = "1dp",
              layout_weight = 1,
            },
            fileIcon("btnFileCopy", "ic_copy", ColorOnPrimaryContainer, res.string.copy),
            fileIcon("btnFileCut", "ic_cut", ColorOnPrimaryContainer, res.string.file_cut),
            fileIcon("btnFileDeleteSel", "delete", ColorError, res.string.delete),
          },
          -- 面包屑
          {
            LuaFileTabView,
            id = "filetab",
            layout_width = "match",
            layout_height = "40dp",
            tabMode = 0,
            selectedTabIndicatorHeight = 0,
            inlineLabel = true,
            clipToPadding = false,
          },
          {
            SwipeRefreshLayout;
            layout_width = "match_parent";
            layout_height = "0dp";
            layout_weight = 1;
            id = "swipeRefresh";
            ProgressBackgroundColorSchemeColor = ColorBackground,
            ColorSchemeColors = { ColorUtil.getColorPrimary() },
            {
              RecyclerView,
              layout_width = "match_parent",
              layout_height = "match_parent",
              id = "mRecycler",
            },
          };
        };
        {
          MaterialDivider,
          id = "side_divider",
          layout_width = "1dp",
          layout_height = "fill",
          visibility = 8,
        };
      }
    };
  };
}
