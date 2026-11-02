package com.androlua.layout

import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.lib.jse.JsePlatform
import java.io.File

/** Read-only Agent entry points. No layout chunks, constructors, imports or setters are executed. */
object LayoutTools {
    private const val MAX_BYTES = 128 * 1024

    @JvmStatic
    fun describe(widget: String, parent: String): LuaTable {
        val view = LayoutSchema.widget(widget)
        val host = LayoutSchema.widget(parent)
        return obj(
            "widget" to widget, "parent" to parent, "knownWidget" to (view != null),
            "knownParent" to (host != null),
            "attributes" to array(LayoutSchema.attributes.filter { spec ->
                (view == null || view.supports(spec.owners)) &&
                    (host == null || LayoutSchema.parentSupports(host, spec))
            }.map { spec ->
                obj("name" to spec.name, "aliases" to array(spec.aliases), "type" to spec.type,
                    "owners" to array(spec.owners), "parents" to array(spec.parents),
                    "bareNumberUnit" to spec.unit, "example" to spec.example, "note" to spec.note,
                    "enums" to array(LayoutSchema.enumValues(spec)), "flags" to spec.flags)
            }),
            "reflectedProperties" to array(view?.properties?.sorted() ?: emptyList<String>()),
            "events" to array(view?.clazz?.methods?.mapNotNull {
                it.name.takeIf { name -> name.startsWith("setOn") && name.endsWith("Listener") && it.parameterCount == 1 }
                    ?.removePrefix("set")?.replaceFirstChar { c -> c.lowercaseChar() }
                    ?.removeSuffix("Listener")
            }?.distinct()?.sorted() ?: emptyList<String>()),
            "notes" to array(listOf(
                "Only shipped, allowlisted classes are reflected, without class initialization. Source aliases and shadowed names cannot be resolved statically.",
                "Custom classes/unknown parents are not declared invalid. A missing property in this curated schema may still be a reflected setter.",
                "Reflection lists capabilities, not inferred units or value semantics. TextInputLayout may delegate text properties to its inner EditText.",
                "layout_* belongs to the parent's LayoutParams. Root parent omitted: parent-specific properties remain conditional.",
                "Prefer explicit dp/sp, local views bindings and unique ids. See res/doc/layout_ai.md."
            )),
            "example" to view?.let { "local views = {}\nlocal root = loadlayout({\n  ${it.name},\n  layout_width = \"match\",\n  layout_height = \"wrap\",\n}, views)" }
        )
    }

    @JvmStatic
    fun checkFile(path: String, parent: String): LuaTable {
        val file = File(path)
        return try {
            // Bound the read itself too: file.length() alone is subject to races and virtual files.
            val bytes = file.inputStream().use { it.readBytesBounded(MAX_BYTES + 1) }
            if (bytes.size > MAX_BYTES) failure(path, "SOURCE_LIMIT", "Layout source exceeds 128 KiB")
            else checkSource(bytes.toString(Charsets.UTF_8), path, parent)
        } catch (e: Exception) {
            failure(path, "READ_ERROR", e.message ?: "Cannot read layout source")
        }
    }

    @JvmStatic
    fun checkSource(source: String, file: String, parent: String): LuaTable {
        if (source.toByteArray(Charsets.UTF_8).size > MAX_BYTES) return failure(file, "SOURCE_LIMIT", "Layout source exceeds 128 KiB")
        return try {
            // The shipped compiler is LuaJ++ aware. load compiles only; never call/invoke the chunk.
            JsePlatform.sandboxGlobals().load(source, "@layout_check")
            Checker(file, parent).check(LayoutSource(source).roots())
        } catch (e: Exception) {
            failure(file, "SOURCE_ERROR", e.message ?: "Cannot parse layout source")
        } catch (_: StackOverflowError) {
            failure(file, "SOURCE_LIMIT", "Layout source nesting exceeds parser limits")
        }
    }

    private class Checker(val file: String, val rootParent: String) {
        private val diagnostics = ArrayList<LuaTable>()
        private var errors = 0
        private var unknowns = 0
        private var nodes = 0
        private var truncated = false
        private val ids = HashMap<String, String>()
        private val nodeIds = HashMap<String, String>()
        private data class Reference(val id: String, val path: String, val field: LayoutSource.Field, val forward: Boolean)
        private val references = ArrayList<Reference>()
        private var dynamicChildren = false

        fun check(roots: List<LayoutSource.Root>): LuaTable {
            if (roots.isEmpty()) diagnostic("NO_LITERAL_LAYOUT", "unknown", "root", null, null,
                "No literal return table or inline loadlayout table found", "Use a literal table; dynamic source is not evaluated")
            for ((index, root) in roots.withIndex()) {
                ids.clear(); nodeIds.clear(); references.clear(); dynamicChildren = false
                val path = "root[${index + 1}]"
                if (root.value == null) {
                    diagnostic("DYNAMIC_ROOT", "unknown", path, root.token, null,
                        root.reason ?: "Return/loadlayout expression is not a literal table", "Inspect the referenced expression separately")
                    continue
                }
                visit(root.value, LayoutSchema.widget(rootParent), path, 0)
                for (ref in references) {
                    if (ref.id !in ids) diagnostic("UNRESOLVED_ID", if (dynamicChildren) "unknown" else "error",
                        ref.path, ref.field.token, ref.field.key, "Unknown target id '${ref.id}'", "Define the target in this layout tree")
                    else if (ref.forward) diagnostic("FORWARD_ID", "warning", ref.path, ref.field.token, ref.field.key,
                        "Target '${ref.id}' is declared later; the current loader may not resolve it",
                        "Declare target siblings earlier; this check does not change runtime reference ordering")
                }
            }
            return obj("file" to file, "hasErrors" to (errors > 0), "complete" to (unknowns == 0 && !truncated),
                "nodesChecked" to nodes, "errors" to errors, "unknowns" to unknowns, "truncated" to truncated,
                "diagnostics" to array(diagnostics),
                "boundary" to "Static literal-table checks only; no code/import/require/View creation. No guarantee of runtime or visual correctness; dynamic expressions and source class aliases are not resolved.")
        }

        private fun visit(value: LayoutSource.Value, parent: LayoutSchema.Widget?, path: String, depth: Int) {
            if (++nodes > 2000 || depth > 48) {
                diagnostic("NODE_LIMIT", "unknown", path, value.token, null, "Layout inspection limit reached", "Split the source")
                return
            }
            val duplicateKeys = HashSet<Any>()
            for (field in value.fields) {
                val key = field.key ?: field.index ?: continue
                if (!duplicateKeys.add(key)) diagnostic("DUPLICATE_PROPERTY", "warning", path, field.token, key.toString(),
                    "Repeated key; Lua keeps the last value", "Keep one declaration")
            }
            // A table literal is a value, not a sequence of setter calls. Earlier duplicate
            // fields are overwritten and nil removes a key before the inflater ever sees it.
            val effective = LinkedHashMap<Any, LayoutSource.Field>()
            for (field in value.fields) effective[field.key ?: field.index ?: field] = field
            val fields = effective.values.filter { it.value.kind != "nil" }
            val classValue = fields.lastOrNull { it.index == 1 }?.value
            val className = classValue?.takeIf { it.kind == "name" }?.expression
            val widget = LayoutSchema.widget(className)
            if (classValue == null || classValue.kind == "nil") {
                diagnostic("MISSING_VIEW_CLASS", "unknown", path, value.token, null,
                    "Table has no statically identifiable View class at [1]; it may be application data",
                    "For a layout, place the imported View class at [1]")
                return
            }
            if (widget == null) diagnostic("UNKNOWN_WIDGET", "unknown", path, classValue.token, null,
                "Cannot verify View class '${className ?: classValue.expression}' without executing source", "Check imports/custom View contract")
            val idValue = fields.lastOrNull { it.key == "id" }?.value
            val id = (idValue?.literal as? String)?.trim()
            val nodePath = if (!id.isNullOrEmpty()) "$path#$id" else path
            if (id != null) nodeIds[nodePath] = id
            if (id != null) {
                if (id.isEmpty()) diagnostic("EMPTY_ID", "error", nodePath, idValue.token, "id", "id cannot be empty", "Use a unique non-empty id")
                else if (ids.put(id, nodePath) != null) diagnostic("DUPLICATE_ID", "error", nodePath, idValue.token, "id", "Duplicate id '$id'", "Rename this binding")
            }
            for (field in fields) {
                if (field.key != null) {
                    attribute(widget, parent, nodePath, field)
                } else if (field.index == null) {
                    diagnostic("DYNAMIC_KEY", "unknown", nodePath, field.token, null, "Computed table key cannot be inspected", "Inspect its runtime value")
                }
            }
            val children = fields.filter { (it.index ?: 0) > 1 }
            if (children.isNotEmpty() && widget != null && !widget.isGroup) diagnostic("LEAF_CHILDREN", "error", nodePath, value.token, null,
                "${widget.name} cannot contain child Views", "Move child nodes to a ViewGroup")
            if (widget?.singleChild == true && children.size > 1) diagnostic("SINGLE_CHILD", "error", nodePath, value.token, null,
                "${widget.name} accepts one direct child", "Wrap children in a LinearLayout or FrameLayout")
            if (widget?.isAdapter == true) {
                if (children.isNotEmpty()) diagnostic("ADAPTER_TEMPLATE", "unknown", nodePath, value.token, null,
                    "AdapterView child tables are item templates, not ordinary children", "Check the template with its adapter API; ids repeat per item")
                dynamicChildren = true
                return
            }
            for (child in children) {
                if (child.value.kind == "table") visit(child.value, widget, "$nodePath/[${child.index}]", depth + 1)
                else {
                    dynamicChildren = true
                    diagnostic("DYNAMIC_CHILD", "unknown", nodePath, child.token, null,
                        "Child may be a required layout, existing View or expression; it is not evaluated", "Check that child separately")
                }
            }
        }

        private fun attribute(widget: LayoutSchema.Widget?, parent: LayoutSchema.Widget?, path: String, field: LayoutSource.Field) {
            val key = field.key ?: return
            val v = field.value
            if (key.startsWith("on")) {
                val setter = "set" + key.replaceFirstChar { it.uppercaseChar() } + "Listener"
                if (widget != null && widget.clazz.methods.none { it.name == setter && it.parameterCount == 1 }) {
                    diagnostic("UNKNOWN_EVENT", "unknown", path, field.token, key, "Cannot verify listener $key", "Check the View listener API")
                }
                return
            }
            val spec = LayoutSchema.attribute(key)
            if (spec == null) {
                val reflected = widget?.let {
                    if (key.startsWith("layout_")) parent?.let { host ->
                        LayoutParamsApplier.resolveNestedLayoutParamsClass(host.clazz)?.let { clazz ->
                            LayoutReflection.canSetJavaProperty(clazz, key.removePrefix("layout_"))
                        }
                    } else LayoutReflection.canSetJavaProperty(it.clazz, key) ||
                        (it.textProxy && LayoutSchema.widget("EditText")?.let { inner -> LayoutReflection.canSetJavaProperty(inner.clazz, key) } == true)
                }
                val severity = if (reflected == false) "error" else "unknown"
                diagnostic(if (reflected == false) "UNKNOWN_PROPERTY" else "UNDESCRIBED_PROPERTY", severity, path, field.token, key,
                    if (reflected == true) "Reflected property has no curated value contract" else "Property is not verified on this View/parent",
                    suggestion(key) ?: "Use layout_describe with widget and parent; custom properties require runtime verification")
                return
            }
            if (widget != null && !widget.supports(spec.owners)) {
                // A custom setter on another shipped class may still implement this property.
                if (!LayoutReflection.canSetJavaProperty(widget.clazz, key)) {
                    diagnostic("WRONG_WIDGET", "error", path, field.token, key,
                        "${widget.name} does not support $key", "Applicable widgets: ${spec.owners.joinToString()}")
                } else diagnostic("CUSTOM_PROPERTY_SEMANTICS", "unknown", path, field.token, key,
                    "Setter exists outside the curated widget contract", "Verify its type and units")
            }
            if (spec.parents.isNotEmpty()) {
                if (parent == null) diagnostic("UNKNOWN_PARENT", "unknown", path, field.token, key,
                    "Parent LayoutParams cannot be determined", "Pass parent to layout_check for a root template")
                else if (!LayoutSchema.parentSupports(parent, spec)) diagnostic("WRONG_PARENT", "error", path, field.token, key,
                    "${parent.name} does not provide LayoutParams for $key", "Required parent: ${spec.parents.joinToString()}", spec.parents.joinToString())
            }
            if (v.kind in listOf("unknown", "name")) {
                diagnostic("DYNAMIC_VALUE", "unknown", path, field.token, key,
                    "Expression is not evaluated: ${v.expression}", "Verify the value at runtime")
                if (key == "id") dynamicChildren = true
                return
            }
            val raw = v.literal
            if (spec.type == "reference" && raw is String && raw != "true") {
                references.add(Reference(raw, path, field, raw !in ids))
            }
            val valid = when (spec.type) {
                "string" -> raw is String
                "text" -> raw is String || raw is Number
                "boolean" -> raw is Boolean || raw is Number || raw is String
                "number", "integer" -> raw is Number || (raw as? String)?.toDoubleOrNull() != null
                "dimension", "size" -> raw is Number || raw is String && validDimension(raw, spec.type == "size")
                "enum", "visibility" -> raw is Number && (spec.type == "visibility" || LayoutEnums.enumMapForAttr(spec.name) != null) ||
                    (spec.type == "visibility" && raw is Boolean) ||
                    raw is String && validEnum(raw, spec)
                "table" -> v.kind == "table"
                "color" -> raw is Number || raw is String && (raw.startsWith('?') || COLOR.matches(raw))
                else -> true // Resource/image/Drawable/behavior values have runtime resolution semantics.
            }
            if (!valid) diagnostic("INVALID_VALUE", "error", path, field.token, key,
                "Invalid ${spec.type} value '${raw ?: v.kind}'", "Expected ${spec.type}; enums: ${LayoutSchema.enumValues(spec).joinToString()}", spec.type)
            val number = (raw as? Number)?.toDouble() ?: (raw as? String)?.toDoubleOrNull()
            if (spec.type == "integer" && number?.let { it < 0 || it % 1.0 != 0.0 } == true) {
                diagnostic("INVALID_INTEGER", "error", path, field.token, key, "Expected a non-negative integer", "Use a non-negative integer")
            }
            if (spec.unit != null && (raw is Number || (raw as? String)?.toDoubleOrNull() != null) && raw.toString().toDoubleOrNull() != 0.0) {
                diagnostic("IMPLICIT_UNIT", "warning", path, field.token, key,
                    "Bare numbers use ${spec.unit}, not universally dp", "Write an explicit dp/sp/px suffix")
            }
        }

        private fun diagnostic(code: String, severity: String, path: String, token: LayoutSource.Token?, property: String?, actual: String, suggestion: String, expected: String? = null) {
            if (severity == "error") errors++
            if (severity == "unknown") unknowns++
            if (diagnostics.size >= 100) { truncated = true; return }
            diagnostics.add(obj("code" to code, "severity" to severity, "file" to file,
                "line" to token?.line, "column" to token?.column, "nodePath" to path.take(500),
                "id" to nodeIds[path]?.take(200), "expected" to expected,
                "property" to property, "actual" to actual.take(500), "suggestion" to suggestion.take(500)))
        }
    }

    private val DIMENSION = Regex("[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?(?:dp|sp|px|pt|in|mm|%[wh]?)?")
    private val COLOR = Regex("#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})")
    private fun validDimension(value: String, size: Boolean): Boolean =
        DIMENSION.matches(value) || (size && value in LayoutEnums.sizeTokens)
    private fun validEnum(value: String, spec: LayoutSchema.Attribute): Boolean {
        if (spec.name == "scaleType") return value.trim() in LayoutEnums.scaleType ||
            value.trim().lowercase(java.util.Locale.ROOT).replace('-', '_') in LayoutEnums.scaleType
        if (value.toDoubleOrNull() != null) return spec.type == "visibility" || LayoutEnums.enumMapForAttr(spec.name) != null
        val enums = LayoutSchema.enumValues(spec)
        val parts = if (spec.flags) value.split('|').map(String::trim) else listOf(value)
        return parts.isNotEmpty() && parts.all { part -> enums.any { it.equals(part, true) } }
    }
    private fun suggestion(key: String): String? {
        if (key.length > 80) return null
        return LayoutSchema.attributes.map { it.name }
            .minByOrNull { distance(it, key) }?.takeIf { distance(it, key) <= 2 }?.let { "Did you mean '$it'?" }
    }
    private fun distance(a: String, b: String): Int {
        var previous = IntArray(b.length + 1) { it }
        for (i in a.indices) {
            val current = IntArray(b.length + 1); current[0] = i + 1
            for (j in b.indices) current[j + 1] = minOf(current[j] + 1, previous[j + 1] + 1, previous[j] + if (a[i] == b[j]) 0 else 1)
            previous = current
        }
        return previous[b.length]
    }
    private fun failure(file: String, code: String, message: String) = obj(
        "file" to file, "hasErrors" to true, "complete" to false, "nodesChecked" to 0,
        "errors" to 1, "unknowns" to 0, "truncated" to false,
        "diagnostics" to array(listOf(obj("code" to code, "severity" to "error", "file" to file,
            "nodePath" to "root", "actual" to message, "suggestion" to "Fix source/read error before layout validation"))))

    private fun java.io.InputStream.readBytesBounded(limit: Int): ByteArray {
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(4096)
        while (output.size() < limit) {
            val count = read(buffer, 0, minOf(buffer.size, limit - output.size()))
            if (count < 0) break
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }
    private fun array(values: Iterable<*>): LuaTable = LuaTable().apply {
        values.forEachIndexed { index, value -> set(index + 1, lua(value)) }
    }
    private fun obj(vararg fields: Pair<String, Any?>): LuaTable = LuaTable().apply {
        fields.forEach { (key, value) -> if (value != null) set(key, lua(value)) }
    }
    private fun lua(value: Any?): LuaValue = when (value) {
        null -> LuaValue.NIL
        is LuaValue -> value
        is Boolean -> LuaValue.valueOf(value)
        is Int -> LuaValue.valueOf(value)
        else -> LuaValue.valueOf(value.toString())
    }
}
