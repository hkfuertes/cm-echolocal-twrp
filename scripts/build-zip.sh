#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"

for tool in cp find sed sha256sum sort touch tr wc xargs zip; do
    need "$tool"
done

echod="$INPUTS/$ECHOD_ARCH/echod"
require_hash "$echod" "$ECHOD_SHA256"
require_static "echod" "$echod" "$GOARCH"
printf '%s\n' "$ECHOLOCAL_MODELS" |
while read -r name expected source; do
    [ -n "$name" ] || continue
    require_hash "$INPUTS/models/$name" "$expected"
done

stage="$WORK/stage-$ECHOD_ARCH"
rm -rf "$stage"
mkdir -p "$stage/payload/system/bin" \
    "$stage/payload/system/app/echod" \
    "$stage/payload/system/etc/echolocal/models" \
    "$stage/META-INF/com/google/android"

cp "$ROOT/payload/system/bin/echolocal" "$stage/payload/system/bin/echolocal"
cp "$ROOT/payload/system/bin/start_animation.sh" "$stage/payload/system/bin/start_animation.sh"
cp "$ROOT/payload/system/bin/stop_animation.sh" "$stage/payload/system/bin/stop_animation.sh"
cp "$echod" "$stage/payload/system/app/echod/echod"
printf 'name=%s\nversion=%s\nbase_ledcontroller_sha256=%s\n' \
    "$ADDON_NAME" "$ECHOLOCAL_TAG" "$BASE_LEDCONTROLLER_SHA256" \
    > "$stage/payload/system/etc/echolocal/.biscuit-addon"
printf '%s\n' "$ECHOLOCAL_MODELS" |
while read -r name expected source; do
    [ -n "$name" ] || continue
    cp "$INPUTS/models/$name" "$stage/payload/system/etc/echolocal/models/$name"
done

find "$stage" -type d -exec chmod 0755 {} \;
find "$stage/payload" -type f -exec chmod 0644 {} \;
chmod 0755 "$stage/payload/system/bin/echolocal" \
    "$stage/payload/system/bin/start_animation.sh" \
    "$stage/payload/system/bin/stop_animation.sh" \
    "$stage/payload/system/app/echod/echod"
(
    cd "$stage"
    LC_ALL=C find payload -type f -print | LC_ALL=C sort | xargs sha256sum
) > "$stage/payload-manifest.sha256"
manifest_sha=$(hash_of "$stage/payload-manifest.sha256")
payload_bytes=0
for path in $(LC_ALL=C find "$stage/payload" -type f -print | LC_ALL=C sort); do
    size=$(wc -c < "$path" | tr -d ' ')
    payload_bytes=$((payload_bytes + size))
done

sed -e "s/@ADDON_NAME@/$ADDON_NAME/g" \
    -e "s/@PACKAGE_NAME@/$PACKAGE_NAME/g" \
    -e "s/@VERSION@/$ECHOLOCAL_TAG/g" \
    -e "s/@BASE_LEDCONTROLLER_SHA256@/$BASE_LEDCONTROLLER_SHA256/g" \
    -e "s/@BASE_LEDCONTROLLER_SHA256S@/$BASE_LEDCONTROLLER_SHA256S/g" \
    -e "s/@MANIFEST_SHA256@/$manifest_sha/g" \
    -e "s/@PAYLOAD_BYTES@/$payload_bytes/g" \
    "$ROOT/installer/META-INF/com/google/android/update-binary.in" \
    > "$stage/META-INF/com/google/android/update-binary"
cp "$ROOT/installer/META-INF/com/google/android/updater-script" \
    "$stage/META-INF/com/google/android/updater-script"
chmod 0755 "$stage/META-INF/com/google/android/update-binary"

find "$stage" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
mkdir -p "$OUT"
install_zip="$OUT/$PACKAGE_NAME-$ECHOLOCAL_TAG-$ECHOD_ARCH.zip"
rm -f "$install_zip" "$install_zip.sha256"
(
    cd "$stage"
    LC_ALL=C find . -type f -print | sed 's|^./||' | LC_ALL=C sort |
        zip -X -q "$install_zip" -@
)
(
    cd "$OUT"
    sha256sum "$(basename "$install_zip")" > "$(basename "$install_zip").sha256"
)

printf '%s\n' "built $install_zip"
