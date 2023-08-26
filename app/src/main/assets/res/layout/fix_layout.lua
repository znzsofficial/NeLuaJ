import "android.widget.LinearLayout"
import "androidx.appcompat.widget.AppCompatTextView"
import "com.google.android.material.progressindicator.CircularProgressIndicator"

return {
  LinearLayout;
  orientation="vertical",
  gravity="center";
  layout_width="fill",
  layout_height="fill",
  {
    CircularProgressIndicator,
    Indeterminate=true,
    trackCornerRadius="2dp",
  },
  {
    AppCompatTextView;
    textSize="18sp";
    text="正在分析";
  };
};
