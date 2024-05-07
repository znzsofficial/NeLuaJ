import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

plugins {
    alias(libs.plugins.androidApplication)
    alias(libs.plugins.kotlinAndroid)
}

android {
    namespace = "github.znzsofficial.neluaj"
    compileSdk = 34

    defaultConfig {
        applicationId = "github.znzsofficial.neluaj"
        minSdk = 26
        targetSdk = 33
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    configurations {
        all {
            exclude(group = "androidx.asynclayoutinflater", module = "asynclayoutinflater")
        }
    }
    buildTypes {
        debug {
            isShrinkResources = false
            isMinifyEnabled = false
            multiDexEnabled = true
        }
        release {
            isShrinkResources = false
            isMinifyEnabled = false
            multiDexEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    applicationVariants.all {
        outputs.all {
            val currentDateTime = LocalDateTime.now()
            // 定义时间格式
            val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd_HH_mm_ss")
            // 格式化时间并打印输出
            val formattedDateTime = currentDateTime.format(formatter)
            val ver = defaultConfig.versionName
            //val minSdk = project.extensions.getByType(BaseAppModuleExtension::class.java).defaultConfig.minSdk
            //val abi = filters.find { it.filterType == "ABI" }?.identifier ?: "all"
            (this as com.android.build.gradle.internal.api.BaseVariantOutputImpl).outputFileName =
                "${project.name}-$formattedDateTime-$ver.APK";
        }
    }
}

dependencies {
    implementation(libs.kotlin.reflect)
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.jar"))))
    implementation(libs.core.ktx)
    implementation(libs.appcompat)
    implementation(libs.material)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.espresso.core)

    //AndroidX
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
    implementation(libs.androidx.legacy.support.core.ui)
    implementation(libs.androidx.legacy.support.core.utils)
    implementation(libs.androidx.lifecycle.common)
    implementation(libs.androidx.lifecycle.process)
    implementation(libs.androidx.lifecycle.runtime)
    implementation(libs.androidx.localbroadcastmanager)
    implementation(libs.androidx.navigation.common)
    implementation(libs.androidx.navigation.fragment)
    implementation(libs.androidx.navigation.runtime)
    implementation(libs.androidx.navigation.ui)
    implementation(libs.androidx.palette)
    implementation(libs.androidx.preference)
    implementation(libs.androidx.startup.runtime)
    implementation(libs.androidx.swiperefreshlayout)
    implementation(libs.androidx.slidingpanelayout)
    implementation(libs.androidx.recyclerview)
    implementation(libs.androidx.transition)
    implementation(libs.androidx.viewpager)
    implementation(libs.androidx.viewpager2)
    implementation(libs.androidx.window)

    //Material
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
    implementation(libs.coil.svg)
    implementation(libs.coil.gif)
}