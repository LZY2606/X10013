import org.gradle.kotlin.dsl.`kotlin-dsl`
import org.gradle.api.artifacts.dsl.LockMode
import java.util.Properties

repositories {
   mavenCentral()
}

plugins {
   `kotlin-dsl`
}

// buildSrc is a separate build and does not inherit the root gradle.properties,
// so read the shared version catalog properties from the root file directly.
val rootVersions = Properties().apply {
   rootDir.parentFile.resolve("gradle.properties").inputStream().use { load(it) }
}
val kotlinVersion = rootVersions.getProperty("kotlin.version")
val vanniktechVersion = rootVersions.getProperty("vanniktech.version")

dependencies {
   implementation("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
   implementation("com.vanniktech.maven.publish:com.vanniktech.maven.publish.gradle.plugin:$vanniktechVersion")
}

dependencyLocking {
   lockAllConfigurations()
   lockMode.set(LockMode.STRICT)
}
