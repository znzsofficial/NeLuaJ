package com.nekolaska.widget

import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.CompoundButton

/** A whole settings row is one named switch; its visual children are not extra nodes. */
object SettingsAccessibility {
    @JvmStatic
    fun bindSwitch(row: ViewGroup, toggle: CompoundButton) {
        row.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        row.isFocusable = true
        for (index in 0 until row.childCount) {
            row.getChildAt(index).importantForAccessibility =
                View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }
        row.accessibilityDelegate = object : View.AccessibilityDelegate() {
            override fun onInitializeAccessibilityNodeInfo(host: View, info: AccessibilityNodeInfo) {
                super.onInitializeAccessibilityNodeInfo(host, info)
                info.className = "android.widget.Switch"
                info.isCheckable = true
                info.isChecked = toggle.isChecked
                info.isEnabled = host.isEnabled && toggle.isEnabled
                info.isClickable = info.isEnabled
                if (info.isEnabled) {
                    info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_CLICK)
                } else {
                    info.removeAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_CLICK)
                }
            }

            override fun onInitializeAccessibilityEvent(host: View, event: AccessibilityEvent) {
                super.onInitializeAccessibilityEvent(host, event)
                event.className = "android.widget.Switch"
                event.isChecked = toggle.isChecked
            }

            override fun performAccessibilityAction(host: View, action: Int, args: Bundle?): Boolean {
                if (action == AccessibilityNodeInfo.ACTION_CLICK) {
                    return host.isEnabled && toggle.isEnabled && host.performClick()
                }
                return super.performAccessibilityAction(host, action, args)
            }
        }
        toggle.setOnCheckedChangeListener { _, _ ->
            row.sendAccessibilityEvent(AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED)
        }
    }
}
