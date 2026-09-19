import org.gradle.api.artifacts.dsl.LockMode
import org.gradle.api.tasks.testing.logging.TestExceptionFormat
import org.gradle.api.tasks.testing.logging.TestLogEvent
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinVersion

plugins {
   `java-library`
   kotlin("jvm")
}

java {
   sourceCompatibility = JavaVersion.VERSION_1_8
   targetCompatibility = JavaVersion.VERSION_1_8
}

kotlin {
   // The JDK major version used for every compile and test task in this tree.
   // verify.sh and the CI workflows must agree with this exact value.
   jvmToolchain(17)
   compilerOptions {
      jvmTarget.set(JvmTarget.JVM_1_8)
      apiVersion.set(KotlinVersion.KOTLIN_2_2)
      languageVersion.set(KotlinVersion.KOTLIN_2_2)
   }
}

tasks.compileJava {
   options.release = 8
}

tasks.compileTestKotlin {
   compilerOptions.jvmTarget = JvmTarget.JVM_11
}

tasks.compileTestJava {
   options.release = 11
}

dependencies {
   val kotestVersion = providers.gradleProperty("kotest.version").get()
   testImplementation("io.kotest:kotest-runner-junit5:$kotestVersion")
   testImplementation("io.kotest:kotest-assertions-core:$kotestVersion")
   testImplementation("io.kotest:kotest-extensions-testcontainers:$kotestVersion")
}

dependencyLocking {
   lockAllConfigurations()
   // Strict mode is enabled by verify.sh (-Pverify.strict.locks=true) so that
   // lock validation is read-only and exact. Without the flag, modules that
   // have no lockfile (e.g. the cloud SDK modules) keep resolving as before.
   if (providers.gradleProperty("verify.strict.locks").isPresent) {
      lockMode.set(LockMode.STRICT)
   }
}

tasks.withType<Test> {
   useJUnitPlatform()
   filter {
      isFailOnNoMatchingTests = false
   }
   // kotest's system extensions (withEnvironment etc.) reflect into JDK
   // internals, which requires explicit opens on the JDK 17 toolchain.
   jvmArgs(
      "--add-opens", "java.base/java.util=ALL-UNNAMED",
      "--add-opens", "java.base/java.lang=ALL-UNNAMED",
   )
   testLogging {
      showExceptions = true
      showStandardStreams = true
      events = setOf(
         TestLogEvent.FAILED,
         TestLogEvent.PASSED
      )
      exceptionFormat = TestExceptionFormat.FULL
   }
}
