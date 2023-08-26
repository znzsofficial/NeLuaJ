import "android.widget.FrameLayout"
import "com.github.chrisbanes.photoview.PhotoView"
import "com.google.android.material.floatingactionbutton.FloatingActionButton"
import "res"

return {
  FrameLayout,
  id="bg",
  background=0xff000000,
  layout_width="-1",
  layout_height="-1",
  {
    PhotoView,
    layout_width = "-1",
    layout_height = "-1",
    id = "mPhotoView",
    Zoomable=true,
  },
  {
    FloatingActionButton,
    layout_width="-2",
    layout_height="-2",
    id="switchBg",
    layout_gravity="bottom|end",
    layout_marginEnd="16dp",
    layout_marginBottom="16dp",
  },
}