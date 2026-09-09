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

// There was a `subprojects { afterEvaluate { ... compileSdk = 36 } }` block here,
// and it is deliberately GONE. Recorded so nobody re-adds it speculatively.
//
// It existed because flutter_plugin_android_lifecycle 2.0.35 required its
// consumers to compile against API 36+, while file_picker 8.3.7 - the only
// package depending on it - hard-coded `compileSdk 34` in its own
// android/build.gradle. That self-inconsistent pair killed every release build
// at `:file_picker:checkReleaseAarMetadata`, and setting compileSdk on `:app`
// did not help because the failing consumer was the plugin's own subproject.
//
// file_picker 12 removes the cause outright: it no longer depends on
// flutter_plugin_android_lifecycle at all (verified - the package is absent from
// pubspec.lock), and the new `android_file_picker` sets
// `compileSdk = flutterCompileSdkVersion` rather than hard-coding a number. No
// resolved plugin now demands API 36; the only one that pins anything is `jni`,
// at 35, and it is a provider rather than a consumer.
//
// `:app` keeps its own explicit `compileSdk = 36` - see android/app/build.gradle.kts.
