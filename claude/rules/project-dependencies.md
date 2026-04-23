# Project Dependency Locations

- **Gradle:** `~/.gradle/caches/` — uses a hash-based directory structure, so search by artifact name rather than browsing the tree.
- **Maven:** `~/.m2/repository/` — follows the standard `group/artifact/version/` layout.

If you need source code, look for the corresponding artifact with the `-sources` classifier (e.g., `some-lib-1.0-sources.jar`).

If you cannot find the sources for the version you want in the Gradle caches, check to see if the project has a task to download
sources named `downloadSources` and run it. Note: not all artifacts have a corresponding sources artifact.

## Build Tool

- Always use the Gradle wrapper (`./gradlew`) for builds, never the global `gradle` command.

