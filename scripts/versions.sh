# Pinned, independently verifiable build inputs.
# Keep this marker identity stable so renamed ZIPs upgrade existing installs.
ADDON_NAME=cm12-echolocal-biscuit
PACKAGE_NAME=cm-echolocal
SOURCE_DATE_EPOCH=1700000000

BASE_LEDCONTROLLER_SHA256=f7a2f96673fae0cb00836362f30d54ec15140829217c7c75b72b707af67ef0fc
RADAR_LEDCONTROLLER_SHA256=8150881990783cd041fd88983d1dd30662d5acaafaf379d3ff7f2278b35eea4a
BASE_LEDCONTROLLER_SHA256S="$BASE_LEDCONTROLLER_SHA256 $RADAR_LEDCONTROLLER_SHA256"

# EchoLocal release tag and the commit it peels to: the single source both the
# binaries and the models are built from. fetch-inputs.sh fails closed if the
# tag no longer resolves to this commit.
ECHOLOCAL_TAG=0.0.7
ECHOLOCAL_COMMIT=1e57414f290f76fab6fe38a4ae34c5e467c5457a

# echod is compiled from the tagged source inside this pinned toolchain image
# (digest obtained via: docker pull golang:1.26.6 && docker inspect
# --format '{{index .RepoDigests 0}}' golang:1.26.6).
GO_IMAGE=golang:1.26.6@sha256:0d1d3a794be25f809dd2cb3160d8c73276c4056a9f8242a138e908ddeee7b6b6
GOOS=linux
GOARCH=${GOARCH:-arm64}
GOARM=${GOARM:-7}

# Expected SHA-256s of deterministic builds (tag + tracked patch + image + flags above).
# Re-pin only after independently rebuilding the affected target.
ECHOD_ARM64_SHA256=d0b1cc3975986d19fb1b5881926b009d988c61be09ea0519bc9edaf5b0d07085
ECHOD_ARMV7_SHA256=24effaec84210e3ebf02c14947fa90cec9898dcd7d1be3e06612c46584ac2ef4
case "$GOARCH:$GOARM" in
    arm64:*) ECHOD_ARCH=arm64; ECHOD_SHA256=$ECHOD_ARM64_SHA256 ;;
    arm:7)   ECHOD_ARCH=armv7; ECHOD_SHA256=$ECHOD_ARMV7_SHA256 ;;
    *) printf '%s\n' "unsupported echod target: GOARCH=$GOARCH GOARM=$GOARM" >&2; exit 1 ;;
esac

ECHOLOCAL_REPOSITORY=https://github.com/ygelfand/echolocal.git
ECHOLOCAL_MODELS='
okay_nabu.json 6dd65604f70fe5ea9d1af73a7bf239529d1fbabc363807f45d2b22ce464ddbed internal/host/assets/models/okay_nabu.json
okay_nabu.tflite 0689abe1912a95a3318a0d8cb2e67bad0cbcfe3e24dd6e050c75debddfb6f891 internal/host/assets/models/okay_nabu.tflite
hey_jarvis.json b153867d818675d8abcc9dace474afe7f83551ae0d5a9b1d71a98681320185af internal/host/assets/models/hey_jarvis.json
hey_jarvis.tflite 21a7976add39ee24ec96c63d96b7aaa18e24d1d9824b963e451da8feb4b78b77 internal/host/assets/models/hey_jarvis.tflite
hey_mycroft.json 57b2b06fe5fdbbe834a242fabc7af31e4194a550fc382b2c88636a6d62d0d57e internal/host/assets/models/hey_mycroft.json
hey_mycroft.tflite c2a9b6ed51182db72e014781d5a4ece1929dc232a40b5b4be384f0295f0e1571 internal/host/assets/models/hey_mycroft.tflite'
