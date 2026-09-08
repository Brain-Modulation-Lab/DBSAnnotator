allprojects {
    repositories {
        google()
        mavenCentral()
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

// Raise every plugin subproject to compileSdk 36.
//
// flutter_plugin_android_lifecycle 2.0.35 requires its consumers to compile
// against API 36+, but file_picker 8.3.7 - the ONLY package that depends on it
// (via `^2.0.22`) - hard-codes `compileSdk 34` in its own android/build.gradle.
// So the locked dependency set is self-inconsistent and the release build dies
// at `:file_picker:checkReleaseAarMetadata`. Setting compileSdk on `:app` does
// not help: the failing consumer is the plugin's own subproject.
//
// Raising compileSdk is what the AGP error itself recommends, and it only
// widens which APIs the code MAY call - minSdk and targetSdk are untouched, so
// no device behaviour changes. The real fix is file_picker 8 -> 12, but that
// plugin has since been split into federated packages and rewriting the file
// open/save path on five platforms is not a CI unblock.
//
// `:app` is skipped deliberately. The `evaluationDependsOn(":app")` above has
// already evaluated it, so registering an afterEvaluate on it throws
// "Cannot run Project.afterEvaluate(Action) when the project is already
// evaluated" - and it sets its own compileSdk anyway.
subprojects {
    if (name != "app") {
        afterEvaluate {
            extensions.findByType<com.android.build.api.dsl.LibraryExtension>()?.let { android ->
                if ((android.compileSdk ?: 0) < 36) android.compileSdk = 36
            }
        }
    }
}
