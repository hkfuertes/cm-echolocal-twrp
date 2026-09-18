#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"

for tool in cp date docker file git id rm sha256sum; do
    need "$tool"
done

source_tree="$SOURCES/echolocal"
[ -d "$source_tree/.git" ] ||
    fail "missing EchoLocal source; run scripts/fetch-inputs.sh first"
[ "$(git -C "$source_tree" rev-parse HEAD)" = "$ECHOLOCAL_COMMIT" ] ||
    fail "EchoLocal source is not at $ECHOLOCAL_COMMIT; run scripts/fetch-inputs.sh"
git -C "$source_tree" diff --quiet ||
    fail 'pinned EchoLocal source is modified; run scripts/fetch-inputs.sh'

commit_short=$(git -C "$source_tree" rev-parse HEAD | cut -c1-7)
build_date=$(date -u -d "@$SOURCE_DATE_EPOCH" '+%Y-%m-%dT%H:%M:%SZ')

patch="$ROOT/scripts/patches/echolocal-radar.patch"
[ -f "$patch" ] || fail "missing EchoLocal Radar patch: $patch"
build_tree="$WORK/build/echolocal-$ECHOD_ARCH"
rm -rf "$build_tree"
mkdir -p "$(dirname "$build_tree")"
cp -a "$source_tree" "$build_tree"
git -C "$build_tree" apply --check --unidiff-zero "$patch" ||
    fail "EchoLocal Radar patch does not apply to $ECHOLOCAL_COMMIT"
git -C "$build_tree" apply --unidiff-zero "$patch"

artifact_dir="$INPUTS/$ECHOD_ARCH"
artifact="$artifact_dir/echod"
mkdir -p "$artifact_dir"
rm -f "$artifact"
docker build --quiet \
    -f "$ROOT/scripts/Dockerfile.echod" \
    --build-arg GO_IMAGE="$GO_IMAGE" \
    --build-arg GOOS="$GOOS" \
    --build-arg GOARCH="$GOARCH" \
    --build-arg GOARM="$GOARM" \
    --build-arg UID="$(id -u)" \
    --build-arg VERSION="$ECHOLOCAL_TAG" \
    --build-arg COMMIT="$commit_short" \
    --build-arg BUILD_DATE="$build_date" \
    --target artifacts \
    --output "type=local,dest=$artifact_dir" \
    "$build_tree"

require_static "echod" "$artifact" "$GOARCH"
require_hash "$artifact" "$ECHOD_SHA256"
printf '%s\n' "built $artifact from $ECHOLOCAL_TAG ($ECHOLOCAL_COMMIT)"
