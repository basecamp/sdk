rootProject.name = "conformance-runner"

dependencyResolutionManagement {
    repositories {
        mavenCentral()
    }
}

// Include the consuming repo's SDK build via composite build.
// When this runner is checked out inside a repo at conformance/runner/kotlin/,
// the SDK project root is three levels up.
includeBuild("../../../kotlin")
