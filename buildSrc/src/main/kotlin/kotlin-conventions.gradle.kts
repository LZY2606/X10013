import org.gradle.api.artifacts.dsl.LockMode
import org.gradle.api.artifacts.VersionCatalogsExtension
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
   // Single fixed JDK major for every compile and test task in the tree.
   // verify.sh (gate "toolchain") and the CI workflows pin this same major version.
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

// Version catalog accessors are not generated for precompiled script plugins,
// so look the catalog up explicitly. The catalog content comes from
// gradle/libs.versions.toml, the single source of truth.
val versionCatalog = the<VersionCatalogsExtension>().named("libs")

dependencies {
   testImplementation(versionCatalog.findLibrary("kotest-runner-junit5").get())
   testImplementation(versionCatalog.findLibrary("kotest-assertions-core").get())
   testImplementation(versionCatalog.findLibrary("kotest-extensions-testcontainers").get())
}

// Dependency locking is only engaged on the verify.sh path:
//   -Pverify.locks         lock every configuration against the committed gradle.lockfile
//   -Pverify.locks.strict  additionally fail on any missing/extra/mismatched entry
val verifyLocksStrict = providers.gradleProperty("verify.locks.strict").isPresent
if (providers.gradleProperty("verify.locks").isPresent || verifyLocksStrict) {
   dependencyLocking {
      lockAllConfigurations()
      if (verifyLocksStrict) {
         lockMode.set(LockMode.STRICT)
      }
   }
}

tasks.withType<Test> {
   useJUnitPlatform()
   // kotest system-extensions rewrite the process environment via reflection;
   // on JDK 16+ that requires opening java.util to the unnamed module.
   jvmArgs("--add-opens", "java.base/java.util=ALL-UNNAMED")
   filter {
      isFailOnNoMatchingTests = false
   }
   if (providers.gradleProperty("verify.excludeContainerTests").isPresent) {
      filter {
         // Testcontainer-based specs need a Docker daemon; the offline verify
         // path excludes them here instead of deleting the files.
         excludeTestsMatching("com.sksamuel.hoplite.resolver.validator.HostnameValidatorTest")
         excludeTestsMatching("com.sksamuel.hoplite.resolver.validator.JdbcHostnameValidatorTest")
      }
   }
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

// Resolves every resolvable configuration so dependency locks can be written.
// Only ever invoked by "bash verify.sh --prime" together with --write-locks.
tasks.register("resolveAndLockAll") {
   description = "Resolves all resolvable configurations so lock files can be written (requires --write-locks)."
   doFirst {
      require(gradle.startParameter.isWriteDependencyLocks) {
         "resolveAndLockAll refuses to run without --write-locks"
      }
   }
   doLast {
      configurations.filter { it.isCanBeResolved }.forEach { it.resolve() }
   }
}

// Read-only counterpart used by verify.sh gate "locks": resolves everything
// under strict locking so missing, stale or extra lock entries fail the build.
tasks.register("verifyLockedResolution") {
   description = "Resolves all resolvable configurations read-only to verify dependency locks."
   doLast {
      configurations.filter { it.isCanBeResolved }.forEach { it.resolve() }
   }
}

// Cloud/SDK groups that must never appear in the dependency graph of the
// offline-verified module set (used by verify.sh gate "offline-build").
val forbiddenDependencyGroups = listOf(
   "com.amazonaws",
   "software.amazon.awssdk",
   "aws.sdk.kotlin",
   "com.google.cloud",
   "com.azure",
   "com.orbitz.consul",
   "org.apache.hadoop",
   "org.springframework.vault"
)

tasks.register("verifyNoForbiddenDeps") {
   description = "Fails if runtimeClasspath or testRuntimeClasspath resolves a forbidden dependency group."
   doLast {
      val violations = mutableListOf<String>()
      listOf("runtimeClasspath", "testRuntimeClasspath").forEach { configurationName ->
         configurations.findByName(configurationName)
            ?.resolvedConfiguration
            ?.resolvedArtifacts
            ?.forEach { artifact ->
               val id = artifact.moduleVersion.id
               if (id.group in forbiddenDependencyGroups) {
                  violations.add("${id.group}:${id.name}:${id.version} ($configurationName)")
               }
            }
      }
      require(violations.isEmpty()) {
         "Forbidden dependencies resolved in ${project.path}:\n" + violations.joinToString("\n")
      }
   }
}
