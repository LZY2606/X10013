plugins {
   id("kotlin-conventions")
   id("publishing-conventions")
}

dependencies {
   api(libs.kotlin.reflect)
   testImplementation(libs.postgresql)
   api(libs.coroutines.core)
   api(libs.coroutines.jdk8)
   testImplementation(libs.testcontainers.base)
   testImplementation(libs.testcontainers.postgresql)
}

// These two specs spin up a postgres testcontainer via JdbcTestContainerExtension
// and cannot run on machines without Docker. They are excluded from the build
// here (build configuration) rather than by deleting the test sources.
tasks.test {
   exclude("com/sksamuel/hoplite/resolver/validator/HostnameValidatorTest*")
   exclude("com/sksamuel/hoplite/resolver/validator/JdbcHostnameValidatorTest*")
}
