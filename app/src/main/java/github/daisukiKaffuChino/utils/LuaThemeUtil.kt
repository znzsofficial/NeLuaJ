package github.daisukiKaffuChino.utils

import android.content.Context
import android.util.TypedValue
import androidx.appcompat.R

class LuaThemeUtil(var context: Context) {
    private var typedValue: TypedValue = TypedValue()

    val colorPrimary: Int
        get() {
            context.theme.resolveAttribute(R.attr.colorPrimary, typedValue, true)
            return typedValue.data
        }
    val colorOnPrimary: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorOnPrimary,
                    typedValue,
                    true
                )
            return typedValue.data
        }
    val colorPrimaryDark: Int
        get() {
            context
                .theme
                .resolveAttribute(R.attr.colorPrimaryDark, typedValue, true)
            return typedValue.data
        }
    val colorPrimaryVariant: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorPrimaryVariant,
                    typedValue,
                    true
                )
            return typedValue.data
        }
    val colorPrimaryContainer: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorPrimaryContainer, typedValue, true
                )
            return typedValue.data
        }
    val colorOnPrimaryContainer: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorOnPrimaryContainer, typedValue, true
                )
            return typedValue.data
        }
    val colorPrimaryInverse: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorPrimaryInverse,
                    typedValue,
                    true
                )
            return typedValue.data
        }
    val colorPrimarySurface: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorPrimarySurface,
                    typedValue,
                    true
                )
            return typedValue.data
        }
    val colorAccent: Int
        get() {
            context.theme.resolveAttribute(R.attr.colorAccent, typedValue, true)
            return typedValue.data
        }
    val colorSecondary: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorSecondary,
                    typedValue,
                    true
                )
            return typedValue.data
        }
    val colorOnSecondary: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorOnSecondary,
                    typedValue,
                    true
                )
            return typedValue.data
        }
    val colorSecondaryVariant: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorSecondaryVariant, typedValue, true
                )
            return typedValue.data
        }
    val colorSecondaryContainer: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorSecondaryContainer, typedValue, true
                )
            return typedValue.data
        }
    val colorOnSecondaryContainer: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorOnSecondaryContainer, typedValue, true
                )
            return typedValue.data
        }
    val colorTertiary: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorTertiary,
                    typedValue,
                    true
                )
            return typedValue.data
        }
    val colorOnTertiary: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorOnTertiary,
                    typedValue,
                    true
                )
            return typedValue.data
        }
    val colorTertiaryContainer: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorTertiaryContainer, typedValue, true
                )
            return typedValue.data
        }
    val colorOnTertiaryContainer: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorOnTertiaryContainer, typedValue, true
                )
            return typedValue.data
        }
    val colorError: Int
        get() {
            context.theme.resolveAttribute(R.attr.colorError, typedValue, true)
            return typedValue.data
        }
    val colorOnError: Int
        get() {
            context
                .theme
                .resolveAttribute(com.google.android.material.R.attr.colorOnError, typedValue, true)
            return typedValue.data
        }
    val colorErrorContainer: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorErrorContainer,
                    typedValue,
                    true
                )
            return typedValue.data
        }
    val colorOnErrorContainer: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorOnErrorContainer, typedValue, true
                )
            return typedValue.data
        }
    val colorSurface: Int
        get() {
            context
                .theme
                .resolveAttribute(com.google.android.material.R.attr.colorSurface, typedValue, true)
            return typedValue.data
        }
    val colorSurfaceInverse: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorSurfaceInverse,
                    typedValue,
                    true
                )
            return typedValue.data
        }
    val colorSurfaceVariant: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorSurfaceVariant,
                    typedValue,
                    true
                )
            return typedValue.data
        }
    val colorOnSurface: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorOnSurface,
                    typedValue,
                    true
                )
            return typedValue.data
        }
    val colorOnSurfaceInverse: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorOnSurfaceInverse, typedValue, true
                )
            return typedValue.data
        }
    val colorOnSurfaceVariant: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorOnSurfaceVariant, typedValue, true
                )
            return typedValue.data
        }
    val colorOnPrimarySurface: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorOnPrimarySurface, typedValue, true
                )
            return typedValue.data
        }
    val colorOutline: Int
        get() {
            context
                .theme
                .resolveAttribute(com.google.android.material.R.attr.colorOutline, typedValue, true)
            return typedValue.data
        }
    val titleTextColor: Int
        get() {
            context.theme.resolveAttribute(R.attr.titleTextColor, typedValue, true)
            return typedValue.data
        }
    val subTitleTextColor: Int
        get() {
            context
                .theme
                .resolveAttribute(R.attr.subtitleTextColor, typedValue, true)
            return typedValue.data
        }
    val actionMenuTextColor: Int
        get() {
            context
                .theme
                .resolveAttribute(R.attr.actionMenuTextColor, typedValue, true)
            return typedValue.data
        }
    val textColor: Int
        get() {
            context.theme.resolveAttribute(android.R.attr.textColor, typedValue, true)
            return typedValue.data
        }
    val textColorHint: Int
        get() {
            context.theme.resolveAttribute(android.R.attr.textColorHint, typedValue, true)
            return typedValue.data
        }
    val textColorHighlight: Int
        get() {
            context.theme.resolveAttribute(android.R.attr.textColorHighlight, typedValue, true)
            return typedValue.data
        }
    val editTextColor: Int
        get() {
            context.theme.resolveAttribute(R.attr.editTextColor, typedValue, true)
            return typedValue.data
        }
    val colorBackground: Int
        get() {
            context.theme.resolveAttribute(android.R.attr.colorBackground, typedValue, true)
            return typedValue.data
        }
    val colorOnBackground: Int
        get() {
            context
                .theme
                .resolveAttribute(
                    com.google.android.material.R.attr.colorOnBackground,
                    typedValue,
                    true
                )
            return typedValue.data
        }

    fun getAnyColor(i: Int): Int {
        context.theme.resolveAttribute(i, typedValue, true)
        return typedValue.data
    }
}
