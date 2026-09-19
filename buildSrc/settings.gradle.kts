dependencyResolutionManagement {
   versionCatalogs {
      create("libs") {
         // Same catalog file as the main build: one source of truth for both classpaths.
         from(files("../gradle/libs.versions.toml"))
      }
   }
}
