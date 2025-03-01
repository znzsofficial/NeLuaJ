package com.nekolaska.ktx

import android.app.Activity
import android.app.Activity.OVERRIDE_TRANSITION_CLOSE
import android.app.Activity.OVERRIDE_TRANSITION_OPEN
import android.os.Build

fun Activity.overridePendingTransition(
    overrideTransitionClose: Boolean = false,
    enterAnim: Int,
    exitAnim: Int,
) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        overrideActivityTransition(
            if (overrideTransitionClose) OVERRIDE_TRANSITION_CLOSE else OVERRIDE_TRANSITION_OPEN,
            enterAnim,
            exitAnim
        )
    } else {
        @Suppress("DEPRECATION")
        overridePendingTransition(enterAnim, exitAnim)
    }
}