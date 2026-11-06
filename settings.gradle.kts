pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        maven("https://mirrors.tuna.tsinghua.edu.cn")
    }
}
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}
@Suppress("UnstableApiUsage")
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        // Central returns HTTP 403 for NanoHTTPD in the supported build environment.
        // Route its artifacts and parent POM exclusively; a later fallback does not
        // help once Gradle has selected Central from the module metadata.
        exclusiveContent {
            forRepository {
                maven("https://maven.aliyun.com/repository/central")
            }
            filter {
                includeGroup("org.nanohttpd")
                includeModule("org.sonatype.oss", "oss-parent")
            }
        }
        google()
        mavenCentral()
        maven("https://jitpack.io")
        maven("https://mirrors.tuna.tsinghua.edu.cn")
        maven("https://repo.eclipse.org/content/groups/releases/")
        maven("https://maven.aliyun.com/nexus/content/groups/public/")
        maven("https://maven.aliyun.com/nexus/content/repositories/jcenter")
    }
}

rootProject.name = "NeLuaJ+"
include(":app")
