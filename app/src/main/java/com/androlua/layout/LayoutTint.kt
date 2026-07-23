package com.androlua.layout

import android.content.res.ColorStateList
import android.view.View
import android.widget.CompoundButton
import android.widget.ImageView
import android.widget.ProgressBar
import androidx.core.view.ViewCompat
import androidx.core.widget.CompoundButtonCompat
import androidx.core.widget.ImageViewCompat
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.chip.Chip
import com.google.android.material.floatingactionbutton.ExtendedFloatingActionButton
import com.google.android.material.floatingactionbutton.FloatingActionButton
import com.google.android.material.textfield.TextInputLayout

/**
 * tint 相关专用属性：
 * - [apply]：历史 TintColor / tintColor，按控件类型落到背景+图标等
 * - [applyIconTint]：仅图标 tint（iconTint）；int/色串已由 parser 转成 ColorStateList
 *
 * 所有 setter 经 runCatching，避免单个控件 API 差异拖垮整张布局。
 */
internal object LayoutTint {

    /**
     * 仅设置图标 tint，不改背景。
     * @return 是否至少成功应用了一种 tint 路径
     */
    fun applyIconTint(host: View, csl: ColorStateList): Boolean {
        // 已知类型：单路径直写，避免连环 tryCsl 反射
        when (host) {
            is ExtendedFloatingActionButton -> {
                host.iconTint = csl
                return true
            }
            is MaterialButton -> {
                host.iconTint = csl
                return true
            }
            is FloatingActionButton -> {
                ImageViewCompat.setImageTintList(host, csl)
                return true
            }
            is Chip -> {
                host.chipIconTint = csl
                return true
            }
            is ImageView -> {
                ImageViewCompat.setImageTintList(host, csl)
                return true
            }
            is TextInputLayout -> {
                host.setStartIconTintList(csl)
                host.setEndIconTintList(csl)
                return true
            }
        }
        // 第三方 / 未知：最多试常见 setter
        if (LayoutReflection.invokeColorStateListSetter(host, "setIconTint", csl) ||
            LayoutReflection.invokeColorStateListSetter(host, "setIconTintList", csl) ||
            LayoutReflection.invokeColorStateListSetter(host, "setImageTintList", csl) ||
            LayoutReflection.invokeColorStateListSetter(host, "setSupportImageTintList", csl)
        ) {
            return true
        }
        return false
    }

    fun apply(host: View, csl: ColorStateList) {
        when (host) {
            is FloatingActionButton -> {
                ImageViewCompat.setImageTintList(host, csl)
                host.backgroundTintList = csl
            }
            is ImageView -> ImageViewCompat.setImageTintList(host, csl)
            is CompoundButton -> {
                CompoundButtonCompat.setButtonTintList(host, csl)
                LayoutReflection.invokeColorStateListSetter(host, "setTrackTintList", csl)
                LayoutReflection.invokeColorStateListSetter(host, "setThumbTintList", csl)
            }
            is ProgressBar -> {
                host.indeterminateTintList = csl
                host.progressTintList = csl
                host.secondaryProgressTintList = csl
            }
            is ExtendedFloatingActionButton -> {
                host.backgroundTintList = csl
                host.iconTint = csl
            }
            is MaterialButton -> {
                host.backgroundTintList = csl
                host.iconTint = csl
            }
            is Chip -> {
                host.chipIconTint = csl
                host.closeIconTint = csl
            }
            is TextInputLayout -> {
                runCatching { host.setBoxStrokeColorStateList(csl) }
                host.setHintTextColor(csl)
                host.setStartIconTintList(csl)
                host.setEndIconTintList(csl)
            }
            is MaterialCardView -> host.setStrokeColor(csl)
            else -> {
                ViewCompat.setBackgroundTintList(host, csl)
                if (!LayoutReflection.invokeColorStateListSetter(
                        host, "setSupportBackgroundTintList", csl
                    )
                ) {
                    LayoutReflection.invokeColorStateListSetter(host, "setButtonTintList", csl)
                    LayoutReflection.invokeColorStateListSetter(host, "setIconTintList", csl)
                    LayoutReflection.invokeColorStateListSetter(host, "setImageTintList", csl)
                }
            }
        }
    }
}
