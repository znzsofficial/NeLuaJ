package org.luaj.android

import com.nekolaska.ktx.firstArg
import com.nekolaska.ktx.secondArg
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import org.luaj.LuaError
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.lib.OneArgFunction
import org.luaj.lib.TwoArgFunction
import org.luaj.lib.jse.CoerceLuaToJava
import org.luaj.lib.jse.LuajavaLib
import java.lang.Exception

/**
 * Created by nirenr on 2020/1/16.
 */
class json : TwoArgFunction() {
    override fun call(modname: LuaValue?, env: LuaValue): LuaValue? {
        val json = LuaTable()
        json.set("decode", decode())
        json.set("encode", encode())
        env.set("json", json)
        if (!env.get("package").isnil()) env.get("package").get("loaded").set("json", json)
        return NIL
    }

    private class decode : OneArgFunction() {
        override fun call(arg: LuaValue): LuaValue? {
            return decode(arg.tojstring())
        }
    }

    private class encode : OneArgFunction() {
        override fun call(arg: LuaValue): LuaValue? {
            return valueOf(encode(arg))
        }
    }

    companion object {
        fun encode(value: LuaValue): String {
            val map: Any = toJson(value)
            return map.toString()
        }

        private fun toJson(value: LuaValue): Any {
            val t = value.checktable()
            if (t.length() == t.size()) {
                val arr = JSONArray()
                for (i in 1 until t.length() + 1) {
                    val v = t.get(i)
                    if (v.istable()) arr.put(toJson(v))
                    else arr.put(CoerceLuaToJava.coerce(v, Any::class.java))
                }
                return arr
            }
            val map = JSONObject()
            var ret = value.next(NIL)
            while (ret !== NIL) {
                val k = ret.firstArg()
                val v = ret.secondArg()
                try {
                    if (v.istable()) map.put(k.tojstring(), toJson(v))
                    else map.put(k.tojstring(), CoerceLuaToJava.coerce(v, Any::class.java))
                } catch (e: JSONException) {
                    e.printStackTrace()
                }
                ret = value.next(k)
            }
            return map
        }

        fun decode(text: String): LuaValue? {
            try {
                if (text.startsWith("[")) return LuajavaLib.asTable(JSONArray(text))
                return LuajavaLib.asTable(JSONObject(text))
            } catch (e: Exception) {
                e.printStackTrace()
                throw LuaError(e.message)
            }
            //return NIL;
        }
    }
}
