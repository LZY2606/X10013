import org.gradle.api.artifacts.component.ModuleComponentIdentifier

// Tasks used by verify.sh. Registered from an init script so the build files
// stay untouched and the checks cannot be skipped by module configuration.

val forbiddenGroups = setOf(
   "com.amazonaws",
   "software.amazon.awssdk",
   "aws.sdk.kotlin",
   "com.google.cloud",
   "com.azure",
   "com.orbitz.consul",
   "org.apache.hadoop",
   "org.springframework.vault",
)

allprojects {
   tasks.register("verifyResolveAllConfigurations") {
      description = "Resolves every resolvable configuration (drives strict dependency-lock validation)."
      doLast {
         configurations.matching { it.isCanBeResolved }.forEach { configuration ->
            configuration.incoming.resolutionResult.allComponents
         }
         // Strict lock validation of extra/missing entries only happens when a
         // configuration is resolved to files, so force file resolution of the
         // main classpaths as well.
         listOf("compileClasspath", "runtimeClasspath", "testCompileClasspath", "testRuntimeClasspath").forEach { name ->
            configurations.findByName(name)?.incoming?.files?.files
         }
      }
   }
   tasks.register("verifyNoForbiddenDeps") {
      description = "Fails if any forbidden cloud/SDK dependency group appears in the resolved graph."
      doLast {
         val violations = mutableListOf<String>()
         configurations.matching { it.isCanBeResolved }.forEach { configuration ->
            configuration.incoming.resolutionResult.allComponents.forEach { component ->
               val id = component.id
               if (id is ModuleComponentIdentifier && id.group in forbiddenGroups) {
                  violations += "${project.path} [${configuration.name}] -> ${id.group}:${id.module}:${id.version}"
               }
            }
         }
         if (violations.isNotEmpty()) {
            throw GradleException(
               "Forbidden dependency groups resolved:\n" + violations.joinToString("\n")
            )
         }
      }
   }
}
