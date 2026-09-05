package com.androlua

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.luaj.Globals
import org.luaj.android.json
import org.luaj.lib.jse.JsePlatform
import java.io.File

class AgentConversationStoreTest {

    private fun createGlobals(assets: File): Globals {
        val globals = JsePlatform.standardGlobals()
        globals.load(json())
        return globals
    }

    private fun loadStore(globals: Globals, assets: File) {
        val file = File(assets, "mods/agent/ConversationStore.lua")
        val chunk = globals.load(file.readText(), "@ConversationStore.lua")
        val store = chunk.call()
        globals.set("ConversationStore", store)
    }

    @Test
    fun testConversationStoreScopeAndStableIds() {
        val assets = sequenceOf(File("src/main/assets"), File("app/src/main/assets"))
            .first { it.isDirectory }
        val globals = JsePlatform.standardGlobals()
        loadStore(globals, assets)

        val chunk = globals.load(
            """
            local ok, err = pcall(function()
            local store = {}
            local currentProject = "/project/A"

            ConversationStore.configure({
                getData = function(key, def) return store[key] or def end,
                setData = function(key, val) store[key] = val; return true end,
                encode = function(v) return v end,
                decode = function(v) return v end,
                getProjectPath = function() return currentProject end,
                normalizeProjectPath = function(p) return p end,
            })

            -- Create in Project A
            local c1 = ConversationStore.create("Conv A1")
            assert(c1.id ~= nil and c1.id ~= "", "id should exist")
            assert(c1.name == "Conv A1")
            assert(c1.projectPath == "/project/A")

            local listA = ConversationStore.list("/project/A")
            assert(#listA == 1)
            assert(listA[1].id == c1.id)

            -- Switch to Project B
            currentProject = "/project/B"
            local listB = ConversationStore.list("/project/B")
            assert(#listB == 0)

            local c2 = ConversationStore.create("Conv B1")
            assert(c2.projectPath == "/project/B")
            assert(c2.id ~= c1.id)

            local listB2 = ConversationStore.list("/project/B")
            assert(#listB2 == 1)
            assert(listB2[1].id == c2.id)

            -- Current conversation tracking per project
            local curB = ConversationStore.current("/project/B")
            assert(curB.id == c2.id)

            local curA = ConversationStore.current("/project/A")
            assert(curA.id == c1.id)

            -- Save conversation messages
            local msgs = { { role = "user", content = "hello world" } }
            local saved = ConversationStore.save(c1.id, msgs, "/project/A")
            assert(saved == true)

            local curAUpdated = ConversationStore.get(c1.id, "/project/A")
            assert(#curAUpdated.messages == 1)
            assert(curAUpdated.messages[1].content == "hello world")
            assert(curAUpdated.name == "Conv A1") -- custom name is preserved

            -- Auto-naming for empty/new conversation
            local cEmpty = ConversationStore.create("")
            ConversationStore.save(cEmpty.id, msgs, "/project/B")
            local curEmpty = ConversationStore.get(cEmpty.id, "/project/B")
            assert(curEmpty.name == "hello world")

            -- Rename
            ConversationStore.rename(c1.id, "Renamed A1", "/project/A")
            local curARenamed = ConversationStore.get(c1.id, "/project/A")
            assert(curARenamed.name == "Renamed A1")

            -- Delete
            local deleted = ConversationStore.delete(c1.id, "/project/A")
            assert(deleted == true)
            assert(#ConversationStore.list("/project/A") == 0)
            assert(ConversationStore.current("/project/A") == nil)

            -- Ensure Project B untouched
            local listBFinal = ConversationStore.list("/project/B")
            assert(#listBFinal == 2) -- c2 and cEmpty
            local curBFinal = ConversationStore.current("/project/B")
            assert(curBFinal.id == cEmpty.id)
            end)
            if not ok then
                print("LUA_FAIL_TRACE:", tostring(err))
                error(tostring(err))
            end
            """.trimIndent(),
            "@test_store.lua"
        )
        chunk.call()
    }

    @Test
    fun testLegacyMigration() {
        val assets = sequenceOf(File("src/main/assets"), File("app/src/main/assets"))
            .first { it.isDirectory }
        val globals = JsePlatform.standardGlobals()
        loadStore(globals, assets)

        globals.load(
            """
            local store = {
                ai_conversations = {
                    { name = "Old Conv 1", messages = { { role = "user", content = "Hi" } } }
                },
                ai_current_conv = "1"
            }

            ConversationStore.configure({
                getData = function(key, def) return store[key] or def end,
                setData = function(key, val) store[key] = val; return true end,
                encode = function(v) return v end,
                decode = function(v) return v end,
                getProjectPath = function() return "/default/project" end,
                normalizeProjectPath = function(p) return p end,
            })

            local list = ConversationStore.list("/default/project")
            assert(#list == 1)
            local item = list[1].conversation
            assert(item.id ~= nil and item.id ~= "")
            assert(item.projectPath == "/default/project")
            assert(item.name == "Old Conv 1")

            local cur = ConversationStore.current("/default/project")
            assert(cur ~= nil)
            assert(cur.id == item.id)
            """.trimIndent(),
            "@test_legacy_migration.lua"
        ).call()
    }

    @Test
    fun accidentalEmptySaveDoesNotEraseMessages() {
        val assets = sequenceOf(File("src/main/assets"), File("app/src/main/assets"))
            .first { it.isDirectory }
        val globals = JsePlatform.standardGlobals()
        loadStore(globals, assets)

        globals.load(
            """
            local store = {}
            ConversationStore.configure({
                getData = function(key, def) return store[key] or def end,
                setData = function(key, value) store[key] = value; return true end,
                encode = function(value) return value end,
                decode = function(value) return value end,
                getProjectPath = function() return "/project" end,
                normalizeProjectPath = function(path) return path end,
            })

            local conversation = ConversationStore.create("Persistent")
            local messages = { { role = "user", content = "must survive" } }
            assert(ConversationStore.save(conversation.id, messages, "/project") == true)
            assert(ConversationStore.save(conversation.id, {}, "/project") == false)
            assert(#ConversationStore.get(conversation.id, "/project").messages == 1)
            ConversationStore.invalidate()
            assert(#ConversationStore.get(conversation.id, "/project").messages == 1)
            assert(ConversationStore.clear(conversation.id, "/project") == true)
            assert(#ConversationStore.get(conversation.id, "/project").messages == 0)
            """.trimIndent(),
            "@empty_save_guard_test"
        ).call()
    }
}
