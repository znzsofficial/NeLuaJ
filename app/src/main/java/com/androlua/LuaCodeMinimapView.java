package com.androlua;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.os.Handler;
import android.os.Looper;
import android.util.AttributeSet;
import android.util.TypedValue;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;
import android.view.ViewTreeObserver;
import android.widget.FrameLayout;

import com.myopicmobile.textwarrior.android.FreeScrollingTextField;
import com.myopicmobile.textwarrior.common.DocumentProvider;

import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * VS Code-style code minimap for {@link LuaEditor} / TextWarrior.
 * Translucent viewport (no border), code bars always visible, pinch-to-zoom.
 */
public class LuaCodeMinimapView extends FrameLayout {

    public static class MinimapConfig {
        public float lineHeight = 2.2f;
        public float charWidthAscii = 1.05f;
        public float verticalGap = 0.6f;
        public float paddingLeft = 2f;

        /** Panel background; prefer translucent ARGB. */
        public int backgroundColor = 0x00000000;
        /** Viewport highlight fill; semi-transparent light blue by default. */
        public int maskColor = 0x282196F3;
        /** Dim outside viewport; 0 to disable. */
        public int outsideDimColor = 0x14000000;

        public int colorDefault;
        public int colorKeyword;
        public int colorString;
        public int colorComment;
        public int colorNumber;
        public int colorId;

        /** 0..255 applied to code bars. */
        public int codeAlpha = 200;

        public int tileHeightPx = 1024;
        public int maxTileCount = 8;
    }

    public interface JumpListener {
        void onJumpToLine(int line);
    }

    public interface ScaleListener {
        void onScaleChanged(float scale);
    }

    private static final int COLOR_IDX_DEFAULT = 0;
    private static final int COLOR_IDX_KEYWORD = 1;
    private static final int COLOR_IDX_STRING = 2;
    private static final int COLOR_IDX_COMMENT = 3;
    private static final int COLOR_IDX_NUMBER = 4;
    private static final int COLOR_IDX_ID = 5;
    private static final int COLOR_IDX_TRANSPARENT = 255;

    private static final float MIN_SCALE = 0.55f;
    private static final float MAX_SCALE = 2.8f;

    private final MinimapContent contentView;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService parseExecutor = Executors.newSingleThreadExecutor();
    private final AtomicInteger parseGeneration = new AtomicInteger();
    private final ScaleGestureDetector scaleDetector;

    private boolean configured;
    private FreeScrollingTextField boundEditor;
    private JumpListener jumpListener;
    private ScaleListener scaleListener;
    private ViewTreeObserver.OnScrollChangedListener scrollListener;
    private ViewTreeObserver.OnGlobalLayoutListener layoutListener;

    private MinimapConfig baseConfig;
    private float scale = 1f;

    private int lastScrollY = Integer.MIN_VALUE;
    private int lastEditorHeight;
    private boolean draggingMask;
    private boolean scaling;
    private float lastTouchY;
    private int activePointerId = MotionEvent.INVALID_POINTER_ID;

    private final Runnable deferredCodeRefresh = new Runnable() {
        @Override
        public void run() {
            if (boundEditor == null || !configured) return;
            setCode(readEditorText(boundEditor));
            syncVisibleRangeFromEditor(false);
        }
    };

    private final Runnable deferredScrollSync = new Runnable() {
        @Override
        public void run() {
            syncVisibleRangeFromEditor(true);
        }
    };

    public LuaCodeMinimapView(Context context) {
        this(context, null);
    }

    public LuaCodeMinimapView(Context context, AttributeSet attrs) {
        super(context, attrs);
        setWillNotDraw(false);
        setClickable(true);
        setFocusable(false);
        // Overlay on editor: host must stay fully transparent
        setBackgroundColor(Color.TRANSPARENT);
        setClipChildren(false);
        setClipToPadding(false);

        contentView = new MinimapContent(context);
        contentView.setBackgroundColor(Color.TRANSPARENT);
        addView(contentView, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT));

        scaleDetector = new ScaleGestureDetector(context, new ScaleGestureDetector.SimpleOnScaleGestureListener() {
            @Override
            public boolean onScaleBegin(ScaleGestureDetector detector) {
                scaling = true;
                draggingMask = false;
                getParent().requestDisallowInterceptTouchEvent(true);
                return true;
            }

            @Override
            public boolean onScale(ScaleGestureDetector detector) {
                float next = clampFloat(scale * detector.getScaleFactor(), MIN_SCALE, MAX_SCALE);
                if (Math.abs(next - scale) > 0.001f) {
                    setScale(next, true);
                }
                return true;
            }

            @Override
            public void onScaleEnd(ScaleGestureDetector detector) {
                scaling = false;
                if (scaleListener != null) scaleListener.onScaleChanged(scale);
                syncVisibleRangeFromEditor(false);
            }
        });
    }

    public void configure(MinimapConfig config) {
        if (config == null) return;
        baseConfig = copyConfig(config);
        // Allow translucent drawing over parent surface
        setBackgroundColor(Color.TRANSPARENT);
        setWillNotDraw(false);
        applyScaledConfig();
        configured = true;
    }

    public void setJumpListener(JumpListener listener) {
        this.jumpListener = listener;
    }

    public void setScaleListener(ScaleListener listener) {
        this.scaleListener = listener;
    }

    public float getScale() {
        return scale;
    }

    public void setScale(float newScale) {
        setScale(newScale, false);
    }

    public void setScale(float newScale, boolean fromGesture) {
        float next = clampFloat(newScale, MIN_SCALE, MAX_SCALE);
        if (!fromGesture && Math.abs(next - scale) < 0.001f && configured) {
            // still re-apply if first configure
        }
        float focusLine = contentView.getMaskCenterLine();
        scale = next;
        if (baseConfig != null) applyScaledConfig();
        contentView.scrollToKeepLineCentered(focusLine);
        if (!fromGesture && scaleListener != null) {
            // only notify for programmatic? skip to avoid loop; gesture notifies on end
        }
        invalidate();
    }

    private void applyScaledConfig() {
        if (baseConfig == null) return;
        MinimapConfig cfg = copyConfig(baseConfig);
        cfg.lineHeight = Math.max(1f, baseConfig.lineHeight * scale);
        cfg.charWidthAscii = Math.max(0.4f, baseConfig.charWidthAscii * scale);
        cfg.verticalGap = Math.max(0f, baseConfig.verticalGap * scale);
        // Keep host transparent; content draws translucent bg itself
        setBackgroundColor(Color.TRANSPARENT);
        contentView.applyConfig(cfg);
    }

    public void setCode(String code) {
        if (!configured) return;
        final int gen = parseGeneration.incrementAndGet();
        final String snapshot = code != null ? code : "";
        parseExecutor.execute(() -> {
            ParsedCode parsed = parseCodeOffThread(snapshot);
            mainHandler.post(() -> {
                if (gen != parseGeneration.get() || !configured) return;
                contentView.applyParsed(parsed);
            });
        });
    }

    public void setVisibleRange(int startLine, int endLine) {
        if (!configured) return;
        contentView.updateMaskRange(startLine, endLine);
        if (!draggingMask && !scaling) {
            autoScrollToCenter(startLine, endLine);
        }
    }

    public void attachToEditor(FreeScrollingTextField editor) {
        detachEditor();
        if (editor == null) return;
        boundEditor = editor;

        scrollListener = () -> {
            if (boundEditor == null) return;
            int sy = boundEditor.getScrollY();
            int h = boundEditor.getHeight();
            if (sy == lastScrollY && h == lastEditorHeight) return;
            lastScrollY = sy;
            lastEditorHeight = h;
            mainHandler.removeCallbacks(deferredScrollSync);
            mainHandler.post(deferredScrollSync);
        };

        layoutListener = () -> {
            mainHandler.removeCallbacks(deferredScrollSync);
            mainHandler.post(deferredScrollSync);
        };

        ViewTreeObserver obs = editor.getViewTreeObserver();
        if (obs.isAlive()) {
            obs.addOnScrollChangedListener(scrollListener);
            obs.addOnGlobalLayoutListener(layoutListener);
        }

        scheduleCodeRefresh(0);
        syncVisibleRangeFromEditor(false);
    }

    public void detachEditor() {
        mainHandler.removeCallbacks(deferredCodeRefresh);
        mainHandler.removeCallbacks(deferredScrollSync);
        if (boundEditor != null) {
            ViewTreeObserver obs = boundEditor.getViewTreeObserver();
            if (obs.isAlive()) {
                if (scrollListener != null) obs.removeOnScrollChangedListener(scrollListener);
                if (layoutListener != null) obs.removeOnGlobalLayoutListener(layoutListener);
            }
        }
        boundEditor = null;
        scrollListener = null;
        layoutListener = null;
        lastScrollY = Integer.MIN_VALUE;
    }

    public void scheduleCodeRefresh(long delayMs) {
        mainHandler.removeCallbacks(deferredCodeRefresh);
        mainHandler.postDelayed(deferredCodeRefresh, Math.max(0, delayMs));
    }

    public void syncVisibleRangeFromEditor(boolean smooth) {
        if (boundEditor == null || !configured) return;
        float editorRowH = estimateEditorRowHeight(boundEditor);
        if (editorRowH <= 0f) return;

        int scrollY = boundEditor.getScrollY();
        int viewH = Math.max(1, boundEditor.getHeight());
        int rowCount = 0;
        try {
            DocumentProvider doc = boundEditor.createDocumentProvider();
            if (doc != null) rowCount = Math.max(1, doc.getRowCount());
        } catch (Throwable ignored) {
        }
        if (rowCount <= 0) rowCount = Math.max(1, contentView.getLineCount());

        int start = (int) Math.floor(scrollY / editorRowH);
        int end = (int) Math.ceil((scrollY + viewH) / editorRowH) - 1;
        start = clamp(start, 0, rowCount - 1);
        end = clamp(end, start, rowCount - 1);

        contentView.updateMaskRange(start, end);
        if (!draggingMask && !scaling) {
            if (smooth) autoScrollToCenter(start, end);
            else jumpScrollToCenter(start, end);
        }
    }

    private static String readEditorText(FreeScrollingTextField editor) {
        try {
            if (editor instanceof LuaEditor) {
                CharSequence text = ((LuaEditor) editor).getText();
                return text != null ? text.toString() : "";
            }
            DocumentProvider doc = editor.createDocumentProvider();
            return doc != null ? doc.toString() : "";
        } catch (Throwable t) {
            return "";
        }
    }

    private static float estimateEditorRowHeight(FreeScrollingTextField editor) {
        try {
            int y0 = editor.getPaintBaseline(0);
            int y1 = editor.getPaintBaseline(1);
            if (y1 > y0) return y1 - y0;
        } catch (Throwable ignored) {
        }
        float size = editor.getTextSize();
        return size > 0 ? size * 1.35f : 40f;
    }

    private void autoScrollToCenter(int startLine, int endLine) {
        float totalLineH = contentView.getTotalLineHeight();
        if (totalLineH <= 0f || getHeight() <= 0) return;
        float maskCenterY = ((startLine + endLine + 1) * 0.5f) * totalLineH;
        int targetY = (int) (maskCenterY - getHeight() / 2f);
        contentView.scrollToY(Math.max(0, targetY));
    }

    private void jumpScrollToCenter(int startLine, int endLine) {
        autoScrollToCenter(startLine, endLine);
    }

    private void jumpEditorToMinimapY(float localY) {
        if (!configured) return;
        int line = contentView.lineAtY(localY + contentView.getScrollOffsetY());
        if (jumpListener != null) {
            jumpListener.onJumpToLine(line);
        } else if (boundEditor instanceof LuaEditor) {
            ((LuaEditor) boundEditor).gotoLine(line + 1);
        } else if (boundEditor != null) {
            try {
                DocumentProvider doc = boundEditor.createDocumentProvider();
                if (doc != null) {
                    int offset = doc.getRowOffset(clamp(line, 0, Math.max(0, doc.getRowCount() - 1)));
                    boundEditor.moveCaret(offset);
                    boundEditor.focusCaret();
                }
            } catch (Throwable ignored) {
            }
        }
        mainHandler.post(() -> syncVisibleRangeFromEditor(false));
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (!configured || !isEnabled()) return super.onTouchEvent(event);

        scaleDetector.onTouchEvent(event);
        if (scaling || event.getPointerCount() > 1) {
            draggingMask = false;
            return true;
        }

        int action = event.getActionMasked();
        switch (action) {
            case MotionEvent.ACTION_DOWN:
                activePointerId = event.getPointerId(0);
                draggingMask = true;
                lastTouchY = event.getY();
                jumpEditorToMinimapY(lastTouchY);
                getParent().requestDisallowInterceptTouchEvent(true);
                return true;
            case MotionEvent.ACTION_MOVE:
                if (!draggingMask) return true;
                int idx = event.findPointerIndex(activePointerId);
                if (idx < 0) return true;
                float y = event.getY(idx);
                if (Math.abs(y - lastTouchY) >= 1f) {
                    lastTouchY = y;
                    jumpEditorToMinimapY(y);
                }
                return true;
            case MotionEvent.ACTION_POINTER_UP: {
                int pid = event.getPointerId(event.getActionIndex());
                if (pid == activePointerId) {
                    int newIndex = event.getActionIndex() == 0 ? 1 : 0;
                    if (newIndex < event.getPointerCount()) {
                        activePointerId = event.getPointerId(newIndex);
                        lastTouchY = event.getY(newIndex);
                    }
                }
                return true;
            }
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                draggingMask = false;
                scaling = false;
                activePointerId = MotionEvent.INVALID_POINTER_ID;
                getParent().requestDisallowInterceptTouchEvent(false);
                return true;
            default:
                return true;
        }
    }

    @Override
    protected void onDetachedFromWindow() {
        detachEditor();
        parseGeneration.incrementAndGet();
        contentView.clearTileCache();
        super.onDetachedFromWindow();
    }

    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        super.onSizeChanged(w, h, oldw, oldh);
        if (w != oldw) contentView.clearTileCache();
        if (configured) syncVisibleRangeFromEditor(false);
    }

    private static int clamp(int v, int min, int max) {
        return Math.max(min, Math.min(max, v));
    }

    private static float clampFloat(float v, float min, float max) {
        return Math.max(min, Math.min(max, v));
    }

    private static MinimapConfig copyConfig(MinimapConfig src) {
        MinimapConfig c = new MinimapConfig();
        c.lineHeight = src.lineHeight;
        c.charWidthAscii = src.charWidthAscii;
        c.verticalGap = src.verticalGap;
        c.paddingLeft = src.paddingLeft;
        c.backgroundColor = src.backgroundColor;
        c.maskColor = src.maskColor;
        c.outsideDimColor = src.outsideDimColor;
        c.colorDefault = src.colorDefault;
        c.colorKeyword = src.colorKeyword;
        c.colorString = src.colorString;
        c.colorComment = src.colorComment;
        c.colorNumber = src.colorNumber;
        c.colorId = src.colorId;
        c.codeAlpha = src.codeAlpha;
        c.tileHeightPx = src.tileHeightPx;
        c.maxTileCount = src.maxTileCount;
        return c;
    }

    private static class ParsedCode {
        int[] data = new int[0];
        int dataSize;
        int[] lineEnds = new int[0];
        int lineCount;
    }

    private ParsedCode parseCodeOffThread(String code) {
        ParsedCode out = new ParsedCode();
        if (code == null || code.isEmpty()) return out;

        int[] data = new int[Math.max(4096, code.length() / 4)];
        int dataSize = 0;
        int[] lineEnds = new int[512];
        int lineCount = 0;

        int[] colorMap = contentView.copyTokenMap();
        int mapLen = colorMap.length;

        int currentBlockLen = 0;
        int lastColorIdx = -1;

        try {
            LuaLexer lexer = new LuaLexer(code);
            LuaTokenTypes token;
            while ((token = lexer.advance()) != null) {
                int ordinal = token.ordinal();
                int colorIdx = (ordinal < mapLen) ? colorMap[ordinal] : COLOR_IDX_DEFAULT;
                int textLen = lexer.yylength();
                if (textLen == 0) continue;
                String text = lexer.yytext();
                int crIndex = text.indexOf('\n');

                if (crIndex == -1) {
                    if (colorIdx == lastColorIdx) {
                        currentBlockLen = addLen(currentBlockLen, textLen);
                    } else {
                        if (currentBlockLen > 0) {
                            if (dataSize >= data.length) data = grow(data);
                            data[dataSize++] = packBlock(currentBlockLen, lastColorIdx);
                        }
                        lastColorIdx = colorIdx;
                        currentBlockLen = textLen;
                    }
                } else {
                    int start = 0;
                    while (crIndex != -1) {
                        int segLen = crIndex - start;
                        if (segLen > 0) {
                            if (colorIdx == lastColorIdx) {
                                currentBlockLen = addLen(currentBlockLen, segLen);
                            } else {
                                if (currentBlockLen > 0) {
                                    if (dataSize >= data.length) data = grow(data);
                                    data[dataSize++] = packBlock(currentBlockLen, lastColorIdx);
                                }
                                lastColorIdx = colorIdx;
                                currentBlockLen = segLen;
                            }
                        }
                        if (currentBlockLen > 0) {
                            if (dataSize >= data.length) data = grow(data);
                            data[dataSize++] = packBlock(currentBlockLen, lastColorIdx);
                            currentBlockLen = 0;
                        }
                        lastColorIdx = -1;
                        if (lineCount >= lineEnds.length) lineEnds = grow(lineEnds);
                        lineEnds[lineCount++] = dataSize;
                        start = crIndex + 1;
                        crIndex = text.indexOf('\n', start);
                    }
                    int remaining = textLen - start;
                    if (remaining > 0) {
                        lastColorIdx = colorIdx;
                        currentBlockLen = remaining;
                    }
                }
            }
            if (currentBlockLen > 0) {
                if (dataSize >= data.length) data = grow(data);
                data[dataSize++] = packBlock(currentBlockLen, lastColorIdx);
            }
            if (lineCount == 0 || lineEnds[lineCount - 1] != dataSize) {
                if (lineCount >= lineEnds.length) lineEnds = grow(lineEnds);
                lineEnds[lineCount++] = dataSize;
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

        out.data = data;
        out.dataSize = dataSize;
        out.lineEnds = lineEnds;
        out.lineCount = lineCount;
        return out;
    }

    private static int addLen(int a, int b) {
        long s = (long) a + b;
        return s > 0xFFFF ? 0xFFFF : (int) s;
    }

    private static int packBlock(int len, int colorIdx) {
        int safeLen = Math.min(0xFFFF, Math.max(0, len));
        return (safeLen << 16) | (colorIdx & 0xFF);
    }

    private static int[] grow(int[] arr) {
        return Arrays.copyOf(arr, arr.length + (arr.length >> 1) + 16);
    }

    private class MinimapContent extends View {
        private int[] mData = new int[0];
        private int mDataSize = 0;
        private int[] mLineEnds = new int[0];
        private int mLineCount = 0;

        private float pLineHeight = 2f;
        private float pCharWidthAscii = 1.05f;
        private float pTotalLineHeight = 2.6f;
        private float pPaddingLeft = 2f;
        private int pBackgroundColor = Color.TRANSPARENT;
        private int pOutsideDimColor = 0x14000000;
        private int pCodeAlpha = 200;

        private final Paint[] paintCache = new Paint[6];
        private final Paint maskPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint outsidePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Rect clipRect = new Rect();
        private final RectF maskRect = new RectF();

        private int[] tokenTypeToColorIdx = new int[0];
        private int tileHeightPx = 1024;
        private int maxTileCount = 8;
        private int scrollOffsetY = 0;

        private final LinkedHashMap<Integer, Bitmap> tileCache =
                new LinkedHashMap<Integer, Bitmap>(16, 0.75f, true) {
                    @Override
                    protected boolean removeEldestEntry(Map.Entry<Integer, Bitmap> eldest) {
                        if (size() > maxTileCount) {
                            Bitmap bmp = eldest.getValue();
                            if (bmp != null && !bmp.isRecycled()) bmp.recycle();
                            return true;
                        }
                        return false;
                    }
                };

        private int currentStartLine = 0;
        private int currentEndLine = 0;

        MinimapContent(Context context) {
            super(context);
            setWillNotDraw(false);
            setBackgroundColor(Color.TRANSPARENT);
            maskPaint.setStyle(Paint.Style.FILL);
            outsidePaint.setStyle(Paint.Style.FILL);
            for (int i = 0; i < 6; i++) {
                paintCache[i] = new Paint();
                paintCache[i].setStyle(Paint.Style.FILL);
                paintCache[i].setAntiAlias(false);
            }
            buildTokenMap();
        }

        void applyConfig(MinimapConfig config) {
            pLineHeight = Math.max(1f, config.lineHeight);
            pCharWidthAscii = Math.max(0.4f, config.charWidthAscii);
            pPaddingLeft = Math.max(0f, config.paddingLeft);
            pTotalLineHeight = pLineHeight + Math.max(0f, config.verticalGap);
            pBackgroundColor = config.backgroundColor;
            pOutsideDimColor = config.outsideDimColor;
            pCodeAlpha = clamp(config.codeAlpha, 0, 255);
            maskPaint.setColor(Color.argb(
                    Color.alpha(config.maskColor),
                    Color.red(config.maskColor),
                    Color.green(config.maskColor),
                    Color.blue(config.maskColor)));
            outsidePaint.setColor(Color.argb(
                    Color.alpha(config.outsideDimColor),
                    Color.red(config.outsideDimColor),
                    Color.green(config.outsideDimColor),
                    Color.blue(config.outsideDimColor)));

            applyBarColor(0, config.colorDefault);
            applyBarColor(1, config.colorKeyword);
            applyBarColor(2, config.colorString);
            applyBarColor(3, config.colorComment);
            applyBarColor(4, config.colorNumber);
            applyBarColor(5, config.colorId);

            if (config.tileHeightPx > 0) tileHeightPx = config.tileHeightPx;
            if (config.maxTileCount > 0) maxTileCount = config.maxTileCount;

            clearTileCache();
            requestLayout();
            invalidate();
        }

        private void applyBarColor(int idx, int color) {
            int a = pCodeAlpha;
            int r = Color.red(color);
            int g = Color.green(color);
            int b = Color.blue(color);
            int srcA = Color.alpha(color);
            if (srcA > 0 && srcA < 255) {
                a = (srcA * pCodeAlpha) / 255;
            }
            // Color.argb avoids long/int overload issues from packed ints
            paintCache[idx].setColor(Color.argb(a, r, g, b));
        }

        int[] copyTokenMap() {
            if (tokenTypeToColorIdx == null || tokenTypeToColorIdx.length == 0) buildTokenMap();
            return Arrays.copyOf(tokenTypeToColorIdx, tokenTypeToColorIdx.length);
        }

        private void buildTokenMap() {
            LuaTokenTypes[] values = LuaTokenTypes.values();
            tokenTypeToColorIdx = new int[values.length];
            Arrays.fill(tokenTypeToColorIdx, COLOR_IDX_DEFAULT);
            for (LuaTokenTypes t : values) {
                int idx = COLOR_IDX_DEFAULT;
                switch (t) {
                    case NAME:
                        idx = COLOR_IDX_ID;
                        break;
                    case STRING:
                    case LONG_STRING:
                        idx = COLOR_IDX_STRING;
                        break;
                    case NUMBER:
                        idx = COLOR_IDX_NUMBER;
                        break;
                    case BLOCK_COMMENT:
                    case SHORT_COMMENT:
                    case DOC_COMMENT:
                        idx = COLOR_IDX_COMMENT;
                        break;
                    case WHITE_SPACE:
                    case NEW_LINE:
                        idx = COLOR_IDX_TRANSPARENT;
                        break;
                    case AND:
                    case BREAK:
                    case DO:
                    case ELSE:
                    case ELSEIF:
                    case END:
                    case FALSE:
                    case FOR:
                    case FUNCTION:
                    case GOTO:
                    case IF:
                    case IN:
                    case LOCAL:
                    case NIL:
                    case NOT:
                    case OR:
                    case REPEAT:
                    case RETURN:
                    case THEN:
                    case TRUE:
                    case UNTIL:
                    case WHILE:
                    case LAMBDA:
                    case DEFER:
                    case SWITCH:
                    case CASE:
                    case DEFAULT:
                    case TRY:
                    case CATCH:
                    case FINALLY:
                    case CONTINUE:
                    case WHEN:
                        idx = COLOR_IDX_KEYWORD;
                        break;
                    default:
                        break;
                }
                tokenTypeToColorIdx[t.ordinal()] = idx;
            }
        }

        float getTotalLineHeight() {
            return pTotalLineHeight;
        }

        int getLineCount() {
            return mLineCount;
        }

        int getScrollOffsetY() {
            return scrollOffsetY;
        }

        float getMaskCenterLine() {
            return (currentStartLine + currentEndLine + 1) * 0.5f;
        }

        void scrollToKeepLineCentered(float line) {
            if (pTotalLineHeight <= 0f || getHeight() <= 0) return;
            float y = line * pTotalLineHeight;
            int targetY = (int) (y - getHeight() / 2f);
            scrollToY(Math.max(0, targetY));
        }

        int lineAtY(float contentY) {
            if (pTotalLineHeight <= 0f || mLineCount <= 0) return 0;
            int line = (int) (contentY / pTotalLineHeight);
            return clamp(line, 0, mLineCount - 1);
        }

        void applyParsed(ParsedCode parsed) {
            if (parsed == null) return;
            mData = parsed.data;
            mDataSize = parsed.dataSize;
            mLineEnds = parsed.lineEnds;
            mLineCount = parsed.lineCount;
            clearTileCache();
            requestLayout();
            invalidate();
        }

        void updateMaskRange(int startLine, int endLine) {
            currentStartLine = Math.max(0, startLine);
            currentEndLine = Math.max(currentStartLine, endLine);
            float top = currentStartLine * pTotalLineHeight;
            float bottom = (currentEndLine + 1) * pTotalLineHeight;
            maskRect.set(0, top, getWidth(), bottom);
            invalidate();
        }

        void scrollToY(int y) {
            int max = Math.max(0, contentHeight() - getHeight());
            int target = clamp(y, 0, max);
            if (target != scrollOffsetY) {
                scrollOffsetY = target;
                invalidate();
            }
        }

        private int contentHeight() {
            return (int) Math.min(Integer.MAX_VALUE, Math.ceil(mLineCount * (double) pTotalLineHeight));
        }

        @Override
        protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
            int w = MeasureSpec.getSize(widthMeasureSpec);
            int h = MeasureSpec.getSize(heightMeasureSpec);
            if (MeasureSpec.getMode(heightMeasureSpec) == MeasureSpec.UNSPECIFIED) {
                h = contentHeight();
            }
            setMeasuredDimension(w, h);
        }

        @Override
        protected void onDraw(Canvas c) {
            // 1) Panel background (keep very translucent)
            if (Color.alpha(pBackgroundColor) > 0) {
                c.drawColor(pBackgroundColor);
            }

            if (mLineCount == 0 || pTotalLineHeight <= 0f) return;
            maskRect.right = getWidth();
            c.getClipBounds(clipRect);

            float maskTop = maskRect.top - scrollOffsetY;
            float maskBottom = maskRect.bottom - scrollOffsetY;
            int w = getWidth();
            int h = getHeight();

            // 2) Viewport / outside dim UNDER code bars so bars are never covered
            if (Color.alpha(pOutsideDimColor) > 0) {
                if (maskTop > 0) {
                    c.drawRect(0, 0, w, Math.min(h, maskTop), outsidePaint);
                }
                if (maskBottom < h) {
                    c.drawRect(0, Math.max(0, maskBottom), w, h, outsidePaint);
                }
            }
            if (maskBottom > maskTop && Color.alpha(maskPaint.getColor()) > 0) {
                c.drawRect(0, maskTop, w, maskBottom, maskPaint);
            }

            // 3) Code bars on top (always fully visible)
            int contentTop = scrollOffsetY + clipRect.top;
            int contentBottom = scrollOffsetY + clipRect.bottom;
            int tH = tileHeightPx;
            int tileTopIndex = Math.max(0, contentTop / tH);
            int tileBottomIndex = Math.max(0, (Math.max(contentBottom, contentTop + 1) - 1) / tH);

            for (int ti = tileTopIndex; ti <= tileBottomIndex; ti++) {
                Bitmap tile = tileCache.get(ti);
                if (tile == null || tile.isRecycled()) {
                    tile = createTileBitmap(ti);
                    if (tile != null) tileCache.put(ti, tile);
                }
                if (tile != null && !tile.isRecycled()) {
                    c.drawBitmap(tile, 0, ti * tH - scrollOffsetY, null);
                }
            }
        }

        private Bitmap createTileBitmap(int tileIndex) {
            int tileTopPx = tileIndex * tileHeightPx;
            long totalContentHeight = contentHeight();
            if (tileTopPx >= totalContentHeight) return null;

            int tileBottomPx = (int) Math.min(totalContentHeight, tileTopPx + tileHeightPx);
            int w = Math.max(1, getWidth());
            int h = tileBottomPx - tileTopPx;
            if (h <= 0) return null;

            try {
                // ARGB for transparency (bars float on translucent bg)
                Bitmap bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
                Canvas cc = new Canvas(bmp);
                cc.drawColor(Color.TRANSPARENT);

                float totalLH = pTotalLineHeight;
                int firstLine = (int) (tileTopPx / totalLH);
                int lastLine = (int) Math.ceil(tileBottomPx / (double) totalLH);
                firstLine = Math.max(0, firstLine);
                lastLine = Math.min(mLineCount, lastLine);

                float lh = Math.max(1f, pLineHeight);
                float ascW = pCharWidthAscii;
                float padL = pPaddingLeft;
                int[] dataRef = mData;
                int[] endsRef = mLineEnds;
                Paint[] paintsRef = paintCache;
                int transparent = COLOR_IDX_TRANSPARENT;
                float maxX = w;

                for (int i = firstLine; i < lastLine; i++) {
                    float y = (i * totalLH) - tileTopPx;
                    float x = padL;
                    int startIdx = (i == 0) ? 0 : endsRef[i - 1];
                    int endIdx = endsRef[i];
                    for (int k = startIdx; k < endIdx; k++) {
                        if (x >= maxX) break;
                        int val = dataRef[k];
                        int len = val >>> 16;
                        int colorIdx = val & 0xFF;
                        float width = len * ascW;
                        if (colorIdx != transparent && colorIdx < paintsRef.length) {
                            float right = Math.min(maxX, x + width);
                            if (right > x) {
                                cc.drawRect(x, y, right, y + lh, paintsRef[colorIdx]);
                            }
                        }
                        x += width;
                    }
                }
                return bmp;
            } catch (OutOfMemoryError e) {
                clearTileCache();
                return null;
            } catch (Exception e) {
                return null;
            }
        }

        void clearTileCache() {
            try {
                for (Bitmap b : tileCache.values()) {
                    if (b != null && !b.isRecycled()) b.recycle();
                }
                tileCache.clear();
            } catch (Exception ignored) {
            }
        }

        @Override
        protected void onDetachedFromWindow() {
            super.onDetachedFromWindow();
            clearTileCache();
        }
    }
}
