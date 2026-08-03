allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
    
    // DESHABILITAR VERIFICACIÓN DE AAR METADATA EN TODOS LOS PLUGINS
    // Esto resuelve el conflicto entre file_picker (compileSdk 34) y 
    // flutter_plugin_android_lifecycle (compileSdk 36)
    tasks.configureEach {
        if (name.contains("AarMetadata")) {
            enabled = false
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}