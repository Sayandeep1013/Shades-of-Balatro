#!/usr/bin/env bash
# Builds the game-free Shades of Balatro APK.
#
# Starts from Lovely Mobile Maker's prebuilt Android base (LÖVE 11.5 with Lovely 0.10.0 built in,
# no game inside), adds the launcher conf.lua and our icon, gives it its own package name and
# signs it. The APK never contains Balatro: the launcher mounts the player's own Balatro.exe.
#
# Needs: java 17+, curl, sha256sum, unzip. Env:
#   SHADES_KEYSTORE        path to the release keystore (.jks)
#   SHADES_KEYSTORE_PASS   its password (store and key)
#   VERSION_NAME           e.g. 1.1.0        VERSION_CODE   e.g. 2
#   JAVA                   java binary (default: java)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${WORK:-$HERE/build}"
OUT="${OUT:-$HERE/dist}"
JAVA="${JAVA:-java}"
VERSION_NAME="${VERSION_NAME:-1.1.0}"
VERSION_CODE="${VERSION_CODE:-2}"
PACKAGE="io.github.sayandeep1013.shades"
LABEL="Shades of Balatro"

BASE_URL="https://lmm.shorty.systems/base.apk"
BASE_SHA="b2e06e936dc2686926409be8837dc3ebc7e24938522566b9c7b2faeb3e5318db"
APKTOOL_URL="https://github.com/iBotPeaches/Apktool/releases/download/v2.9.3/apktool_2.9.3.jar"
APKTOOL_SHA="7956eb04194300ce0d0a84ad18771eebc94b89fb8d1ddcce8ea4c056818646f4"
SIGNER_URL="https://github.com/patrickfav/uber-apk-signer/releases/download/v1.3.0/uber-apk-signer-1.3.0.jar"
SIGNER_SHA="e1299fd6fcf4da527dd53735b56127e8ea922a321128123b9c32d619bba1d835"

fetch() { # url sha file
	if [ -f "$3" ] && echo "$2  $3" | sha256sum -c --status; then return; fi
	curl -sSL -o "$3" "$1"
	echo "$2  $3" | sha256sum -c --status || { echo "checksum mismatch: $1" >&2; exit 1; }
}

: "${SHADES_KEYSTORE:?set SHADES_KEYSTORE}" "${SHADES_KEYSTORE_PASS:?set SHADES_KEYSTORE_PASS}"
mkdir -p "$WORK" "$OUT"
fetch "$BASE_URL" "$BASE_SHA" "$WORK/base.apk"
fetch "$APKTOOL_URL" "$APKTOOL_SHA" "$WORK/apktool.jar"
fetch "$SIGNER_URL" "$SIGNER_SHA" "$WORK/uber-apk-signer.jar"

DEC="$WORK/decoded"
rm -rf "$DEC"
"$JAVA" -jar "$WORK/apktool.jar" d -f -o "$DEC" "$WORK/base.apk" >/dev/null

# Own package (so it installs beside any other Balatro build), label, and debuggable so
# `shades phone` can copy Balatro.exe and the mods into the app's private folder over adb.
M="$DEC/AndroidManifest.xml"
sed -i \
	-e "s/package=\"systems.shorty.lmm\"/package=\"$PACKAGE\"/" \
	-e "s/systems\.shorty\.lmm\./$PACKAGE./g" \
	-e "s/android:label=\"Lovely Mobile Maker\"/android:label=\"$LABEL\"/g" \
	-e 's/<application /<application android:debuggable="true" /' \
	"$M"
grep -q "package=\"$PACKAGE\"" "$M"
! grep -q 'systems\.shorty\.lmm' "$M"

sed -i -e "s/versionCode: .*/versionCode: $VERSION_CODE/" -e "s/versionName: .*/versionName: $VERSION_NAME/" "$DEC/apktool.yml"

cp "$HERE/launcher/conf.lua" "$DEC/assets/conf.lua"
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do cp "$HERE/icon/icon-$d.png" "$DEC/res/drawable-$d/love.png"; done

"$JAVA" -jar "$WORK/apktool.jar" b -o "$WORK/unsigned.apk" "$DEC" >/dev/null
rm -rf "$WORK/signed"
"$JAVA" -jar "$WORK/uber-apk-signer.jar" -a "$WORK/unsigned.apk" -o "$WORK/signed" \
	--ks "$SHADES_KEYSTORE" --ksAlias shades --ksPass "$SHADES_KEYSTORE_PASS" --ksKeyPass "$SHADES_KEYSTORE_PASS" >/dev/null

APK="$OUT/ShadesOfBalatro-$VERSION_NAME.apk"
cp "$WORK"/signed/*-aligned-signed.apk "$APK"
sha256sum "$APK"
