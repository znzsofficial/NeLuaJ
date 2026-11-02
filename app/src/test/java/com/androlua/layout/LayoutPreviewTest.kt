package com.androlua.layout

import android.content.Context
import android.content.ContextWrapper
import android.util.DisplayMetrics
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.androlua.LuaContext
import com.androlua.LuaLayout
import com.androlua.adapter.LuaRecyclerAdapter
import com.nekolaska.ktx.toLuaInstance
import org.junit.Assert.*
import org.junit.Test
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.lib.OneArgFunction
import org.luaj.lib.TwoArgFunction
import org.luaj.lib.jse.JsePlatform
import java.lang.reflect.Proxy

/**
 * Executes the real production loader, parser, params applier and hook traversal.
 * Android's local-test stubs cannot initialize Coil or prove visuals: allocate the
 * loader shell without its Android/Coil constructor and install its real components.
 * Views record platform writes; no production inflation/attribute method is mocked.
 */
class LayoutPreviewTest {
    class RecordingGroup(context: Context) : ViewGroup(context) {
        val added = mutableListOf<View>()
        override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {}
        override fun addView(child: View) { added += child }
        override fun setLayoutParams(params: LayoutParams) {}
    }

    class RecordingView(context: Context) : View(context) {
        var recordedAlpha = 1f
        var recordedEnabled = true
        var recordedPadding = listOf(0, 0, 0, 0)
        var recordedParams: ViewGroup.LayoutParams? = null
        override fun setAlpha(alpha: Float) { recordedAlpha = alpha }
        override fun setEnabled(enabled: Boolean) { recordedEnabled = enabled }
        override fun setPadding(left: Int, top: Int, right: Int, bottom: Int) {
            recordedPadding = listOf(left, top, right, bottom)
        }
        override fun setLayoutParams(params: ViewGroup.LayoutParams) { recordedParams = params }
    }

    private val unsafeClass = Class.forName("sun.misc.Unsafe")
    private val unsafe = unsafeClass.getDeclaredField("theUnsafe").let {
        it.isAccessible = true
        it.get(null)
    }

    private fun setField(target: Any, name: String, value: Any) {
        target.javaClass.getDeclaredField(name).apply { isAccessible = true }.set(target, value)
    }

    private fun fixture(): Triple<LuaLayout, Context, MutableList<String>> {
        val context = ContextWrapper(null)
        val errors = mutableListOf<String>()
        val globals = JsePlatform.standardGlobals()
        val luaContext = Proxy.newProxyInstance(javaClass.classLoader, arrayOf(LuaContext::class.java)) { _, method, args ->
            when (method.name) {
                "sendError", "sendMsg" -> { errors += args?.firstOrNull().toString(); null }
                "getLuaState" -> globals
                "getWidth", "getHeight" -> 100
                "toString" -> "LayoutPreviewTest context"
                else -> null
            }
        } as LuaContext
        val metrics = DisplayMetrics().apply { density = 2f; scaledDensity = 2f }
        val ids = hashMapOf<String, Int>()
        val values = LayoutValueParser(context, luaContext, metrics)
        val loader = unsafeClass.getMethod("allocateInstance", Class::class.java)
            .invoke(unsafe, LuaLayout::class.java) as LuaLayout
        setField(loader, "initialContext", context)
        setField(loader, "luaContext", luaContext)
        setField(loader, "dm", metrics)
        setField(loader, "ids", ids)
        setField(loader, "view", hashMapOf<String, LuaValue>())
        setField(loader, "values", values)
        setField(loader, "viewFactory", LayoutViewFactory(context, luaContext, context.toLuaInstance()))
        setField(loader, "paramsApplier", LayoutParamsApplier(luaContext, values, ids))
        return Triple(loader, context, errors)
    }

    private fun paramsFactory() = object : TwoArgFunction() {
        override fun call(width: LuaValue, height: LuaValue): LuaValue =
            ViewGroup.LayoutParams(width.toint(), height.toint()).toLuaInstance()
    }

    @Test fun recyclerAdapterInflatesRootMarginsWithRecyclerParams() {
        val (loader, context, errors) = fixture()
        val host = RecordingView(context)
        val layout = LuaTable().apply {
            set(1, object : OneArgFunction() {
                override fun call(arg: LuaValue) = host.toLuaInstance()
            })
            set("layout_width", -1)
            set("layout_height", -2)
            // Pixel values isolate parent-param/margin behavior: Android's local
            // TypedValue.applyDimension stub cannot verify dp conversion.
            set("layout_marginBottom", 12)
            set("layout_marginLeft", 20)
        }
        // Only bypass the Android/Coil constructor; execute the real adapter's
        // onCreateViewHolder -> LuaLayout -> margin applier, not a source regex.
        val adapter = unsafeClass.getMethod("allocateInstance", Class::class.java)
            .invoke(unsafe, LuaRecyclerAdapter::class.java) as LuaRecyclerAdapter
        setField(adapter, "mLayout", layout)
        setField(adapter, "loadlayout", loader)
        val holder = adapter.onCreateViewHolder(RecordingGroup(context), 0)
        assertSame(host, holder.itemView)
        val params = host.recordedParams as RecyclerView.LayoutParams
        assertEquals(-1, params.width)
        assertEquals(-2, params.height)
        assertEquals(12, params.bottomMargin)
        assertEquals(20, params.leftMargin)
        assertTrue(errors.toString(), errors.isEmpty())
    }

    @Test fun productionAttributesIdsAndDecorationOrderAreActuallyExecuted() {
        val (loader, context, errors) = fixture()
        val host = RecordingView(context)
        val source = LuaTable().apply {
            set(1, object : OneArgFunction() {
                override fun call(arg: LuaValue): LuaValue = host.toLuaInstance()
            })
            set("id", "title")
            set("alpha", "0.25")
            set("enabled", "false")
            set("padding", 7)
            set("layout_width", 123)
        }
        val env = LuaTable()
        val seen = mutableListOf<String>()
        val hooks = LuaTable().apply {
            set("onCreated", object : TwoArgFunction() {
                override fun call(view: LuaValue, layout: LuaValue): LuaValue {
                    assertSame(source, layout)
                    assertEquals(1f, host.recordedAlpha)
                    seen += "created"
                    return LuaValue.NIL
                }
            })
            set("onLoaded", object : TwoArgFunction() {
                override fun call(view: LuaValue, layout: LuaValue): LuaValue {
                    assertSame(source, layout)
                    assertSame(host, env["title"].touserdata())
                    assertEquals(0.25f, host.recordedAlpha)
                    assertFalse(host.recordedEnabled)
                    assertEquals(listOf(7, 7, 7, 7), host.recordedPadding)
                    assertEquals(123, host.recordedParams!!.width)
                    seen += "loaded"
                    return LuaValue.NIL
                }
            })
        }
        assertSame(host, loader.loadDecorated(source, env, hooks, paramsFactory()).touserdata())
        assertEquals(listOf("created", "loaded"), seen)
        assertTrue(errors.toString(), errors.isEmpty())
        assertSame(host, loader.get("title")!!.touserdata())
        assertTrue(loader.id.containsKey("title"))
        // Ordinary loads must not retain editor callbacks from a prior generation.
        loader.load(source, env, paramsFactory())
        assertEquals(listOf("created", "loaded"), seen)
    }

    @Test fun hookFailureRestoresScopeAndCustomParamsStillUseProductionAttributes() {
        val (loader, context, errors) = fixture()
        val host = RecordingView(context)
        val layout = LuaTable().apply {
            set(1, object : OneArgFunction() {
                override fun call(arg: LuaValue) = host.toLuaInstance()
            })
            set("layout_height", 87)
        }
        val hooks = LuaTable().apply {
            set("onCreated", object : TwoArgFunction() {
                override fun call(view: LuaValue, layout: LuaValue): LuaValue = error("decoration failed")
            })
        }
        assertTrue(runCatching { loader.loadDecorated(layout, LuaTable(), hooks, paramsFactory()) }.isFailure)
        loader.load(layout, LuaTable(), paramsFactory())
        assertEquals(87, host.recordedParams!!.height)
        var customFactoryCalled = false
        hooks.set("onCreated", LuaValue.NIL)
        hooks.set("layoutParamsFactory", object : TwoArgFunction() {
            override fun call(paramsClass: LuaValue, source: LuaValue): LuaValue {
                assertSame(layout, source)
                customFactoryCalled = true
                return paramsFactory()
            }
        })
        loader.loadDecorated(layout, LuaTable(), hooks, LuaValue.NIL)
        assertTrue(customFactoryCalled)
        assertEquals(87, host.recordedParams!!.height)
        assertTrue(errors.toString(), errors.isEmpty())
    }

    @Test fun recursiveChildrenUseSameProductionLoaderAndDecorationScope() {
        val (loader, context, errors) = fixture()
        val parent = RecordingGroup(context)
        val child = RecordingView(context)
        val childLayout = LuaTable().apply {
            set(1, object : OneArgFunction() {
                override fun call(arg: LuaValue) = child.toLuaInstance()
            })
            set("id", "child")
            set("alpha", 0.5)
            set("layout_height", 56)
        }
        val parentLayout = LuaTable().apply {
            set(1, object : OneArgFunction() {
                override fun call(arg: LuaValue) = parent.toLuaInstance()
            })
            set(2, childLayout)
        }
        val visited = mutableListOf<LuaValue>()
        val hooks = LuaTable().apply {
            set("onLoaded", object : TwoArgFunction() {
                override fun call(view: LuaValue, layout: LuaValue): LuaValue {
                    visited += layout
                    return LuaValue.NIL
                }
            })
        }
        val env = LuaTable()
        loader.loadDecorated(parentLayout, env, hooks, paramsFactory())
        assertEquals(listOf(childLayout, parentLayout), visited)
        assertEquals(listOf(child), parent.added)
        assertSame(child, env["child"].touserdata())
        assertEquals(0.5f, child.recordedAlpha)
        assertEquals(56, child.recordedParams!!.height)
        assertTrue(errors.toString(), errors.isEmpty())
    }
}
