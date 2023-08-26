import "android.content.Context"
import "androidx.core.content.SharedPreferencesCompat"
import "vinx.material.preference.PreferenceDataStore"

local DEFAULT_FILE_NAME = "shared_preferences"

return function(name)
    local name = name or DEFAULT_FILE_NAME
    local sp = activity.getSharedPreferences(name, Context.MODE_PRIVATE)
    local editor = sp.edit()
    return PreferenceDataStore {
        putString = function(key, value)
            editor.putString(key, value).commit()
        end,
        getString = function(key)
            return sp.getString(key, nil)
        end,

        putInt = function(key, value)
            editor.putInt(key, value).commit()
        end,
        getInt = function(key)
            return sp.getInt(key, 0)
        end,

        putFloat = function(key, value)
            editor.putFloat(key, value).commit()
        end,
        getFloat = function(key)
            return sp.getFloat(key, 0)
        end,

        putLong = function(key, value)
        end,
        getLong = function(key)
        end,

        putMap = function(key, value)
        end,
        getMap = function(key)
        end,

        putPair = function(key, value)
        end,
        getPair = function(key)
        end,

        putArray = function(key, value)
        end,
        getArray = function(key)
        end,

        putBoolean = function(key, value)
            editor.putBoolean(key, value).commit()
        end,
        getBoolean = function(key)
            return sp.getBoolean(key, false)
        end,

        putSerializableObject = function(key, value)
        end,
        getSerializableObject = function(key)
        end
    }
end