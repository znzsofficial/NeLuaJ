package com.androlua.layout

/** Metadata for tooling only. The legacy inflater's hot path does not consult this registry. */
internal object LayoutSchema {
    data class Attribute(
        val name: String,
        val type: String,
        val owners: Set<String> = setOf("View"),
        val parents: Set<String> = emptySet(),
        val aliases: Set<String> = emptySet(),
        val unit: String? = null,
        val example: String? = null,
        val note: String? = null,
        val flags: Boolean = false,
    ) {
        val enums: Set<String> get() = when (name) {
            "scaleType" -> LayoutEnums.scaleType.keys
            "ellipsize" -> setOf("start", "end", "middle", "marquee")
            "textStyle" -> setOf("normal", "bold", "italic", "bold|italic", "italic|bold", "bold_italic", "bolditalic")
            else -> LayoutEnums.enumMapForAttr(name)?.keys ?: emptySet()
        }
    }

    // Only these shipped classes can be reflected. Never load a class named by untrusted source.
    private val packages = linkedMapOf(
        "android.view" to "View ViewGroup",
        "android.widget" to "LinearLayout FrameLayout RelativeLayout ScrollView HorizontalScrollView TextView EditText Button ImageView ImageButton CheckBox RadioButton Switch ToggleButton ProgressBar SeekBar ListView GridView Spinner Space",
        "androidx.appcompat.widget" to "AppCompatTextView AppCompatEditText AppCompatButton AppCompatImageView AppCompatImageButton AppCompatCheckBox SwitchCompat LinearLayoutCompat",
        "androidx.core.widget" to "NestedScrollView",
        "androidx.recyclerview.widget" to "RecyclerView",
        "androidx.constraintlayout.widget" to "ConstraintLayout",
        "androidx.coordinatorlayout.widget" to "CoordinatorLayout",
        "androidx.drawerlayout.widget" to "DrawerLayout",
        "androidx.swiperefreshlayout.widget" to "SwipeRefreshLayout",
        "androidx.cardview.widget" to "CardView",
        "com.google.android.material.textview" to "MaterialTextView",
        "com.google.android.material.button" to "MaterialButton MaterialButtonToggleGroup",
        "com.google.android.material.card" to "MaterialCardView",
        "com.google.android.material.textfield" to "TextInputLayout TextInputEditText",
        "com.google.android.material.checkbox" to "MaterialCheckBox",
        "com.google.android.material.radiobutton" to "MaterialRadioButton",
        "com.google.android.material.materialswitch" to "MaterialSwitch",
        "com.google.android.material.switchmaterial" to "SwitchMaterial",
        "com.google.android.material.chip" to "Chip ChipGroup",
        "com.google.android.material.floatingactionbutton" to "FloatingActionButton ExtendedFloatingActionButton",
        "com.google.android.material.appbar" to "AppBarLayout CollapsingToolbarLayout MaterialToolbar",
        "com.google.android.material.divider" to "MaterialDivider",
        "com.google.android.material.navigation" to "NavigationView",
        "com.google.android.material.tabs" to "TabLayout",
        "vinx.material.textfield" to "MaterialTextField",
    )
    val classes: Map<String, String> = packages.flatMap { (pkg, names) ->
        names.split(' ').map { it to "$pkg.$it" }
    }.toMap()

    data class Widget(val name: String, val clazz: Class<*>) {
        val families: Set<String> = generateSequence(clazz) { it.superclass }
            .map { it.simpleName }.toSet()
        val textProxy: Boolean = "TextInputLayout" in families
        fun supports(owners: Set<String>): Boolean = owners.any { it in families } ||
            (textProxy && "TextView" in owners)
        val isGroup: Boolean get() = "ViewGroup" in families
        val isAdapter: Boolean get() = "AdapterView" in families
        val singleChild: Boolean get() = families.any { it in setOf("ScrollView", "HorizontalScrollView", "NestedScrollView") }
        val properties: Set<String> get() = LayoutReflection.propertyNamesFor(clazz)
    }

    fun widget(name: String?): Widget? {
        if (name == null) return null
        val simple = name.substringAfterLast('.')
        val full = classes[simple] ?: return null
        if (name != simple && name != full) return null
        return runCatching {
            Widget(simple, Class.forName(full, false, LayoutSchema::class.java.classLoader))
        }.getOrNull()
    }

    val attributes: List<Attribute> = buildList {
        fun add(name: String, type: String, owners: String = "View", parents: String = "",
                aliases: String = "", unit: String? = null, example: String? = null,
                note: String? = null, flags: Boolean = false) {
            add(Attribute(name, type, owners.split(' ').toSet(), parents.split(' ').filter { it.isNotEmpty() }.toSet(),
                aliases.split(' ').filter { it.isNotEmpty() }.toSet(), unit, example, note, flags))
        }
        add("id", "string", example = "saveButton", note = "Use unique ids and a local views binding table.")
        for (name in listOf("style", "styleAttr", "styleRes", "theme")) {
            add(name, "resource", note = "Constructor option; see res/doc/layout_style.html. theme wraps Context, not a widget style.")
        }
        for (name in listOf("layout_width", "layout_height")) {
            add(name, "size", unit = "px", example = "match", note = "Prefer match/wrap or explicit dp. Omitted dimensions default to wrap.")
        }
        add("layout_weight", "number", parents = "LinearLayout", example = "1", note = "Use 0dp on the parent's distribution axis for proportional sizing.")
        add("layout_gravity", "enum", parents = "LinearLayout FrameLayout CoordinatorLayout", flags = true)
        for (suffix in listOf("", "Left", "Top", "Right", "Bottom", "Start", "End", "Horizontal", "Vertical")) {
            add("layout_margin$suffix", "dimension", parents = "MarginLayoutParams", unit = "px", example = "16dp")
        }
        for (suffix in listOf("", "Left", "Top", "Right", "Bottom", "Start", "End")) {
            add("padding$suffix", "dimension", unit = "px", example = "16dp")
        }
        for (name in LayoutEnums.relativeRules.keys) {
            val parentRule = name.startsWith("layout_alignParent") || name.startsWith("layout_center")
            add(name, if (parentRule) "boolean" else "reference", parents = "RelativeLayout",
                note = if (parentRule) null else "Target id must already be registered by the current loader; prefer earlier sibling declarations.")
        }
        add("layout_alignWithParentIfMissing", "boolean", parents = "RelativeLayout")
        add("layout_anchor", "reference", parents = "CoordinatorLayout", note = "Target id must already be registered.")
        add("layout_behavior", "behavior", parents = "CoordinatorLayout")
        add("layout_scrollFlags", "enum", parents = "AppBarLayout", flags = true)
        add("layout_collapseMode", "enum", parents = "CollapsingToolbarLayout")
        add("layout_collapseParallaxMultiplier", "number", parents = "CollapsingToolbarLayout")
        add("text", "text", "TextView")
        add("hint", "text", "TextView", note = "TextInputLayout hint is applied to its outer floating label.")
        add("textSize", "dimension", "TextView", unit = "sp", example = "16sp")
        add("textStyle", "enum", "TextView")
        for ((name, aliases) in listOf("textColor" to "TextColor", "hintTextColor" to "HintTextColor textColorHint TextColorHint")) {
            add(name, "color", "TextView", aliases = aliases, example = "?attr/colorOnSurface")
        }
        add("ellipsize", "enum", "TextView")
        add("singleLine", "boolean", "TextView")
        add("maxLines", "integer", "TextView")
        add("maxLength", "integer", "TextView")
        add("inputType", "enum", "TextView", flags = true)
        add("imeOptions", "enum", "TextView", flags = true)
        add("lineSpacingMultiplier", "number", "TextView")
        add("lineSpacingExtra", "dimension", "TextView", unit = "px")
        add("gravity", "enum", "TextView LinearLayout LinearLayoutCompat", flags = true,
            note = "Content alignment, not the child's alignment within its parent (layout_gravity).")
        add("orientation", "enum", "LinearLayout LinearLayoutCompat")
        add("scaleType", "enum", "ImageView")
        add("src", "image", "ImageView", example = "@drawable/save",
            note = "Drawable references do not apply tint; use iconTint separately. Paths/URLs load asynchronously.")
        add("background", "background", example = "?attr/colorSurface")
        add("backgroundColor", "color", aliases = "BackgroundColor")
        add("backgroundTintList", "color", aliases = "BackgroundTintList backgroundTint")
        add("iconTint", "color", "ImageView MaterialButton FloatingActionButton Chip TextInputLayout",
            aliases = "IconTint iconTintList IconTintList")
        add("TintColor", "color", aliases = "tintColor", note = "Legacy widget-specific tint; prefer explicit iconTint/backgroundTintList when applicable.")
        add("visibility", "visibility", example = "gone")
        for (name in listOf("enabled", "selected", "clickable", "focusable")) add(name, "boolean")
        add("alpha", "number")
        for (name in listOf("minWidth", "minHeight", "elevation")) add(name, "dimension", unit = "px")
        add("cardBackgroundColor", "color", aliases = "CardBackgroundColor")
        add("cardElevation", "dimension", aliases = "CardElevation", unit = "px")
        add("radius", "dimension", "MaterialCardView MaterialButton", aliases = "cornerRadius", unit = "px")
        add("strokeWidth", "dimension", "MaterialCardView MaterialButton Chip", aliases = "StrokeWidth", unit = "px")
        add("strokeColor", "color", "MaterialCardView MaterialButton Chip", aliases = "StrokeColor")
        add("checked", "boolean", "CompoundButton CheckedTextView MaterialButton MaterialCardView Chip", aliases = "Checked")
        add("checkable", "boolean", "MaterialButton MaterialCardView Chip", aliases = "Checkable")
        add("dividerHeight", "dimension", "ListView", aliases = "DividerHeight", unit = "px")
        add("items", "table", "AdapterView")
        add("pages", "table", "View", note = "Requires setAdapter compatible with LuaPagerAdapter; verify the pager API.")
        add("pagesWithTitle", "table", "View", note = "Requires setAdapter compatible with LuaPagerAdapter.")
        add("contentDescription", "text")
        add("tooltipText", "text")
    }
    private val byName = attributes.flatMap { spec -> (spec.aliases + spec.name).map { it to spec } }.toMap()
    fun attribute(name: String): Attribute? = byName[name]

    fun parentSupports(parent: Widget, spec: Attribute): Boolean {
        if (spec.parents.isEmpty()) return true
        if ("MarginLayoutParams" in spec.parents) {
            val lp = LayoutParamsApplier.resolveNestedLayoutParamsClass(parent.clazz) ?: return false
            return generateSequence(lp) { it.superclass }.any { it.simpleName == "MarginLayoutParams" }
        }
        val lp = LayoutParamsApplier.resolveNestedLayoutParamsClass(parent.clazz)
        return parent.families.any { it in spec.parents } ||
            generateSequence(lp) { it.superclass }.any { it.enclosingClass?.simpleName in spec.parents }
    }

    fun enumValues(spec: Attribute): Set<String> =
        if (spec.type == "visibility") LayoutEnums.visibility.keys else spec.enums
}
