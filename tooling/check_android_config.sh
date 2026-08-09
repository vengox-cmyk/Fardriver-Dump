#!/bin/sh

set -eu

test -f android/app/build.gradle.kts
test ! -e android/app/build.gradle
test -x android/gradlew
test -f android/gradle/wrapper/gradle-wrapper.jar
test -f android/gradle/wrapper/gradle-wrapper.properties

grep -F 'sourceCompatibility = JavaVersion.VERSION_17' android/app/build.gradle.kts >/dev/null
grep -F 'jvmTarget = JavaVersion.VERSION_17.toString()' android/app/build.gradle.kts >/dev/null
grep -F 'android:value="2"' android/app/src/main/AndroidManifest.xml >/dev/null

printf '%s\n' 'Android configuration OK'
