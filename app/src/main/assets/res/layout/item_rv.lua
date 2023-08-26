import "android.widget.LinearLayout";
import "androidx.appcompat.widget.AppCompatImageView";
import "com.google.android.material.card.MaterialCardView";
import "com.google.android.material.textview.MaterialTextView";

local ColorBackground=ColorUtil.getColorBackground()

return {
  LinearLayout,
  layout_width='match_parent';
  layout_height='wrap';
  paddingTop='2dp';
  paddingBottom='2dp';
  paddingLeft='12dp';
  paddingRight='12dp';
  {
    MaterialCardView,
    radius="32dp",
    layout_width='fill';
    layout_height='wrap';
    strokeWidth="0dp",
    layout_margin="4dp",
    backgroundColor=ColorBackground,
    id="contents",
    {
      LinearLayout,
      Orientation=0,
      layout_width="fill",
      layout_height="wrap",
      gravity="start",
      id="linear",
      {
        AppCompatImageView,
        layout_marginTop="12dp",
        layout_marginBottom="12dp",
        layout_marginLeft="20dp",
        layout_width="28dp",
        layout_height="28dp",
        id="icon",
      },
      {
        MaterialTextView,
        textSize="16sp",
        singleLine=true,
        ellipsize="start",
        id="name",
        layout_marginLeft="8dp",
        layout_marginTop="16dp",
        layout_marginBottom="12dp",
        layout_marginLeft="8dp",
      },
    },
  },
}