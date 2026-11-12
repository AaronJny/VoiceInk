#!/bin/bash
set -euo pipefail
mkdir -p artifacts
configuration=${CI_BUILD_CONFIGURATION:-Release}
[[ "$configuration" == Debug || "$configuration" == Release ]] || exit 1
common=( -project VoiceInk.xcodeproj -scheme VoiceInk -configuration "$configuration"
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$PWD/.ci-build"
  -xcconfig LocalBuild.xcconfig -skipMacroValidation -skipPackagePluginValidation
  -skipPackageUpdates -onlyUsePackageVersionsFromResolvedFile
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=
  "CODE_SIGN_ENTITLEMENTS=$PWD/VoiceInk/VoiceInk.local.entitlements"
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LOCAL_BUILD'
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES ENABLE_TESTABILITY=YES )
if ! xcodebuild "${common[@]}" build > artifacts/build.log 2>&1; then
  tail -100 artifacts/build.log; exit 1
fi
tests=(LegacyStatsCarryForwardTests SessionMetricWriteCoordinatorTests OllamaServerConfigurationTests
  ModeOllamaConfigurationTests MixedScriptTypographyNormalizerTests OnboardingLocalModelSelectionTests Qwen3ASRIntegrationTests)
only=()
for test in "${tests[@]}"; do only+=( "-only-testing:VoiceInkTests/$test" ); done
if ! xcodebuild "${common[@]}" -parallel-testing-enabled NO "${only[@]}" \
  -resultBundlePath "$PWD/artifacts/FocusedTests.xcresult" test > artifacts/tests.log 2>&1; then
  tail -100 artifacts/tests.log; exit 1
fi
# Do not mistake an empty test run (or ASRBenchmark's no-input return) for validation.
xcrun xcresulttool get test-results summary --path artifacts/FocusedTests.xcresult --format json > artifacts/test-summary.json
python3 - <<'PY'
import json
s=json.load(open('artifacts/test-summary.json'))
assert s.get('totalTestCount',0)>0, 'No tests executed'
assert s.get('failedTests',0)==0, 'Failed tests'
PY
app="$PWD/.ci-build/Build/Products/$configuration/VoiceInk.app"
[[ "$('/usr/libexec/PlistBuddy' -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == com.prakashjoshipax.VoiceInk ]]
lipo -verify_arch arm64 "$app/Contents/MacOS/VoiceInk"
git diff --exit-code -- VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
