#!/bin/bash
set -euo pipefail
mkdir -p artifacts
[[ "$(uname -m)" == arm64 ]] || { echo 'An ARM64 runner is required.' >&2; exit 1; }
[[ -d "$DEVELOPER_DIR" ]] || { echo 'Pinned Xcode 26.6 is unavailable.' >&2; exit 1; }
{ xcodebuild -version; swift --version; uname -m; sw_vers; echo "ImageVersion=${ImageVersion:-unknown}"; } > artifacts/toolchain.txt
swift --version | python3 -c 'import re,sys; s=sys.stdin.read(); m=re.search(r"Swift version (\d+)\.(\d+)",s); assert m and tuple(map(int,m.groups())) >= (6,3),s'
# Xcode's Metal compiler is a separately downloadable component on some images.
if ! xcrun --find metal > /dev/null 2>&1; then
  xcodebuild -downloadComponent MetalToolchain > artifacts/metal-setup.log 2>&1
fi
xcrun metal --version >> artifacts/toolchain.txt 2>&1
# Official release asset digest, verified against the GitHub v1.9.2 release API.
url=https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.2/whisper-v1.9.2-xcframework.zip
sha=af74fed13ea7f2d5ca2a39d9f58ec177713fafd7cab63aef4e27b79f3ceca80b
archive="$RUNNER_TEMP/whisper-v1.9.2-xcframework.zip"
curl --fail --location --retry 3 --silent --show-error "$url" -o "$archive"
printf '%s  %s\n' "$sha" "$archive" | shasum -a 256 -c - > artifacts/whisper-checksum.txt
unpack="$RUNNER_TEMP/whisper-unpack"
mkdir -p "$unpack"
ditto -x -k "$archive" "$unpack"
framework=$(find "$unpack" -type d -name whisper.xcframework -print -quit)
[[ -n "$framework" ]] || { echo 'Missing whisper.xcframework in verified archive.' >&2; exit 1; }
destination="$HOME/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework"
mkdir -p "$(dirname "$destination")"
ditto "$framework" "$destination"
/usr/libexec/PlistBuddy -c 'Print :AvailableLibraries' "$destination/Info.plist" > artifacts/whisper-slices.txt
