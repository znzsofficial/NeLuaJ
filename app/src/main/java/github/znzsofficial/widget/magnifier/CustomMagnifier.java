package github.znzsofficial.widget.magnifier;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Matrix;
import android.util.DisplayMetrics;
import android.util.TypedValue;
import android.view.TextureView;
import android.graphics.SurfaceTexture;
import android.graphics.Canvas;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import androidx.appcompat.widget.AppCompatImageView;
import androidx.cardview.widget.CardView;

public class CustomMagnifier {
  private float imageHeight;
  private float imageWidth;
  private float lastSourceCenterX;
  private float lastSourceCenterY;
  private CardView mCardView;
  private Activity mContext;
  private FrameLayout mDecorView;
  private DisplayMetrics displayMetrics;
  private AppCompatImageView mImageView;
  private Bitmap mLastBitmap;
  private View mView;
  private Matrix matrix = new Matrix();
  private float mZoom = 1.25F;
  private float verticalOffset;
  private int cornerRadius = 16;
  private float mElevation = 4.0F;

  public CustomMagnifier(View view) {
    mView = view;
    mContext = (Activity) view.getContext();
    displayMetrics = mContext.getResources().getDisplayMetrics();
    mCardView = new CardView(this.mContext);
    mImageView = new AppCompatImageView(this.mContext);
    mCardView.addView(mImageView);
    mCardView.setVisibility(View.GONE);
    // 设置卡片圆角
    mCardView.setRadius(cornerRadius);
    mCardView.setCardElevation(
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, mElevation, displayMetrics));
    FrameLayout decorView = (FrameLayout) this.mContext.getWindow().getDecorView();
    this.mDecorView = decorView;
    decorView.addView(this.mCardView);
    this.imageWidth =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 100.0F, displayMetrics);
    this.imageHeight =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 48.0F, displayMetrics);
    this.verticalOffset =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, -42.0F, displayMetrics);
    ViewGroup.LayoutParams layoutParams = this.mCardView.getLayoutParams();
    layoutParams.width = (int) this.imageWidth;
    layoutParams.height = (int) this.imageHeight;
    this.mCardView.setLayoutParams(layoutParams);
  }

  private Bitmap cropBitmap(Bitmap bitmap, int x, int y, int width, int height) {
    float scale = this.mZoom;
    matrix.setScale(scale, scale);
    if (x < 0) {
      x = 0;
    } else if (x > bitmap.getWidth() - width) {
      x = bitmap.getWidth() - width;
    }
    if (y < 0) {
      y = 0;
    } else if (y > bitmap.getHeight() - height) {
      y = bitmap.getHeight() - height;
    }
    Bitmap croppedBitmap = Bitmap.createBitmap(bitmap, x, y, width, height, matrix, true);
    bitmap.recycle();
    return croppedBitmap;
  }

  public void dismiss() {
    this.mCardView.setVisibility(View.GONE);
    Bitmap bitmap = this.mLastBitmap;
    if (bitmap != null) {
      bitmap.recycle();
    }
  }

  public float getZoom() {
    return this.mZoom;
  }

  public void setZoom(float zoom) {
    this.mZoom = zoom;
  }

  public void setDimensions(float width, float height) {
    this.imageWidth = width;
    this.imageHeight = height;
    ViewGroup.LayoutParams layoutParams = this.mCardView.getLayoutParams();
    layoutParams.width = (int) this.imageWidth;
    layoutParams.height = (int) this.imageHeight;
    this.mCardView.setLayoutParams(layoutParams);
  }

  public void setCornerRadius(int radius) {
    this.cornerRadius = radius;
    this.mCardView.setRadius(cornerRadius);
  }

  public void show(float sourceX, float sourceY) {
    this.show(sourceX, sourceY, sourceX, this.verticalOffset + sourceY);
  }

  public void show(float sourceX, float sourceY, float destinationX, float destinationY) {
    this.lastSourceCenterX = sourceX;
    this.lastSourceCenterY = sourceY;
    int[] location = new int[2];
    this.mView.getLocationInWindow(location);
    int viewX = location[0];
    int viewY = location[1];
    int decorViewWidth = this.mDecorView.getMeasuredWidth();
    int decorViewHeight = this.mDecorView.getMeasuredHeight();
    float x = (float) viewX;
    float cardWidth = this.imageWidth;
    float cardX = x + destinationX - cardWidth / 2.0F;
    float y = (float) viewY + destinationY - this.imageHeight / 2.0F;
    if (cardX < 0.0F) {
      this.mCardView.setX(0.0F);
    } else {
      float rightBoundary = (float) decorViewWidth;
      if (cardX > rightBoundary - cardWidth) {
        this.mCardView.setX(rightBoundary - cardWidth);
      } else {
        this.mCardView.setX(cardX);
      }
    }
    if (y < 0.0F) {
      this.mCardView.setY(0.0F);
    } else {
      float bottomBoundary = (float) decorViewHeight;
      float cardHeight = this.imageHeight;
      if (y > bottomBoundary - cardHeight) {
        this.mCardView.setY(bottomBoundary - cardHeight);
      } else {
        this.mCardView.setY(y);
      }
    }
    this.mCardView.setVisibility(View.VISIBLE);
    this.update();
  }

  public void update() {
    this.mView.setDrawingCacheEnabled(true);
    Bitmap viewBitmap = this.mView.getDrawingCache().copy(Bitmap.Config.ARGB_8888, true);
    this.mView.setDrawingCacheEnabled(false);
    float width = this.imageWidth;
    float zoom = this.mZoom;
    width /= zoom;
    zoom = this.imageHeight / zoom;
    Bitmap lastBitmap = this.mLastBitmap;
    if (lastBitmap != null) {
      lastBitmap.recycle();
    }
    Bitmap croppedBitmap =
        this.cropBitmap(
            viewBitmap,
            (int) (this.lastSourceCenterX - width / 2.0F),
            (int) (this.lastSourceCenterY - zoom / 2.0F),
            (int) width,
            (int) zoom);
    this.mLastBitmap = croppedBitmap;
    this.mImageView.setImageBitmap(croppedBitmap);
  }

  public float getElevation() {
    return this.mElevation;
  }

  public void setElevation(float elevation) {
    this.mElevation = elevation;
    this.mCardView.setCardElevation(
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, elevation, displayMetrics));
  }
}