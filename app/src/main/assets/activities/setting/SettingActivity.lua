import "vinx.material.preference.widget.*"
import "vinx.material.preference.widget.SwitchPreference"
import "androidx.appcompat.widget.LinearLayoutCompat"
import "android.graphics.drawable.BitmapDrawable"
import "android.preference.PreferenceManager"
import "com.google.android.material.divider.MaterialDivider"
import "android.widget.ScrollView"
import "mods.dataStore.SharedPreferencesDataStore"
import "vinx.material.preference.PreferenceManager"

activity.contentView = loadlayout {
    ScrollView,
    layout_width = "match",
    layout_height = "match",
    {
        LinearLayoutCompat,
        layout_width = "match",
        layout_height = "match",
        orientation = "vertical",
        {
            SubHeaderPreference,
            layout_width = "match",
            layout_height = "wrap",
            title = "SubHeaderPreference",
        },
        {
            Preference,
            layout_width = "match",
            layout_height = "wrap",
            title = "Preference",
        },
        {
            Preference,
            layout_width = "match",
            layout_height = "wrap",
            title = "Preference",
            summary = "Lorem ipsum dolor.",
        },
        {
            MaterialDivider
        },
        {
            SubHeaderPreference,
            layout_width = "match",
            layout_height = "wrap",
            title = "SubHeaderPreference",
            blankEnabled = true
        },
        {
            Preference,
            layout_width = "match",
            layout_height = "wrap",
            title = "Preference",
            summary = "Lorem ipsum dolor.",
            src = res.bitmap.android_studio,
        },
        {
            SwitchPreference,
            id = "mSwitchPreference",
            layout_width = "match",
            layout_height = "wrap",
            title = "SwitchPreference",
            summary = "Lorem ipsum dolor.",
            src = "icon.png",
            material3StyleEnabled = true,
        },
        {
            CheckBoxPreference,
            layout_width = "match",
            layout_height = "wrap",
            title = "CheckBoxPreference",
            summary = "Lorem ipsum dolor.",
            src = "icon.png"
        },
        {
            EditTextPreference,
            id = "mEditTextPreference",
            layout_width = "match",
            layout_height = "wrap",
            title = "EditTextPreference",
            summary = "Lorem ipsum dolor.",
            src = "icon.png"
        },
        {
            TextFieldPreference,
            id = "mTextFieldPreference",
            layout_width = "match",
            layout_height = "wrap",
            title = "TextFieldPreference",
            summary = "Lorem ipsum dolor.",
            src = "icon.png"
        },
        {
            EndTextPreference,
            layout_width = "match",
            layout_height = "wrap",
            title = "EndTextPreference",
            summary = "Lorem ipsum dolor.",
            src = "icon.png",
            endText = "100%"
        },
        {
            ListPreference,
            id = "l",
            layout_width = "match",
            layout_height = "wrap",
            title = "ListPreference",
            summary = "Lorem ipsum dolor.",
            src = "icon.png",

        },
        {
            SingleChoicePreference,
            id = "a",
            layout_width = "match",
            layout_height = "wrap",
            title = "SingleChoicePreference",
            summary = "Lorem ipsum dolor.",
            src = "icon.png",
        },
        {
            MultiChoicePreference,
            id = "g",
            layout_width = "match",
            layout_height = "wrap",
            title = "MultiChoicePreference",
            summary = "Lorem ipsum dolor.",
        }
    }
}

l.itemArray = { "Apple", "Banana", "Orange" }
a.itemArray = { "Apple", "Banana", "Orange" }
g.itemArray = { "Apple", "Banana", "Orange" }

local manager = PreferenceManager(SharedPreferencesDataStore())

mSwitchPreference.key = "test"
mSwitchPreference.manager = manager
mSwitchPreference.update()

mEditTextPreference.key = "test3"
mEditTextPreference.manager = manager
mEditTextPreference.update()

mTextFieldPreference.key = "test4"
mTextFieldPreference.manager = manager
mTextFieldPreference.update()
--test.material3StyleEnabled = true
--this.window.decorView.setOnApplyWindowInsetsListener(function()
--
--end)
