package github.daisukiKaffuChino.utils

import android.content.Context
import android.util.TypedValue
import androidx.annotation.AttrRes
import androidx.appcompat.view.ContextThemeWrapper
import com.google.android.material.color.MaterialColors

/**
 * A Kotlin-idiomatic utility class for accessing theme colors.
 *
 * Provides a structured way to get Material Design theme colors,
 * while maintaining backward compatibility with the original Java methods.
 *
 * @property context The context used to resolve theme attributes.
 *
 * New structured access example:
 * ```
 * val primaryColor = themeUtil.primary.main
 * val surfaceContainerColor = themeUtil.surface.container
 * val textColor = themeUtil.text.primary
 * ```
 *
 * Backward-compatible access example:
 * ```
 * val primaryColor = themeUtil.getColorPrimary()
 * ```
 */
class LuaThemeUtil(private val context: Context) {
    val typedValue = TypedValue()

    //region Helper Methods
    private fun getMaterialColor(@AttrRes attrResId: Int): Int {
        // The last parameter is a "tag" used for error logging by the Material library.
        return MaterialColors.getColor(
            ContextThemeWrapper(context, context.theme), attrResId, "LuaThemeUtil"
        )
    }

    private fun resolveSystemColor(@AttrRes attrResId: Int): Int {
        context.theme.resolveAttribute(attrResId, typedValue, true)
        return typedValue.data
    }
    //endregion

    //region Structured Accessors
    val primary by lazy { PrimaryColors() }
    val secondary by lazy { SecondaryColors() }
    val tertiary by lazy { TertiaryColors() }
    val error by lazy { ErrorColors() }
    val surface by lazy { SurfaceColors() }
    val background by lazy { BackgroundColors() }
    val text by lazy { TextColors() }
    val outline by lazy { OutlineColors() }
    //endregion

    //region Color Groups (Inner Classes for structured access)

    inner class PrimaryColors {
        val main: Int get() = getMaterialColor(androidx.appcompat.R.attr.colorPrimary)
        val on: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOnPrimary)
        val dark: Int get() = getMaterialColor(androidx.appcompat.R.attr.colorPrimaryDark)
        val variant: Int get() = getMaterialColor(com.google.android.material.R.attr.colorPrimaryVariant)
        val container: Int get() = getMaterialColor(com.google.android.material.R.attr.colorPrimaryContainer)
        val onContainer: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOnPrimaryContainer)
        val inverse: Int get() = getMaterialColor(com.google.android.material.R.attr.colorPrimaryInverse)
        val fixed: Int get() = getMaterialColor(com.google.android.material.R.attr.colorPrimaryFixed)
        val fixedDim: Int get() = getMaterialColor(com.google.android.material.R.attr.colorPrimaryFixedDim)
        val onFixed: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOnPrimaryFixed)
        val onFixedVariant: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOnPrimaryFixedVariant)
    }

    inner class SecondaryColors {
        val main: Int get() = getMaterialColor(com.google.android.material.R.attr.colorSecondary)
        val on: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOnSecondary)
        val variant: Int get() = getMaterialColor(com.google.android.material.R.attr.colorSecondaryVariant)
        val container: Int get() = getMaterialColor(com.google.android.material.R.attr.colorSecondaryContainer)
        val onContainer: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOnSecondaryContainer)
        val fixed: Int get() = getMaterialColor(com.google.android.material.R.attr.colorSecondaryFixed)
        val fixedDim: Int get() = getMaterialColor(com.google.android.material.R.attr.colorSecondaryFixedDim)
        val onFixed: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOnSecondaryFixed)
        val onFixedVariant: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOnSecondaryFixedVariant)
    }

    inner class TertiaryColors {
        val main: Int get() = getMaterialColor(com.google.android.material.R.attr.colorTertiary)
        val on: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOnTertiary)
        val container: Int get() = getMaterialColor(com.google.android.material.R.attr.colorTertiaryContainer)
        val onContainer: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOnTertiaryContainer)
        val fixed: Int get() = getMaterialColor(com.google.android.material.R.attr.colorTertiaryFixed)
        val fixedDim: Int get() = getMaterialColor(com.google.android.material.R.attr.colorTertiaryFixedDim)
        val onFixed: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOnTertiaryFixed)
        val onFixedVariant: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOnTertiaryFixedVariant)
    }

    inner class ErrorColors {
        val main: Int get() = getMaterialColor(androidx.appcompat.R.attr.colorError)
        val on: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOnError)
        val container: Int get() = getMaterialColor(com.google.android.material.R.attr.colorErrorContainer)
        val onContainer: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOnErrorContainer)
    }

    inner class SurfaceColors {
        val main: Int get() = getMaterialColor(com.google.android.material.R.attr.colorSurface)
        val on: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOnSurface)
        val inverse: Int get() = getMaterialColor(com.google.android.material.R.attr.colorSurfaceInverse)
        val onInverse: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOnSurfaceInverse)
        val variant: Int get() = getMaterialColor(com.google.android.material.R.attr.colorSurfaceVariant)
        val onVariant: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOnSurfaceVariant)
        val primary: Int get() = getMaterialColor(com.google.android.material.R.attr.colorPrimarySurface)
        val onPrimary: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOnPrimarySurface)
        val bright: Int get() = getMaterialColor(com.google.android.material.R.attr.colorSurfaceBright)
        val dim: Int get() = getMaterialColor(com.google.android.material.R.attr.colorSurfaceDim)
        val container: Int get() = getMaterialColor(com.google.android.material.R.attr.colorSurfaceContainer)
        val containerLow: Int get() = getMaterialColor(com.google.android.material.R.attr.colorSurfaceContainerLow)
        val containerLowest: Int get() = getMaterialColor(com.google.android.material.R.attr.colorSurfaceContainerLowest)
        val containerHigh: Int get() = getMaterialColor(com.google.android.material.R.attr.colorSurfaceContainerHigh)
        val containerHighest: Int get() = getMaterialColor(com.google.android.material.R.attr.colorSurfaceContainerHighest)
    }

    inner class BackgroundColors {
        val main: Int get() = getMaterialColor(android.R.attr.colorBackground)
        val on: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOnBackground)
    }

    inner class TextColors {
        val primary: Int get() = resolveSystemColor(android.R.attr.textColor)
        val hint: Int get() = resolveSystemColor(android.R.attr.textColorHint)
        val highlight: Int get() = resolveSystemColor(android.R.attr.textColorHighlight)
        val title: Int get() = resolveSystemColor(android.R.attr.titleTextColor)
        val subtitle: Int get() = resolveSystemColor(android.R.attr.subtitleTextColor)
        val actionMenu: Int get() = resolveSystemColor(androidx.appcompat.R.attr.actionMenuTextColor)
        val editText: Int get() = resolveSystemColor(androidx.appcompat.R.attr.editTextColor)
    }

    inner class OutlineColors {
        val main: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOutline)
        val variant: Int get() = getMaterialColor(com.google.android.material.R.attr.colorOutlineVariant)
    }
    //endregion

    //region Backward Compatibility (Original methods)
    @JvmName("getColorPrimary")
    fun getColorPrimary(): Int = primary.main

    @JvmName("getColorOnPrimary")
    fun getColorOnPrimary(): Int = primary.on

    @JvmName("getColorPrimaryDark")
    fun getColorPrimaryDark(): Int = primary.dark

    @JvmName("getColorPrimaryVariant")
    fun getColorPrimaryVariant(): Int = primary.variant

    @JvmName("getColorPrimaryContainer")
    fun getColorPrimaryContainer(): Int = primary.container

    @JvmName("getColorOnPrimaryContainer")
    fun getColorOnPrimaryContainer(): Int = primary.onContainer

    @JvmName("getColorPrimaryInverse")
    fun getColorPrimaryInverse(): Int = primary.inverse

    @JvmName("getColorPrimarySurface")
    fun getColorPrimarySurface(): Int = surface.primary

    @JvmName("getColorAccent")
    fun getColorAccent(): Int = getMaterialColor(androidx.appcompat.R.attr.colorAccent)

    @JvmName("getColorSecondary")
    fun getColorSecondary(): Int = secondary.main

    @JvmName("getColorOnSecondary")
    fun getColorOnSecondary(): Int = secondary.on

    @JvmName("getColorSecondaryVariant")
    fun getColorSecondaryVariant(): Int = secondary.variant

    @JvmName("getColorSecondaryContainer")
    fun getColorSecondaryContainer(): Int = secondary.container

    @JvmName("getColorOnSecondaryContainer")
    fun getColorOnSecondaryContainer(): Int = secondary.onContainer

    @JvmName("getColorTertiary")
    fun getColorTertiary(): Int = tertiary.main

    @JvmName("getColorOnTertiary")
    fun getColorOnTertiary(): Int = tertiary.on

    @JvmName("getColorTertiaryContainer")
    fun getColorTertiaryContainer(): Int = tertiary.container

    @JvmName("getColorOnTertiaryContainer")
    fun getColorOnTertiaryContainer(): Int = tertiary.onContainer

    @JvmName("getColorError")
    fun getColorError(): Int = error.main

    @JvmName("getColorOnError")
    fun getColorOnError(): Int = error.on

    @JvmName("getColorErrorContainer")
    fun getColorErrorContainer(): Int = error.container

    @JvmName("getColorOnErrorContainer")
    fun getColorOnErrorContainer(): Int = error.onContainer

    @JvmName("getColorSurface")
    fun getColorSurface(): Int = surface.main

    @JvmName("getColorSurfaceInverse")
    fun getColorSurfaceInverse(): Int = surface.inverse

    @JvmName("getColorSurfaceVariant")
    fun getColorSurfaceVariant(): Int = surface.variant

    @JvmName("getColorOnSurface")
    fun getColorOnSurface(): Int = surface.on

    @JvmName("getColorOnSurfaceInverse")
    fun getColorOnSurfaceInverse(): Int = surface.onInverse

    @JvmName("getColorOnSurfaceVariant")
    fun getColorOnSurfaceVariant(): Int = surface.onVariant

    @JvmName("getColorOnPrimarySurface")
    fun getColorOnPrimarySurface(): Int = surface.onPrimary

    @JvmName("getColorOutline")
    fun getColorOutline(): Int = outline.main

    @JvmName("getColorOnPrimaryFixed")
    fun getColorOnPrimaryFixed(): Int = primary.onFixed

    @JvmName("getColorOnPrimaryFixedVariant")
    fun getColorOnPrimaryFixedVariant(): Int = primary.onFixedVariant

    @JvmName("getColorOnSecondaryFixed")
    fun getColorOnSecondaryFixed(): Int = secondary.onFixed

    @JvmName("getColorOnSecondaryFixedVariant")
    fun getColorOnSecondaryFixedVariant(): Int = secondary.onFixedVariant

    @JvmName("getColorOnTertiaryFixed")
    fun getColorOnTertiaryFixed(): Int = tertiary.onFixed

    @JvmName("getColorOnTertiaryFixedVariant")
    fun getColorOnTertiaryFixedVariant(): Int = tertiary.onFixedVariant

    @JvmName("getColorOutlineVariant")
    fun getColorOutlineVariant(): Int = outline.variant

    @JvmName("getColorPrimaryFixed")
    fun getColorPrimaryFixed(): Int = primary.fixed

    @JvmName("getColorPrimaryFixedDim")
    fun getColorPrimaryFixedDim(): Int = primary.fixedDim

    @JvmName("getColorSecondaryFixed")
    fun getColorSecondaryFixed(): Int = secondary.fixed

    @JvmName("getColorSecondaryFixedDim")
    fun getColorSecondaryFixedDim(): Int = secondary.fixedDim

    @JvmName("getColorSurfaceBright")
    fun getColorSurfaceBright(): Int = surface.bright

    @JvmName("getColorSurfaceContainer")
    fun getColorSurfaceContainer(): Int = surface.container

    @JvmName("getColorSurfaceContainerHigh")
    fun getColorSurfaceContainerHigh(): Int = surface.containerHigh

    @JvmName("getColorSurfaceContainerHighest")
    fun getColorSurfaceContainerHighest(): Int = surface.containerHighest

    @JvmName("getColorSurfaceContainerLow")
    fun getColorSurfaceContainerLow(): Int = surface.containerLow

    @JvmName("getColorSurfaceContainerLowest")
    fun getColorSurfaceContainerLowest(): Int = surface.containerLowest

    @JvmName("getColorSurfaceDim")
    fun getColorSurfaceDim(): Int = surface.dim

    @JvmName("getColorTertiaryFixed")
    fun getColorTertiaryFixed(): Int = tertiary.fixed

    @JvmName("getColorTertiaryFixedDim")
    fun getColorTertiaryFixedDim(): Int = tertiary.fixedDim

    @JvmName("getTitleTextColor")
    fun getTitleTextColor(): Int = text.title

    @JvmName("getSubTitleTextColor")
    fun getSubTitleTextColor(): Int = text.subtitle

    @JvmName("getActionMenuTextColor")
    fun getActionMenuTextColor(): Int = text.actionMenu

    @JvmName("getTextColor")
    fun getTextColor(): Int = text.primary

    @JvmName("getTextColorHint")
    fun getTextColorHint(): Int = text.hint

    @JvmName("getTextColorHighlight")
    fun getTextColorHighlight(): Int = text.highlight

    @JvmName("getEditTextColor")
    fun getEditTextColor(): Int = text.editText

    @JvmName("getColorBackground")
    fun getColorBackground(): Int = background.main

    @JvmName("getColorOnBackground")
    fun getColorOnBackground(): Int = background.on

    @JvmName("getAnyColor")
    fun getAnyColor(i: Int): Int = getMaterialColor(i)
    //endregion
}