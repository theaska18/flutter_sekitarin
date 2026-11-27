allprojects {
    repositories {
        // The Jitsi repository advertises itself through github.com/raw, which
        // is unreliable (504). Prefer the raw CDN for the same artifacts.
        maven {
            url = uri("https://raw.githubusercontent.com/jitsi/jitsi-maven-repository/master/releases")
        }
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
