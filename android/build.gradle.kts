allprojects {
    repositories {
        google()
        mavenCentral()
    }
    // Workaround for path_provider's :jni module requiring kotlin-android DSL
    if (project.name == "jni") {
        apply(plugin = "org.jetbrains.kotlin.android")
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
