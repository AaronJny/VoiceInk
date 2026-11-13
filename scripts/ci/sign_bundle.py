#!/usr/bin/env python3
"""Sign from the inside out, verify all leaf identities, and verify the shipped zip."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

APP = Path(sys.argv[1]).resolve()
IDENTITY = os.environ['SIGNING_IDENTITY_SHA1'].upper()
KEYCHAIN = os.environ['VOICEINK_SIGNING_KEYCHAIN']
BUNDLE_ID = 'com.prakashjoshipax.VoiceInk'
ARTIFACTS = Path('artifacts').resolve()
MACHO = {b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'}


def run(*args, **kw):
    try:
        return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kw)
    except subprocess.CalledProcessError as error:
        # These are only codesign/ditto commands; no credential arguments.
        print(error.stderr.decode(errors='replace'), file=sys.stderr)
        raise


def code_paths(app):
    files, bundles = [], []
    for p in app.rglob('*'):
        if p.is_symlink():
            continue
        if p.is_file():
            with p.open('rb') as f:
                if f.read(4) in MACHO:
                    files.append(p)
        elif p.suffix in {'.framework', '.xpc', '.app', '.bundle', '.appex'}:
            # Resource-only bundles are not executable code.
            if (p / 'Contents/MacOS').is_dir() or p.suffix == '.framework':
                bundles.append(p)
    return sorted(files, key=lambda p: len(p.parts), reverse=True) + sorted(bundles, key=lambda p: len(p.parts), reverse=True) + [app]


def verify(app):
    assert not list(app.rglob('*.xctest')), 'Test bundles must not ship in the daily application'
    run('codesign', '--verify', '--deep', '--strict', str(app))
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == BUNDLE_ID, info['CFBundleIdentifier']
    rows = []
    for p in code_paths(app):
        run('codesign', '--verify', '--strict', str(p))
        with tempfile.TemporaryDirectory() as tmp:
            prefix = str(Path(tmp) / 'cert')
            run('codesign', '-d', '--extract-certificates=' + prefix, str(p))
            leaf = Path(prefix + '0').read_bytes()
            fingerprint = hashlib.sha1(leaf).hexdigest().upper()
            assert fingerprint == IDENTITY, (p, fingerprint)
        rows.append({'path': str(p.relative_to(app)) or '.', 'certificateSHA1': fingerprint})
    ent = run('codesign', '-d', '--entitlements', ':-', str(app)).stdout
    entitlements = plistlib.loads(ent)
    expected_entitlements = plistlib.loads(Path('VoiceInk/VoiceInk.local.entitlements').read_bytes())
    for key, value in expected_entitlements.items():
        assert entitlements.get(key) == value, (key, entitlements.get(key))
    assert not any('icloud' in k.lower() for k in entitlements), entitlements
    requirement_output = run('codesign', '-dr', '-', str(app))
    requirement = '\n'.join(line for line in (requirement_output.stdout + requirement_output.stderr).decode().splitlines() if line.startswith('designated =>'))
    assert requirement, 'Missing designated requirement output'
    assert IDENTITY.lower() in requirement.lower(), requirement
    return info, rows, entitlements, requirement


for path in code_paths(APP):
    args = ['codesign', '--force', '--sign', IDENTITY, '--keychain', KEYCHAIN, '--timestamp=none']
    if path == APP:
        args += ['--entitlements', 'VoiceInk/VoiceInk.local.entitlements', '--requirements',
                 f'=designated => identifier "{BUNDLE_ID}" and certificate leaf = H"{IDENTITY.lower()}"']
    else:
        args += ['--preserve-metadata=entitlements,flags,runtime']
    run(*args, str(path))
info, rows, entitlements, requirement = verify(APP)
sha = os.environ['GITHUB_SHA']
archive = ARTIFACTS / f'VoiceInk-{info["CFBundleShortVersionString"]}-{sha[:12]}-arm64.zip'
run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(APP), str(archive))
with tempfile.TemporaryDirectory() as tmp:
    run('ditto', '-x', '-k', str(archive), tmp)
    verify(Path(tmp) / APP.name)
metadata = {
    'commit': sha, 'packagingCommit': os.environ.get('VOICEINK_PACKAGING_COMMIT', sha), 'signingRunId': os.environ.get('GITHUB_RUN_ID'), 'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
    'bundleIdentifier': info['CFBundleIdentifier'], 'architecture': 'arm64',
    'certificateSHA1': IDENTITY, 'designatedRequirement': requirement.strip(),
    'entitlements': entitlements, 'signedCode': rows,
    'archiveSHA256': hashlib.sha256(archive.read_bytes()).hexdigest(),
    'testSummarySHA256': hashlib.sha256((ARTIFACTS / 'test-summary.json').read_bytes()).hexdigest(),
    'toolchain': (ARTIFACTS / 'toolchain.txt').read_text(),
    'verification': 'codesign --verify --deep --strict, each code leaf fingerprint, zip round-trip',
    'notarized': False, 'realDeviceValidation': 'pending',
}
(ARTIFACTS / 'build-info.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
print(f'Verified signed artifact: {archive.name}')
