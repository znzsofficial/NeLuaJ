import com.android.build.api.dsl.Packaging
import org.gradle.api.tasks.testing.Test
import org.gradle.jvm.tasks.Jar
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.Properties
import java.util.zip.ZipFile

plugins {
    alias(libs.plugins.androidApplication)
    alias(libs.plugins.kotlinAndroid)
}

val versionPropsFile = layout.projectDirectory.file("version.properties")
val versionProps = Properties().apply {
    versionPropsFile.asFile.inputStream().use { load(it) }
}
val verCode = versionProps.getProperty("VERSION_CODE").toInt()

// Deliberate maintenance operation, never a dependency of assemble/publish.
// Run separately, then build in a NEW invocation so Android reads the new code.
tasks.register("bumpVersionCode") {
    group = "versioning"
    description = "Increment VERSION_CODE explicitly; run alone, then build in a new invocation."
    val requestedTasks = gradle.startParameter.taskNames.toList()
    doLast {
        check(requestedTasks.size == 1) {
            "Run :app:bumpVersionCode alone, then assemble in a separate Gradle invocation."
        }
        val current = Properties().apply {
            versionPropsFile.asFile.inputStream().use { load(it) }
        }
        val next = Math.addExact(current.getProperty("VERSION_CODE").toInt(), 1)
        check(next > 0 && next <= 2_100_000_000) { "VERSION_CODE exceeds the Android limit." }
        current.setProperty("VERSION_CODE", next.toString())
        versionPropsFile.asFile.outputStream().use { current.store(it, null) }
        logger.lifecycle("VERSION_CODE=$next; rebuild in a new Gradle invocation.")
    }
}

android {
    namespace = "github.znzsofficial.neluaj"
    //compileSdk = 36
    compileSdk {
        version = release(37)
    }

    defaultConfig {
        applicationId = "github.znzsofficial.neluaj"
        minSdk = 26
        //noinspection OldTargetApi
        targetSdk = 33
        val formatter = DateTimeFormatter.ofPattern("yyyyMMdd_HHmm")
        val formattedDateTime = LocalDateTime.now().format(formatter)
        versionCode = verCode
        versionName = "${verCode}_$formattedDateTime"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    buildTypes {
        release {
            isShrinkResources = false
            isMinifyEnabled = false
            multiDexEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    packaging {
        resources {
            excludes.add("META-INF/androidx/emoji2/emoji2/LICENSE.txt")
        }
    }
    kotlin {
        jvmToolchain(17)
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
            freeCompilerArgs.addAll(
                "-Xno-call-assertions",
                "-Xno-receiver-assertions",
                "-Xno-param-assertions"
            )
        }
        compileOptions {
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
        }
    }
    testOptions {
        unitTests {
            isReturnDefaultValues = true
        }
    }
    configurations.all {
        exclude(group = "androidx.asynclayoutinflater", module = "asynclayoutinflater")
        exclude(group = "androidx.localbroadcastmanager", module = "localbroadcastmanager")
        exclude(group = "androidx.slidingpanelayout", module = "slidingpanelayout")
    }
    androidComponents {
        onVariants(selector().all()) { variant ->
            variant.outputs.forEach { output ->
                val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd_HH_mm_ss")
                val formattedDateTime = LocalDateTime.now().format(formatter)
                val apkName = "${project.name}-${defaultConfig.versionCode}-$formattedDateTime.APK"
                output.outputFileName.set(apkName)
            }
        }
    }
}

// One registry drives both filtering and verification, including nested classes.
// Some bridge classes are already absent from the nocglib archive; they still
// belong here so replacing that archive cannot silently reintroduce them.
val runtimeTakeoverClasses = setOf(
    "org/luaj/LuaString",
    "org/luaj/LuaUtf8String",
    "org/luaj/lib/jse/LuajavaLib",
    "org/luaj/lib/jse/CoerceJavaToLua",
    "org/luaj/lib/jse/CoerceLuaToJava",
    "org/luaj/lib/jse/JavaClass",
    "org/luaj/lib/jse/JavaConstructor",
    "org/luaj/lib/jse/JavaInstance",
    "org/luaj/lib/jse/JavaMethod",
    "org/luaj/lib/jse/JavaPackage",
    "org/luaj/lib/jse/JsePlatform",
    "org/luaj/lib/jse/JseIoLib"
)
val runtimeTakeoverExcludes = runtimeTakeoverClasses.flatMap {
    listOf("$it.class", "$it\$*.class")
}
val runtimeBaseJar = layout.projectDirectory.file("libs/luajpp_nocglib.jar")
val filteredLuajppJar = tasks.register<Jar>("filteredLuajppJar") {
    archiveFileName.set("luajpp_nocglib_without_luajava.jar")
    destinationDirectory.set(layout.buildDirectory.dir("filtered-libs"))
    from(zipTree(runtimeBaseJar)) {
        exclude(runtimeTakeoverExcludes)
    }
}

val verifyRuntimeTakeover = tasks.register("verifyRuntimeTakeover") {
    group = "verification"
    description = "Check source takeover registry and actual filtered JAR class entries (not ABI compatibility)."
    dependsOn(filteredLuajppJar)
    val sourceRoot = layout.projectDirectory.dir("src/main").asFile
    val sources = fileTree(sourceRoot) { include("java/**/*.java", "java/**/*.kt", "kotlin/**/*.kt") }
    val filteredArchive = filteredLuajppJar.flatMap { it.archiveFile }
    val registeredClasses = runtimeTakeoverClasses
    inputs.files(sources).withPathSensitivity(PathSensitivity.RELATIVE)
    inputs.file(runtimeBaseJar).withPathSensitivity(PathSensitivity.NONE)
    inputs.file(filteredArchive).withPathSensitivity(PathSensitivity.NONE)
    inputs.property("runtimeTakeoverClasses", registeredClasses.sorted())
    doLast {
        fun classEntries(jar: File): Set<String> = ZipFile(jar).use { zip ->
            zip.entries().asSequence().map { it.name }.filter { it.endsWith(".class") }.toSet()
        }
        fun classOwner(entry: String) = entry.removeSuffix(".class").substringBefore('$')
        val sourceClasses = sources.files.map { source ->
            source.relativeTo(sourceRoot).invariantSeparatorsPath.substringAfter('/')
                .substringBeforeLast('.')
        }.toSet()
        val original = classEntries(runtimeBaseJar.asFile)
        val filtered = classEntries(filteredArchive.get().asFile)
        val missingSources = registeredClasses - sourceClasses
        check(missingSources.isEmpty()) { "Takeover entries without source files: $missingSources" }
        val unregistered = original.map(::classOwner).toSet().intersect(sourceClasses) - registeredClasses
        check(unregistered.isEmpty()) { "Source/JAR collisions missing from runtimeTakeoverClasses: $unregistered" }
        val expected = original.filterNot { classOwner(it) in registeredClasses }.toSet()
        check(filtered == expected) {
            "Filtered JAR mismatch; unexpected=${filtered - expected}, missing=${expected - filtered}"
        }
        logger.lifecycle("Runtime takeover verified: ${registeredClasses.size} source families; ${original.size - filtered.size} JAR classes removed. No ABI guarantee implied.")
    }
}

// Fail every normal build/check, not just the explicit CI verification command.
tasks.matching { it.name == "preBuild" || it.name == "check" }.configureEach {
    dependsOn(verifyRuntimeTakeover)
}

// The legacy Luaj++ JAR omits StackMapTable entries; ART accepts its DEX output,
// while the desktop JVM used for local unit tests requires verification to be disabled.
tasks.withType<Test>().configureEach {
    jvmArgs("-noverify")
}

dependencies {
    implementation(fileTree("libs") {
        include("*.jar")
        exclude("luajpp_nocglib.jar")
    })
    implementation(files(filteredLuajppJar))
    //implementation(libs.kotlin.reflect)
    //implementation("me.jahnen.libaums:core:0.10.0")
    //implementation("me.jahnen.libaums:httpserver:0.6.2")
    //implementation("io.github.beseting:NesEmulator:1.0.1")
    //implementation("net.gotev:speech:1.6.2")

    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.espresso.core)

    //AndroidX
    implementation(libs.appcompat)
    implementation(libs.androidx.activity)
    implementation(libs.androidx.annotation)
    implementation(libs.androidx.collection)
    implementation(libs.androidx.constraintlayout)
    implementation(libs.androidx.coordinatorlayout)
    implementation(libs.androidx.core)
    implementation(libs.androidx.customview)
    implementation(libs.androidx.documentfile)
    implementation(libs.androidx.drawerlayout)
    implementation(libs.androidx.draganddrop)
    implementation(libs.androidx.dynamicanimation)
    implementation(libs.androidx.emoji2)
    implementation(libs.androidx.fragment)
    implementation(libs.androidx.gridlayout)
    //implementation(libs.androidx.legacy.support.core.ui)
    //implementation(libs.androidx.legacy.support.core.utils)
    implementation(libs.androidx.lifecycle.common)
    implementation(libs.androidx.lifecycle.process)
    implementation(libs.androidx.lifecycle.runtime)
    implementation(libs.androidx.navigation.common)
    implementation(libs.androidx.navigation.fragment)
    implementation(libs.androidx.navigation.runtime)
    implementation(libs.androidx.navigation.ui)
    implementation(libs.androidx.palette)
    implementation(libs.androidx.preference)
    implementation(libs.androidx.startup.runtime)
    implementation(libs.androidx.swiperefreshlayout)
    implementation(libs.androidx.recyclerview)
    implementation(libs.androidx.transition)
    implementation(libs.androidx.viewpager)
    implementation(libs.androidx.viewpager2)
    implementation(libs.androidx.window)

    //Material
    implementation(libs.material)
    implementation(libs.collapsingtoolbarlayout.subtitle)

    //Zip4J
    implementation(libs.zip4j)

    //Okhttp
    implementation(libs.okhttp)

    //lottie
    implementation(libs.lottie)

    //recycler anime
    implementation(libs.recyclerview.animators)

    //zhanghai
    implementation(libs.library)

    implementation(libs.coil)
    implementation(libs.coil.network.okhttp)
    implementation(libs.coil.svg)
    implementation(libs.coil.gif)
}
