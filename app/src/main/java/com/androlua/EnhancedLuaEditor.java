package com.androlua;

import android.content.Context;

import com.myopicmobile.textwarrior.common.ColorScheme;

/**
 * LuaEditor 子类：在 TextWarrior ColorScheme 上暴露光标色。
 * {@link #setDark(boolean)} 会换整套 Light/Dark scheme，自定义色会记在字段里并在切换后重施。
 */
public class EnhancedLuaEditor extends LuaEditor {

    private Integer caretForeground;
    private Integer caretBackground;
    private Integer caretDisabled;

    public EnhancedLuaEditor(Context context) {
        super(context);
    }

    @Override
    public void setDark(boolean dark) {
        super.setDark(dark);
        reapplyCaretColors();
    }

    /** 光标（CARET_FOREGROUND） */
    public void setCaretColor(int color) {
        caretForeground = color;
        applyColor(ColorScheme.Colorable.CARET_FOREGROUND, color);
    }

    public int getCaretColor() {
        if (caretForeground != null) return caretForeground;
        return readColor(ColorScheme.Colorable.CARET_FOREGROUND);
    }

    /** 光标行背景（CARET_BACKGROUND） */
    public void setCaretBackgroundColor(int color) {
        caretBackground = color;
        applyColor(ColorScheme.Colorable.CARET_BACKGROUND, color);
    }

    public int getCaretBackgroundColor() {
        if (caretBackground != null) return caretBackground;
        return readColor(ColorScheme.Colorable.CARET_BACKGROUND);
    }

    /** 无焦点时的光标色（CARET_DISABLED） */
    public void setCaretDisabledColor(int color) {
        caretDisabled = color;
        applyColor(ColorScheme.Colorable.CARET_DISABLED, color);
    }

    public int getCaretDisabledColor() {
        if (caretDisabled != null) return caretDisabled;
        return readColor(ColorScheme.Colorable.CARET_DISABLED);
    }

    /**
     * 显示空白字符（空格 / Tab / 换行等），由 TextWarrior 绘制 NonPrinting 字形。
     * 颜色对应 ColorScheme.NON_PRINTING_GLYPH（与 setLineColor 同源）。
     */
    public void setShowWhitespace(boolean show) {
        setNonPrintingCharVisibility(show);
    }

    /** Tab 显示宽度（空格数），封装父类 {@link #setTabSpaces(int)} */
    public void setTabWidth(int spaces) {
        if (spaces < 1) spaces = 1;
        if (spaces > 16) spaces = 16;
        setTabSpaces(spaces);
    }

    private void reapplyCaretColors() {
        if (caretForeground != null) {
            applyColor(ColorScheme.Colorable.CARET_FOREGROUND, caretForeground);
        }
        if (caretBackground != null) {
            applyColor(ColorScheme.Colorable.CARET_BACKGROUND, caretBackground);
        }
        if (caretDisabled != null) {
            applyColor(ColorScheme.Colorable.CARET_DISABLED, caretDisabled);
        }
    }

    private void applyColor(ColorScheme.Colorable key, int color) {
        ColorScheme scheme = getColorScheme();
        if (scheme == null) return;
        scheme.setColor(key, color);
        invalidate();
    }

    private int readColor(ColorScheme.Colorable key) {
        ColorScheme scheme = getColorScheme();
        if (scheme == null) return 0;
        return scheme.getColor(key);
    }
}
