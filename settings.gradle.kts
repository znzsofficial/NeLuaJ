pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven("https://jitpack.io")
        maven("https://repo.eclipse.org/content/groups/releases/")
        maven("https://maven.aliyun.com/nexus/content/groups/public/")
        maven("https://mirrors.tuna.tsinghua.edu.cn")
    }
}

rootProject.name = "NeLuaJ+"
include(":app")
 