# Sourced by the scripts that run gradlew; expects die().
# shellcheck shell=bash

# gradlew needs a JDK, and macOS ships only a `java` stub that errors out — so
# probe it rather than its existence. Android Studio's bundled runtime is the
# one Gradle syncs with anyway.
if [[ -z "$JAVA_HOME" ]] && ! java -version >/dev/null 2>&1; then
    JBR="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
    [[ -x "$JBR/bin/java" ]] || die "no JDK — set JAVA_HOME (Android Studio's is $JBR)"
    export JAVA_HOME="$JBR"
fi
