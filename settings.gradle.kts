rootProject.name = "hoplite"

pluginManagement {
   repositories {
      mavenLocal()
      mavenCentral()
      gradlePluginPortal()
   }
}

// NOTE: no toolchain auto-download resolver plugin is registered here.
// The JDK must be provisioned ahead of time; see verify.sh.

include(
   ":hoplite-core",
   ":hoplite-azure",
   ":hoplite-aws",
   ":hoplite-aws2",
   ":hoplite-aws-kotlin",
   ":hoplite-arrow",
   ":hoplite-consul",
   ":hoplite-cronutils",
   ":hoplite-datetime",
   ":hoplite-gcp",
   ":hoplite-hdfs",
   ":hoplite-hikaricp",
   ":hoplite-hocon",
   ":hoplite-javax",
   ":hoplite-json",
   ":hoplite-micrometer-datadog",
   ":hoplite-micrometer-prometheus",
   ":hoplite-micrometer-statsd",
   ":hoplite-toml",
   ":hoplite-vault",
   ":hoplite-vavr",
   ":hoplite-watch",
   ":hoplite-watch-consul",
   ":hoplite-yaml"
)

enableFeaturePreview("STABLE_CONFIGURATION_CACHE")
enableFeaturePreview("TYPESAFE_PROJECT_ACCESSORS")

dependencyResolutionManagement {
   repositoriesMode = RepositoriesMode.FAIL_ON_PROJECT_REPOS
   repositories {
      mavenCentral()
      mavenLocal()
   }
   versionCatalogs {
      create("libs") {
         // kotlin.version is single-sourced from gradle.properties and shared
         // with the buildSrc classpath (kotlin-gradle-plugin).
         val kotlin = providers.gradleProperty("kotlin.version").get()
         plugin("kotlin-jvm", "org.jetbrains.kotlin.jvm").version(kotlin)
         plugin("kotlin-serialization", "org.jetbrains.kotlin.plugin.serialization").version(kotlin)
         library("kotlin-reflect", "org.jetbrains.kotlin:kotlin-reflect:$kotlin")

         val micrometer = "1.14.1"
         library("micrometer-core", "io.micrometer:micrometer-core:$micrometer")
         library("micrometer-registry-datadog", "io.micrometer:micrometer-registry-datadog:$micrometer")
         library("micrometer-registry-prometheus", "io.micrometer:micrometer-registry-prometheus:$micrometer")
         library("micrometer-registry-statsd", "io.micrometer:micrometer-registry-statsd:$micrometer")

         val coroutines = "1.6.4"
         library("coroutines-core", "org.jetbrains.kotlinx:kotlinx-coroutines-core:$coroutines")
         library("coroutines-jdk8", "org.jetbrains.kotlinx:kotlinx-coroutines-jdk8:$coroutines")

         val typesafeConfig = "1.4.3"
         library("typesafe-config", "com.typesafe:config:$typesafeConfig")

         val arrow = "2.0.1"
         library("arrow-core", "io.arrow-kt:arrow-core:$arrow")

         val springVault = "2.3.4"
         library("spring-vault-core", "org.springframework.vault:spring-vault-core:$springVault")

         val vavr = "0.10.2"
         library("vavr-kotlin", "io.vavr:vavr-kotlin:$vavr")

         val cronUtils = "9.2.1"
         library("cron-utils", "com.cronutils:cron-utils:$cronUtils")

         val hikari = "5.1.0"
         library("hikaricp", "com.zaxxer:HikariCP:$hikari")

         val kotlinxSerialization = "1.4.1"
         library("kotlinx-serialization-json", "org.jetbrains.kotlinx:kotlinx-serialization-json:$kotlinxSerialization")
         val kotlinxDatetime = "0.4.0"
         library("kotlinx-datetime", "org.jetbrains.kotlinx:kotlinx-datetime:$kotlinxDatetime")

         val gcpSecretmanager = "2.54.0"
         library("google-cloud-secretmanager", "com.google.cloud:google-cloud-secretmanager:$gcpSecretmanager")
         val hadoop = "2.10.2"
         library("hadoop-common", "org.apache.hadoop:hadoop-common:$hadoop")
         val tomlj = "1.1.1"
         library("tomlj", "org.tomlj:tomlj:$tomlj")
         val embeddedConsul = "2.2.1"
         library("embedded-consul", "com.pszymczyk.consul:embedded-consul:$embeddedConsul")
         val snakeyaml = "2.2"
         library("snakeyaml", "org.yaml:snakeyaml:$snakeyaml")

         val slf4j = "2.0.14"
         library("slf4j-api", "org.slf4j:slf4j-api:$slf4j")

         val aws1 = "1.12.767"
         library("aws-java-sdk-secretsmanager", "com.amazonaws:aws-java-sdk-secretsmanager:$aws1")
         library("aws-java-sdk-ssm", "com.amazonaws:aws-java-sdk-ssm:$aws1")

         val aws2 = "2.27.0"
         library("regions", "software.amazon.awssdk:regions:$aws2")
         library("secretsmanager", "software.amazon.awssdk:secretsmanager:$aws2")

         val awsKotlin = "1.4.44"
         library("aws-kotlin-ssm", "aws.sdk.kotlin:ssm:$awsKotlin")
         library("aws-kotlin-secretsmanager", "aws.sdk.kotlin:secretsmanager:$awsKotlin")

         val postgresql = "42.7.3"
         library("postgresql", "org.postgresql:postgresql:$postgresql")

         val jackson = "2.17.2"
         library("jackson-core", "com.fasterxml.jackson.core:jackson-core:$jackson")
         library("jackson-databind", "com.fasterxml.jackson.core:jackson-databind:$jackson")

         val testcontainers = "1.19.8"
         library("testcontainers-base", "org.testcontainers:testcontainers:$testcontainers")
         library("testcontainers-postgresql", "org.testcontainers:postgresql:$testcontainers")
         library("testcontainers-mysql", "org.testcontainers:mysql:$testcontainers")
         library("testcontainers-localstack", "org.testcontainers:localstack:$testcontainers")
         library("testcontainers-vault", "org.testcontainers:vault:$testcontainers")

         val azureIdentity = "1.13.2"
         library("azure-identity", "com.azure:azure-identity:$azureIdentity")
         val azureKeyvault = "4.9.0"
         library("azure-security-keyvault-secrets", "com.azure:azure-security-keyvault-secrets:$azureKeyvault")

         val consulClient = "1.5.3"
         library("consul-client", "com.orbitz.consul:consul-client:$consulClient")
      }
   }
}
