import com.android.build.gradle.internal.api.BaseVariantOutputImpl
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

plugins {
    alias(libs.plugins.androidApplication)
    alias(libs.plugins.kotlinAndroid)
}

android {
    namespace = "github.znzsofficial.neluaj"
    compileSdk = 35

    defaultConfig {
        applicationId = "github.znzsofficial.neluaj"
        minSdk = 26
        //noinspection OldTargetApi
        targetSdk = 33
        versionCode = 1
        versionName = "1.0"
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
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
        freeCompilerArgs += "-Xno-call-assertions"
        freeCompilerArgs += "-Xno-receiver-assertions"
        freeCompilerArgs += "-Xno-param-assertions"
    }
    packagingOptions.resources.excludes.add("META-INF/androidx/emoji2/emoji2/LICENSE.txt")
    configurations.all {
        exclude(group = "androidx.asynclayoutinflater", module = "asynclayoutinflater")
        exclude(group = "androidx.localbroadcastmanager", module = "localbroadcastmanager")
        exclude(group = "androidx.slidingpanelayout", module = "slidingpanelayout")
    }
    applicationVariants.all {
        outputs.all {
            // 定义时间格式
            val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd_HH_mm_ss")
            // 格式化时间并打印输出
            val formattedDateTime = LocalDateTime.now().format(formatter)
            val ver = defaultConfig.versionName
            //val minSdk = project.extensions.getByType(BaseAppModuleExtension::class.java).defaultConfig.minSdk
            //val abi = filters.find { it.filterType == "ABI" }?.identifier ?: "all"
            (this as BaseVariantOutputImpl).outputFileName =
                "${project.name}-$formattedDateTime-$ver.APK";
        }
    }
}

dependencies {
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.jar"))))
    implementation(libs.kotlin.reflect)
    //implementation("me.jahnen.libaums:core:0.10.0")
    //implementation("me.jahnen.libaums:httpserver:0.6.2")
    //implementation("io.github.beseting:NesEmulator:1.0.1")
    //implementation("net.gotev:speech:1.6.2")

    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.espresso.core)

    //AndroidX
    implementation(libs.core.ktx)
    implementation(libs.appcompat)
    implementation(libs.androidx.activity)
    implementation(libs.androidx.annotation)
    implementation(libs.androidx.collection)
    implementation(libs.androidx.constraintlayout)
    implementation(libs.androidx.coordinatorlayout)
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

    //drawer
    implementation(libs.drawer)

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