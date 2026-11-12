#!/bin/bash
set -euo pipefail
mkdir -p artifacts/intermediate
app="$RUNNER_TEMP/voiceink-distribution/VoiceInk.app"
[[ -d "$app" ]]
[[ "$(git rev-parse HEAD)" == "$GITHUB_SHA" ]]
[[ -z "$(find "$app" -name '*.xctest' -print -quit)" ]]
ditto -c -k --sequesterRsrc --keepParent "$app" artifacts/intermediate/UNSIGNED-VoiceInk-arm64.zip
cp artifacts/toolchain.txt artifacts/intermediate/toolchain.txt
cp artifacts/test-summary.json artifacts/intermediate/test-summary.json
python3 - <<'PY'
import hashlib,json,os,pathlib
p=pathlib.Path('artifacts/intermediate')
s=json.loads((p/'test-summary.json').read_text())
assert s.get('totalTestCount',0)>0 and s.get('failedTests',0)==0
m={'kind':'UNSIGNED-INTERMEDIATE-NOT-FOR-INSTALLATION','commit':os.environ['GITHUB_SHA'],'runId':os.environ['GITHUB_RUN_ID'],'buildAttempt':os.environ['GITHUB_RUN_ATTEMPT'],'configuration':os.environ['CI_BUILD_CONFIGURATION'],'files':{n:hashlib.sha256((p/n).read_bytes()).hexdigest() for n in ['UNSIGNED-VoiceInk-arm64.zip','toolchain.txt','test-summary.json']}}
(p/'intermediate-info.json').write_text(json.dumps(m,indent=2)+'\n')
PY
