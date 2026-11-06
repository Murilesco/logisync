#!/usr/bin/env bash
# Builds the APK without Gradle: aapt2 + javac + d8 + apksigner.
# Needs JDK 17 and an Android SDK with platforms;android-35 and build-tools;35.0.0
# ($ANDROID_HOME set). Output: android/build/LogiSync.apk
set -euo pipefail
cd "$(dirname "$0")"
BT="$ANDROID_HOME/build-tools/35.0.0"
JAR="$ANDROID_HOME/platforms/android-35/android.jar"
OUT=build
rm -rf "$OUT" && mkdir -p "$OUT/gen" "$OUT/classes" "$OUT/dex"

"$BT/aapt2" compile --dir res -o "$OUT/res.zip"
"$BT/aapt2" link -I "$JAR" --manifest AndroidManifest.xml -o "$OUT/base.apk" "$OUT/res.zip" \
    --java "$OUT/gen" --min-sdk-version 31 --target-sdk-version 35 --version-code 1 --version-name 1.0.0
javac --release 17 -encoding UTF-8 -classpath "$JAR" -d "$OUT/classes" $(find src "$OUT/gen" -name '*.java')
"$BT/d8" --lib "$JAR" --min-api 31 --output "$OUT/dex" $(find "$OUT/classes" -name '*.class')

cp "$OUT/base.apk" "$OUT/unsigned.apk"
(cd "$OUT/dex" && jar uf ../unsigned.apk classes.dex)
"$BT/zipalign" -f -p 4 "$OUT/unsigned.apk" "$OUT/aligned.apk"

KS="${KEYSTORE:-debug.keystore}"
[[ -f "$KS" ]] || keytool -genkeypair -keystore "$KS" -storepass android -keypass android -alias logisync \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=LogiSync" >/dev/null
"$BT/apksigner" sign --ks "$KS" --ks-pass "pass:${KEYSTORE_PASS:-android}" --out "$OUT/LogiSync.apk" "$OUT/aligned.apk"
echo "OK: $OUT/LogiSync.apk"
