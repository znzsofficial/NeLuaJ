```lua
import "com.androlua.LuaPreferenceFragment"
import "androidx.preference.SeekBarPreference"
import "androidx.preference.SwitchPreference"
local fragment = LuaPreferenceFragment{
    {
        SwitchPreference,
        defaultValue=true;
        title="开关";
        summary="描述";
        key="key_preference";
    },
    {
        SeekBarPreference,
        value=5,
    }
}
this.setFragment(fragment)

fragment.onPreferenceChange = function(preference, newValue)
    print(preference, newValue)
end

fragment.onPreferenceClick = function(preference)
    print(preference)
end
```