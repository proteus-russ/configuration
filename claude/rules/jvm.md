# JVM projects

- Activate Java: `sdk env` in project root (reads `.sdkmanrc`); re-run on project switch. No `.sdkmanrc` -> ask which Java version.
- Build with `./gradlew`, never global `gradle`.
- Gradle cache `~/.gradle/caches/` (hash-based — search by artifact name). Maven cache `~/.m2/repository/` (`group/artifact/version/`).
- Sources: `-sources` classifier jar. Not in Gradle cache -> try `./gradlew downloadSources` if task exists. Not every artifact has sources.
