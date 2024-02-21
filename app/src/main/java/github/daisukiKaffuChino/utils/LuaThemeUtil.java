package github.daisukiKaffuChino.utils;

import android.content.Context;
import android.util.TypedValue;

import com.google.android.material.color.MaterialColors;

public class LuaThemeUtil {
    Context context;
    TypedValue typedValue;

    public LuaThemeUtil(Context context) {
        this.typedValue = new TypedValue();
        this.context = context;
    }

    public int getColorPrimary() {
        context.getTheme().resolveAttribute(androidx.appcompat.R.attr.colorPrimary, typedValue, true);
        return typedValue.data;
    }

    public int getColorOnPrimary() {
        context
                .getTheme()
                .resolveAttribute(com.google.android.material.R.attr.colorOnPrimary, typedValue, true);
        return typedValue.data;
    }

    public int getColorPrimaryDark() {
        context
                .getTheme()
                .resolveAttribute(androidx.appcompat.R.attr.colorPrimaryDark, typedValue, true);
        return typedValue.data;
    }

    public int getColorPrimaryVariant() {
        context
                .getTheme()
                .resolveAttribute(com.google.android.material.R.attr.colorPrimaryVariant, typedValue, true);
        return typedValue.data;
    }

    public int getColorPrimaryContainer() {
        context
                .getTheme()
                .resolveAttribute(
                        com.google.android.material.R.attr.colorPrimaryContainer, typedValue, true);
        return typedValue.data;
    }

    public int getColorOnPrimaryContainer() {
        context
                .getTheme()
                .resolveAttribute(
                        com.google.android.material.R.attr.colorOnPrimaryContainer, typedValue, true);
        return typedValue.data;
    }

    public int getColorPrimaryInverse() {
        context
                .getTheme()
                .resolveAttribute(com.google.android.material.R.attr.colorPrimaryInverse, typedValue, true);
        return typedValue.data;
    }

    public int getColorPrimarySurface() {
        context
                .getTheme()
                .resolveAttribute(com.google.android.material.R.attr.colorPrimarySurface, typedValue, true);
        return typedValue.data;
    }

    public int getColorAccent() {
        context.getTheme().resolveAttribute(androidx.appcompat.R.attr.colorAccent, typedValue, true);
        return typedValue.data;
    }

    public int getColorSecondary() {
        context
                .getTheme()
                .resolveAttribute(com.google.android.material.R.attr.colorSecondary, typedValue, true);
        return typedValue.data;
    }

    public int getColorOnSecondary() {
        context
                .getTheme()
                .resolveAttribute(com.google.android.material.R.attr.colorOnSecondary, typedValue, true);
        return typedValue.data;
    }

    public int getColorSecondaryVariant() {
        context
                .getTheme()
                .resolveAttribute(
                        com.google.android.material.R.attr.colorSecondaryVariant, typedValue, true);
        return typedValue.data;
    }

    public int getColorSecondaryContainer() {
        context
                .getTheme()
                .resolveAttribute(
                        com.google.android.material.R.attr.colorSecondaryContainer, typedValue, true);
        return typedValue.data;
    }

    public int getColorOnSecondaryContainer() {
        context
                .getTheme()
                .resolveAttribute(
                        com.google.android.material.R.attr.colorOnSecondaryContainer, typedValue, true);
        return typedValue.data;
    }

    public int getColorTertiary() {
        context
                .getTheme()
                .resolveAttribute(com.google.android.material.R.attr.colorTertiary, typedValue, true);
        return typedValue.data;
    }

    public int getColorOnTertiary() {
        context
                .getTheme()
                .resolveAttribute(com.google.android.material.R.attr.colorOnTertiary, typedValue, true);
        return typedValue.data;
    }

    public int getColorTertiaryContainer() {
        context
                .getTheme()
                .resolveAttribute(
                        com.google.android.material.R.attr.colorTertiaryContainer, typedValue, true);
        return typedValue.data;
    }

    public int getColorOnTertiaryContainer() {
        context
                .getTheme()
                .resolveAttribute(
                        com.google.android.material.R.attr.colorOnTertiaryContainer, typedValue, true);
        return typedValue.data;
    }

    public int getColorError() {
        context.getTheme().resolveAttribute(androidx.appcompat.R.attr.colorError, typedValue, true);
        return typedValue.data;
    }

    public int getColorOnError() {
        context
                .getTheme()
                .resolveAttribute(com.google.android.material.R.attr.colorOnError, typedValue, true);
        return typedValue.data;
    }

    public int getColorErrorContainer() {
        context
                .getTheme()
                .resolveAttribute(com.google.android.material.R.attr.colorErrorContainer, typedValue, true);
        return typedValue.data;
    }

    public int getColorOnErrorContainer() {
        context
                .getTheme()
                .resolveAttribute(
                        com.google.android.material.R.attr.colorOnErrorContainer, typedValue, true);
        return typedValue.data;
    }

    public int getColorSurface() {
        context
                .getTheme()
                .resolveAttribute(com.google.android.material.R.attr.colorSurface, typedValue, true);
        return typedValue.data;
    }

    public int getColorSurfaceInverse() {
        context
                .getTheme()
                .resolveAttribute(com.google.android.material.R.attr.colorSurfaceInverse, typedValue, true);
        return typedValue.data;
    }

    public int getColorSurfaceVariant() {
        context
                .getTheme()
                .resolveAttribute(com.google.android.material.R.attr.colorSurfaceVariant, typedValue, true);
        return typedValue.data;
    }

    public int getColorOnSurface() {
        context
                .getTheme()
                .resolveAttribute(com.google.android.material.R.attr.colorOnSurface, typedValue, true);
        return typedValue.data;
    }

    public int getColorOnSurfaceInverse() {
        context
                .getTheme()
                .resolveAttribute(
                        com.google.android.material.R.attr.colorOnSurfaceInverse, typedValue, true);
        return typedValue.data;
    }

    public int getColorOnSurfaceVariant() {
        context
                .getTheme()
                .resolveAttribute(
                        com.google.android.material.R.attr.colorOnSurfaceVariant, typedValue, true);
        return typedValue.data;
    }

    public int getColorOnPrimarySurface() {
        context
                .getTheme()
                .resolveAttribute(
                        com.google.android.material.R.attr.colorOnPrimarySurface, typedValue, true);
        return typedValue.data;
    }

    public int getColorOutline() {
        context
                .getTheme()
                .resolveAttribute(com.google.android.material.R.attr.colorOutline, typedValue, true);
        return typedValue.data;
    }

    public int getTitleTextColor() {
        context.getTheme().resolveAttribute(androidx.appcompat.R.attr.titleTextColor, typedValue, true);
        return typedValue.data;
    }

    public int getSubTitleTextColor() {
        context
                .getTheme()
                .resolveAttribute(androidx.appcompat.R.attr.subtitleTextColor, typedValue, true);
        return typedValue.data;
    }

    public int getActionMenuTextColor() {
        context
                .getTheme()
                .resolveAttribute(androidx.appcompat.R.attr.actionMenuTextColor, typedValue, true);
        return typedValue.data;
    }

    public int getTextColor() {
        context.getTheme().resolveAttribute(android.R.attr.textColor, typedValue, true);
        return typedValue.data;
    }

    public int getTextColorHint() {
        context.getTheme().resolveAttribute(android.R.attr.textColorHint, typedValue, true);
        return typedValue.data;
    }

    public int getTextColorHighlight() {
        context.getTheme().resolveAttribute(android.R.attr.textColorHighlight, typedValue, true);
        return typedValue.data;
    }

    public int getEditTextColor() {
        context.getTheme().resolveAttribute(androidx.appcompat.R.attr.editTextColor, typedValue, true);
        return typedValue.data;
    }

    public int getColorBackground() {
        return MaterialColors.getColor(context, android.R.attr.colorBackground, null);
    }

    public int getColorOnBackground() {
        context
                .getTheme()
                .resolveAttribute(com.google.android.material.R.attr.colorOnBackground, typedValue, true);
        return typedValue.data;
    }

    public int getAnyColor(int i) {
        context.getTheme().resolveAttribute(i, typedValue, true);
        return typedValue.data;
    }
}
