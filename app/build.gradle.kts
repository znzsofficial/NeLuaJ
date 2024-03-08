import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

@Suppress("DSL_SCOPE_VIOLATION") // TODO: Remove once KTIJ-19369 is fixed
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
    implementation("org.jetbrains.kotlin:kotlin-reflect:1.9.23")
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.jar"))))
    implementation(libs.core.ktx)
    implementation(libs.appcompat)
    implementation(libs.material)

    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.espresso.core)

    //AndroidX
    implementation("androidx.activity:activity:1.9.0-alpha03")
    implementation("androidx.annotation:annotation:1.7.1")
    implementation("androidx.asynclayoutinflater:asynclayoutinflater:1.1.0-alpha01")
    implementation("androidx.collection:collection:1.4.0")
    implementation("androidx.constraintlayout:constraintlayout:2.2.0-alpha13")
    implementation("androidx.coordinatorlayout:coordinatorlayout:1.3.0-alpha02")
    implementation("androidx.customview:customview:1.2.0-alpha02")
    implementation("androidx.documentfile:documentfile:1.1.0-alpha01")
    implementation("androidx.drawerlayout:drawerlayout:1.2.0")
    implementation("androidx.draganddrop:draganddrop:1.0.0")
    implementation("androidx.dynamicanimation:dynamicanimation:1.1.0-alpha03")
    implementation("androidx.emoji2:emoji2:1.4.0")
    implementation("androidx.fragment:fragment:1.7.0-alpha10")
    implementation("androidx.gridlayout:gridlayout:1.1.0-beta01")
    implementation("androidx.legacy:legacy-support-core-ui:1.0.0")
    implementation("androidx.legacy:legacy-support-core-utils:1.0.0")
    implementation("androidx.lifecycle:lifecycle-common:2.7.0")
    implementation("androidx.lifecycle:lifecycle-process:2.7.0")
    implementation("androidx.lifecycle:lifecycle-runtime:2.7.0")
    implementation("androidx.localbroadcastmanager:localbroadcastmanager:1.1.0")
    implementation("androidx.navigation:navigation-common:2.7.7")
    implementation("androidx.navigation:navigation-fragment:2.7.7")
    implementation("androidx.navigation:navigation-runtime:2.7.7")
    implementation("androidx.navigation:navigation-ui:2.7.7")
    implementation("androidx.palette:palette:1.0.0")
    implementation("androidx.preference:preference:1.2.1")
    implementation("androidx.startup:startup-runtime:1.2.0-alpha02")
    implementation("androidx.swiperefreshlayout:swiperefreshlayout:1.2.0-alpha01")
    implementation("androidx.slidingpanelayout:slidingpanelayout:1.2.0")
    implementation("androidx.recyclerview:recyclerview:1.3.2")
    implementation("androidx.transition:transition:1.4.1")
    implementation("androidx.viewpager:viewpager:1.1.0-alpha01")
    implementation("androidx.viewpager2:viewpager2:1.1.0-beta02")
    implementation("androidx.window:window:1.2.0")

    //Material
    implementation("com.hendraanggrian.material:collapsingtoolbarlayout-subtitle:1.5.0")

    //Zip4J
    implementation("net.lingala.zip4j:zip4j:2.11.5")

    //drawer
    implementation("com.drakeet.drawer:drawer:1.0.3")

    //Okhttp
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    //lottie
    implementation("com.airbnb.android:lottie:6.4.0")

    //recycler anime
    implementation("jp.wasabeef:recyclerview-animators:4.0.2")

    //zhanghai
    implementation("me.zhanghai.android.fastscroll:library:1.3.0")

    implementation("io.coil-kt:coil:2.6.0")
    implementation("io.coil-kt:coil-svg:2.6.0")
    implementation("io.coil-kt:coil-gif:2.6.0")
}