#!/bin/bash
set -euo pipefail
mkdir -p artifacts
configuration=${CI_BUILD_CONFIGURATION:-Release}
[[ "$configuration" == Debug || "$configuration" == Release ]] || exit 1
# v2.27 nests the filesystem-synchronized test group under Tests/.
# Catch a source/group-path mismatch before spending time compiling the app.
if grep -q 'path = Tests;' VoiceInk.xcodeproj/project.pbxproj; then
  test_sources=Tests/VoiceInkTests
else
  test_sources=VoiceInkTests
fi
for suite in LegacyStatsCarryForwardTests SessionMetricWriteCoordinatorTests OllamaServerConfigurationTests ModeOllamaConfigurationTests MixedScriptTypographyNormalizerTests OnboardingLocalModelSelectionTests Qwen3ASRIntegrationTests; do
  [[ -s "$test_sources/$suite.swift" ]] || { echo "Missing test source: $test_sources/$suite.swift" >&2; exit 1; }
done
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
# Test hosting embeds .xctest bundles into the build product. Keep a clean
# distribution copy before test injection, rather than shipping XCTest code.
distribution="$RUNNER_TEMP/voiceink-distribution/VoiceInk.app"
mkdir -p "$(dirname "$distribution")"
ditto "$PWD/.ci-build/Build/Products/$configuration/VoiceInk.app" "$distribution"
tests=(LegacyStatsCarryForwardTests SessionMetricWriteCoordinatorTests OllamaServerConfigurationTests
  ModeOllamaConfigurationTests MixedScriptTypographyNormalizerTests OnboardingLocalModelSelectionTests Qwen3ASRIntegrationTests)
only=()
for test in "${tests[@]}"; do only+=( "-only-testing:VoiceInkTests/$test" ); done
if ! xcodebuild "${common[@]}" -parallel-testing-enabled NO "${only[@]}" \
  -resultBundlePath "$PWD/artifacts/FocusedTests.xcresult" test > artifacts/tests.log 2>&1; then
  tail -100 artifacts/tests.log; exit 1
fi
# Do not mistake an empty test run (or ASRBenchmark's no-input return) for validation.
xcrun xcresulttool get test-results summary --path artifacts/FocusedTests.xcresult > artifacts/test-summary.json
python3 - <<'PY'
import json,re
from pathlib import Path
s=json.load(open('artifacts/test-summary.json'))
assert s.get('totalTestCount',0)>0, 'No tests executed'
assert s.get('failedTests',0)==0, 'Failed tests'
assert s.get('skippedTests',0)==0, 'Skipped tests'
# xcresult summary has counts but no suite list. Require each observed Swift
# Testing suite completion line as well, rather than accepting one partial suite.
log=Path('artifacts/tests.log').read_text()
suites=['Legacy stats carry-forward','Mixed-script typography normalization',
        'ModeOllamaConfigurationTests','OllamaServerConfigurationTests',
        'Onboarding local model selection','Qwen3-ASR integration',
        'Session metric write coordination']
for suite in suites:
    assert re.search(r'✔ Suite \"?'+re.escape(suite)+r'\"? passed after ',log), 'Missing passing suite: '+suite
assert re.search(r'Test run with \d+ tests in 7 suites passed',log), 'Incomplete focused suite run'

PY
app="$PWD/.ci-build/Build/Products/$configuration/VoiceInk.app"
[[ "$('/usr/libexec/PlistBuddy' -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == com.prakashjoshipax.VoiceInk ]]
lipo "$app/Contents/MacOS/VoiceInk" -verify_arch arm64
git diff --exit-code -- VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
