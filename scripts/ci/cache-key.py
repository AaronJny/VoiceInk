#!/usr/bin/env python3
"""Version-scoped, lockfile-scoped caches; no private signing material."""
import hashlib,json,os,pathlib,platform,subprocess
p=pathlib.Path

def digest(data): return hashlib.sha256(data).hexdigest()[:24]
def command(*args): return subprocess.check_output(args,text=True).strip()
toolchain={'runnerOS':os.environ['RUNNER_OS'],'architecture':platform.machine(),'xcode':command('xcodebuild','-version'),'swift':command('xcrun','swift','--version'),'sdk':command('xcrun','--sdk','macosx','--show-sdk-version')}
tool=digest(json.dumps(toolchain,sort_keys=True).encode())
lock=digest(p('VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_bytes())
inputs=['LocalBuild.xcconfig','VoiceInk/VoiceInk.local.entitlements','VoiceInk.xcodeproj/project.pbxproj','scripts/ci/build.sh','scripts/ci/prepare.sh']
config=digest(os.environ['CI_BUILD_CONFIGURATION'].encode()+b''.join(p(n).read_bytes() for n in inputs))
# prepare.sh includes the fixed official Whisper archive digest, so changing
# that dependency invalidates compilation cache even if package lock is stable.
base=f'voiceink-v2-{tool}-{lock}'
spm=base+'-spm-'
compile=base+'-'+config+'-compile-'
keys={'spm-prefix':spm,'spm-key':spm+os.environ['GITHUB_SHA'],'compile-prefix':compile,'compile-key':compile+os.environ['GITHUB_SHA']}
with open(os.environ['GITHUB_OUTPUT'],'a') as f:
 for k,v in keys.items(): f.write(f'{k}={v}\n')
p('artifacts/cache-keys.json').write_text(json.dumps({'toolchain':toolchain,'keys':keys},indent=2)+'\n')
