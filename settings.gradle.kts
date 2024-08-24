pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        maven("https://mirrors.tuna.tsinghua.edu.cn")
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven("https://jitpack.io")
        maven("https://mirrors.tuna.tsinghua.edu.cn")
        maven("https://repo.eclipse.org/content/groups/releases/")
        maven("https://maven.aliyun.com/nexus/content/groups/public/")
    }
}

rootProject.name = "NeLuaJ+"
include(":app")

