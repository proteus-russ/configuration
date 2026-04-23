# Java / JVM Version Selection

Use SDKMAN to select the Java version for a project. Most projects have an `.sdkmanrc` file in the project root declaring the required version.

- Run `sdk env` in the project root to activate the version specified in `.sdkmanrc`.
- If no `.sdkmanrc` exists, ask which Java version to use before proceeding.
- Run `sdk env` proactively before builds or when switching projects.
