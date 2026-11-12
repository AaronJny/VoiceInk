#!/bin/bash
set -euo pipefail
[[ "$(git rev-parse HEAD)" == "$GITHUB_SHA" ]]
python3 - <<'PY'
import hashlib,json,os,pathlib,zipfile
p=pathlib.Path('artifacts/intermediate')
m=json.loads((p/'intermediate-info.json').read_text())
assert m['kind']=='UNSIGNED-INTERMEDIATE-NOT-FOR-INSTALLATION'
assert m['commit']==os.environ['GITHUB_SHA'] and m['runId']==os.environ['GITHUB_RUN_ID']
# On rerun-failed-jobs, the successful build's attempt may legitimately be older.
assert m['configuration']==('Debug' if os.environ['GITHUB_REF']=='refs/heads/ci/cloud-baseline' else 'Release')
for n in ['UNSIGNED-VoiceInk-arm64.zip','toolchain.txt','test-summary.json']:
 assert hashlib.sha256((p/n).read_bytes()).hexdigest()==m['files'][n],n
s=json.loads((p/'test-summary.json').read_text())
assert s.get('totalTestCount',0)>0 and s.get('failedTests',0)==0
with zipfile.ZipFile(p/'UNSIGNED-VoiceInk-arm64.zip') as z:
 for n in z.namelist():
  path=pathlib.PurePosixPath(n)
  assert not path.is_absolute() and '..' not in path.parts,n
  assert path.parts[0] in ['VoiceInk.app','__MACOSX'],n
PY
mkdir -p "$RUNNER_TEMP/voiceink-distribution"
ditto -x -k artifacts/intermediate/UNSIGNED-VoiceInk-arm64.zip "$RUNNER_TEMP/voiceink-distribution"
app="$RUNNER_TEMP/voiceink-distribution/VoiceInk.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == com.prakashjoshipax.VoiceInk ]]
[[ -z "$(find "$app" -name '*.xctest' -print -quit)" ]]
lipo "$app/Contents/MacOS/VoiceInk" -verify_arch arm64
cp artifacts/intermediate/toolchain.txt artifacts/toolchain.txt
cp artifacts/intermediate/test-summary.json artifacts/test-summary.json
cp artifacts/intermediate/intermediate-info.json artifacts/intermediate-info.json
