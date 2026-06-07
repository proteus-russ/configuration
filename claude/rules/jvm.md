# JVM projects

- Activate Java with `sdk env` in the project root (reads `.sdkmanrc`); re-run when switching projects. Ask which Java version to use if no `.sdkmanrc` exists.
- Build with `./gradlew`, never the global `gradle`.
- Gradle cache: `~/.gradle/caches/` (hash-based — search by artifact name). Maven cache: `~/.m2/repository/` (`group/artifact/version/`).
- For sources, look for the `-sources` classifier jar. If a version's sources aren't in the Gradle cache, try `./gradlew downloadSources` if the project defines that task. Not every artifact has sources.
