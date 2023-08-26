import "com.google.android.material.textview.MaterialTextView";
import "android.widget.LinearLayout";

return {
  LinearLayout,
  layout_width='match_parent';
  layout_height='wrap';
  gravity="center";
  orientation="vertical";
  {
    MaterialTextView;
    id="author";
    layout_gravity="center";
    layout_width="wrap";
    text="@智商封印official";
    textColor=ColorUtil.getColorPrimary();
    layout_height="wrap";
  };
};