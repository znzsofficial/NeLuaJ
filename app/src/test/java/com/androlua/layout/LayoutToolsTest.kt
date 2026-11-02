package com.androlua.layout

import org.junit.Assert.*
import org.junit.Test
import org.luaj.LuaTable
import org.luaj.LuaValue
import java.io.File

class LayoutToolsTest {
    private fun check(source: String, parent: String = "") = LayoutTools.checkSource(source, "example.lua", parent)
    private fun diagnostics(report: LuaTable): List<LuaValue> = (1..report["diagnostics"].length()).map { report["diagnostics"][it] }
    private fun codes(report: LuaTable) = diagnostics(report).map { it["code"].tojstring() }

    @Test fun minimalLiteralLayoutIsCheckedWithoutExecution() {
        val report = check("""
            error('MUST NOT RUN')
            import "android.widget.LinearLayout"
            return { LinearLayout, orientation="vertical", layout_width="match", layout_height="wrap",
              { TextView, id="title", text="Hello", textSize="16sp" } }
        """.trimIndent())
        assertFalse(report.tojstring(), report["hasErrors"].toboolean())
        assertTrue(codes(report).toString(), report["complete"].toboolean())
        assertEquals(2, report["nodesChecked"].toint())
    }

    @Test fun typoHasLocationAndSuggestion() {
        val report = check("return { TextView,\n textSzie='16sp' }")
        val diagnostic = diagnostics(report).single { it["code"].tojstring() == "UNKNOWN_PROPERTY" }
        assertTrue(report["hasErrors"].toboolean())
        assertEquals("example.lua", diagnostic["file"].tojstring())
        assertEquals(2, diagnostic["line"].toint())
        assertEquals(2, diagnostic["column"].toint())
        assertTrue(diagnostic["suggestion"].tojstring().contains("textSize"))
    }

    @Test fun layoutParamsDependOnParentNotChildClass() {
        assertTrue("WRONG_PARENT" in codes(check("return {FrameLayout, {TextView,layout_weight=1}}")))
        assertFalse("WRONG_PARENT" in codes(check("return {LinearLayout, {TextView,layout_weight=1}}")))
        assertTrue("UNKNOWN_PARENT" in codes(check("return {TextView,layout_weight=1}")))
        assertFalse("UNKNOWN_PARENT" in codes(check("return {TextView,layout_weight=1}", "LinearLayout")))
    }

    @Test fun valuesAndUnitsAreValidatedPerProperty() {
        val report = check("return {LinearLayout,orientation='sideways',padding=16,{TextView,textSize=18,visibility='none'}}")
        assertEquals(2, codes(report).count { it == "INVALID_VALUE" })
        assertEquals(2, codes(report).count { it == "IMPLICIT_UNIT" })
        assertTrue(diagnostics(report).any { it["property"].tojstring() == "textSize" && it["actual"].tojstring().contains("sp") })
        assertTrue(diagnostics(report).any { it["property"].tojstring() == "padding" && it["actual"].tojstring().contains("px") })
        assertFalse(check("return {TextView,gravity='center|end',inputType='text|textMultiLine'}")["hasErrors"].toboolean())
    }

    @Test fun duplicateIdsAndMissingTargetsAreErrorsButForwardTargetsWarn() {
        val report = check("return {RelativeLayout,{TextView,id='a',layout_below='b'},{TextView,id='b'},{TextView,id='b',layout_below='missing'}}")
        assertTrue(codes(report).containsAll(listOf("DUPLICATE_ID", "UNRESOLVED_ID", "FORWARD_ID")))
        assertEquals("warning", diagnostics(report).single { it["code"].tojstring() == "FORWARD_ID" }["severity"].tojstring())
    }

    @Test fun bindingsDoNotLeakBetweenIndependentLoads() {
        val report = check("local a=loadlayout({TextView,id='title'})\nlocal b=loadlayout({RelativeLayout,{TextView,layout_below='title'}})")
        assertTrue("UNRESOLVED_ID" in codes(report))
        assertFalse("DUPLICATE_ID" in codes(check("loadlayout({TextView,id='a'});loadlayout({TextView,id='a'})")))
    }

    @Test fun unknownExpressionsDoNotExecuteOrProduceFalseSuccess() {
        val report = check("return {CustomView,textSize=calculate(),require('remote'),[key()]=true}")
        assertFalse(report["complete"].toboolean())
        assertFalse(diagnostics(report).joinToString { it["actual"].tojstring() }, report["hasErrors"].toboolean())
        assertTrue(codes(report).toString(), codes(report).containsAll(listOf("UNKNOWN_WIDGET", "DYNAMIC_VALUE", "DYNAMIC_CHILD", "DYNAMIC_KEY")))
        assertFalse(check("local x=makeLayout();return x")["complete"].toboolean())
    }

    @Test fun missingTargetWithDynamicChildIsUnknownNotDefiniteError() {
        val report = check("return {RelativeLayout,require('child'),{TextView,layout_below='dynamic'}}")
        assertFalse(report["hasErrors"].toboolean())
        assertEquals("unknown", diagnostics(report).single { it["code"].tojstring() == "UNRESOLVED_ID" }["severity"].tojstring())
    }

    @Test fun childSemanticsDistinguishScrollLeafAndAdapterTemplates() {
        assertTrue("SINGLE_CHILD" in codes(check("return {ScrollView,{TextView},{TextView}}")))
        assertTrue("LEAF_CHILDREN" in codes(check("return {TextView,{TextView}}")))
        val adapter = check("return {ListView,{LinearLayout,{TextView,id='repeated'},{TextView,id='repeated'}}}")
        assertTrue("ADAPTER_TEMPLATE" in codes(adapter))
        assertFalse("DUPLICATE_ID" in codes(adapter))
    }

    @Test fun stringsCommentsAndFunctionBodiesDoNotBecomeTableFields() {
        val report = check("""
            -- return { NotAView }
            return {TextView, text=[=[return {not a layout}, ; }]=],
              onClick=function(v)
                local fake={a=1,b=2}
                if v then for i=1,2 do print(i) end end
                return {ignored=true}
              end,
              textSize="16sp"}
        """.trimIndent())
        assertFalse(codes(report).toString(), report["hasErrors"].toboolean())
        assertEquals(1, report["nodesChecked"].toint())
    }

    @Test fun bracketKeysAndEscapedIdsAreDecoded() {
        val report = check("return {[1]=LinearLayout,['orientation']='vertical',[2]={TextView,id='a\\098'},[3]={TextView,id='ab'}}")
        assertTrue(diagnostics(report).joinToString { it["code"].tojstring() + ":" + it["actual"].tojstring() }, "DUPLICATE_ID" in codes(report))
    }

    @Test fun syntaxAndResourceLimitsCannotReportSuccess() {
        assertTrue(check("return {TextView text='missing comma'}")["hasErrors"].toboolean())
        val long = check("--" + "x".repeat(128 * 1024))
        assertEquals(listOf("SOURCE_LIMIT"), codes(long))
        assertTrue(check("return " + "{".repeat(100) + "TextView" + "}".repeat(100))["hasErrors"].toboolean())
    }

    @Test fun emptyAndNonLayoutSourceRemainExplicitlyUnknown() {
        assertFalse(check("local x=1")["complete"].toboolean())
        assertTrue("MISSING_VIEW_CLASS" in codes(check("return {ok=true}")))
    }

    @Test fun reflectionIsOnlyForShippedClassesAndDoesNotInstantiateAnything() {
        val known = LayoutTools.describe("TextView", "LinearLayout")
        assertTrue(known["knownWidget"].toboolean())
        assertTrue((1..known["attributes"].length()).any { known["attributes"][it]["name"].tojstring() == "layout_weight" })
        val other = LayoutTools.describe("TextView", "FrameLayout")
        assertFalse((1..other["attributes"].length()).any { other["attributes"][it]["name"].tojstring() == "layout_weight" })
        assertFalse(LayoutTools.describe("malicious.project.TextView", "")["knownWidget"].toboolean())
        assertFalse(LayoutTools.describe("java.lang.Runtime", "")["knownWidget"].toboolean())
    }

    @Test fun reflectedButUndescribedPropertiesAreNotCalledInvalid() {
        val report = check("return {TextView,letterSpacing=0.1}")
        assertFalse(report["hasErrors"].toboolean())
        assertTrue("UNDESCRIBED_PROPERTY" in codes(report))
        assertFalse(report["complete"].toboolean())
    }

    @Test fun checkFileIsReadOnlyBoundedAndReportsMissingFiles() {
        val file = File.createTempFile("layout-check", ".lua")
        try {
            file.writeText("error('not executed');return {TextView,text='hello'}", Charsets.UTF_8)
            assertFalse(LayoutTools.checkFile(file.absolutePath, "")["hasErrors"].toboolean())
            assertTrue(file.readText().startsWith("error("))
        } finally { file.delete() }
        assertEquals(listOf("READ_ERROR"), codes(LayoutTools.checkFile(file.absolutePath, "")))
    }

    @Test fun schemaAliasesAreUniqueAndEnumsUseTheRuntimeRegistry() {
        val names = LayoutSchema.attributes.flatMap { it.aliases + it.name }
        assertEquals(names.size, names.distinct().size)
        for (attribute in listOf("gravity", "inputType", "imeOptions", "orientation")) {
            assertEquals(LayoutEnums.enumMapForAttr(attribute)!!.keys, LayoutSchema.attribute(attribute)!!.enums)
        }
        assertEquals("textColor", LayoutSchema.attribute("TextColor")!!.name)
        assertEquals("sp", LayoutSchema.attribute("textSize")!!.unit)
    }

    @Test fun schemaCoversAllDedicatedInflaterBranches() {
        val assets = sequenceOf(File("src/main"), File("app/src/main")).first { it.isDirectory }
        val source = File(assets, "java/com/androlua/LuaLayout.kt").readText()
            .substringAfter("when (keyString)").substringBefore("// layout_* ")
        val labels = Regex("(?m)^ {12}((?:\"[^\"]+\"[ ,]*\\s*)+)->")
            .findAll(source).flatMap { match -> Regex("\"([^\"]+)\"").findAll(match.groupValues[1]).map { it.groupValues[1] } }.toList()
        assertTrue(labels.size > 50)
        for (label in labels) assertNotNull("Missing contract for $label", LayoutSchema.attribute(label))
    }

    @Test fun shippedLayoutSamplesAreReadWithoutRunningTheirImportsOrFactories() {
        val assets = sequenceOf(File("src/main/assets"), File("app/src/main/assets")).first { it.isDirectory }
        for (name in listOf("main_layout.lua", "layouthelper_layout.lua")) {
            val report = LayoutTools.checkFile(File(assets, "res/layout/$name").path, "")
            assertFalse("$name: ${diagnostics(report).map { it["actual"].tojstring() }}", "SOURCE_ERROR" in codes(report))
            assertTrue(name, report["nodesChecked"].toint() > 0)
        }
    }

    @Test fun luaJppLambdaArgumentsAndSwitchCasesDoNotSplitLayoutFields() {
        val report = check("""
            return {TextView,
              onClick=(lambda a,b -> print(a,b)),
              onLongClick=function(v)
                switch v
                  case 1,2 print(v)
                  default print('other')
                end
              end,
              textSzie='16sp'}
        """.trimIndent())
        assertTrue(diagnostics(report).map { it["actual"].tojstring() }.toString(), "UNKNOWN_PROPERTY" in codes(report))
        assertFalse("SOURCE_ERROR" in codes(report))
        assertEquals(1, report["nodesChecked"].toint())
    }

    @Test fun tableSemanticsKeepOnlyTheLastValueAndDropNilFields() {
        val report = check("return loadlayout({TextView,textSize='bad',textSize='16sp',nonsense=nil})")
        assertFalse(codes(report).toString(), report["hasErrors"].toboolean())
        assertTrue(report["complete"].toboolean())
        assertTrue("DUPLICATE_PROPERTY" in codes(report))
        assertFalse(check("return {ImageView,scaleType='center-crop'}")["hasErrors"].toboolean())
    }

    @Test fun actualLuaJavaBridgePreservesTypesAndPortableJsonRoundTrip() {
        val globals = org.luaj.lib.jse.JsePlatform.standardGlobals()
        // Android's org.json is stubbed in local JVM tests. Use the existing portable
        // codec to verify the report shape; device org.json serialization is not claimed.
        com.androlua.SandboxLibraries.install(globals)
        globals.load("""
            local tools=luajava.bindClass('com.androlua.layout.LayoutTools')
            local description=tools.describe('TextView','LinearLayout')
            assert(description.knownWidget == true)
            local report=tools.checkSource('return {TextView,textSzie=16}', 'bridge.lua','')
            assert(report.hasErrors == true)
            local decoded=json.decode(json.encode(report))
            assert(decoded.hasErrors == true)
            assert(decoded.diagnostics[1].property == 'textSzie')
        """.trimIndent(), "@layout_bridge_test").call()
    }

    @Test fun omittedDoInLuaJppDoesNotConsumeFollowingAttributes() {
        val report = check("""
            return {TextView,onClick=function(v)
              for i=1,2
                print(i)
              end
              do print('later block') end
            end,textSzie='16sp'}
        """.trimIndent())
        assertTrue(codes(report).toString(), "UNKNOWN_PROPERTY" in codes(report))
        assertFalse("SOURCE_ERROR" in codes(report))
    }

    @Test fun punctuationAndKeywordsInsideStringsRemainLiteralValues() {
        for (text in listOf(",", ";", "lambda", "\\\\", "function", "{")) {
            val report = check("return {TextView,text='$text',textSzie='16sp'}")
            assertFalse("$text: ${codes(report)}", "SOURCE_ERROR" in codes(report))
            assertTrue("$text: ${codes(report)}", "UNKNOWN_PROPERTY" in codes(report))
            assertFalse("$text: ${codes(report)}", "DYNAMIC_VALUE" in codes(report))
        }
    }

    @Test fun numericStringsAreNotUniversalEnumValues() {
        assertTrue(check("return {TextView,textStyle='123',ellipsize='7'}")["hasErrors"].toboolean())
        assertFalse(check("return {TextView,visibility='8',gravity='17'}")["hasErrors"].toboolean())
    }
}
