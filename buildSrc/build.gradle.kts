import org.gradle.api.artifacts.dsl.LockMode
import org.gradle.kotlin.dsl.`kotlin-dsl`

repositories {
   mavenCentral()
}

plugins {
   `kotlin-dsl`
}

dependencies {
   implementation(libs.kotlin.gradle.plugin)
   implementation(libs.vanniktech.maven.publish)
}

val verifyLocksStrict = providers.gradleProperty("verify.locks.strict").isPresent
if (providers.gradleProperty("verify.locks").isPresent || verifyLocksStrict) {
   dependencyLocking {
      lockAllConfigurations()
      if (verifyLocksStrict) {
         lockMode.set(LockMode.STRICT)
      }
   }
}
