#!/usr/bin/env python3
"""Package an immutable signed build without accessing private signing material."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

SOURCE = os.environ['GITHUB_SHA']
SOURCE_RUN = os.environ['GITHUB_RUN_ID']
SOURCE_ARTIFACT = os.environ['SOURCE_ARTIFACT_ID']
IDENTITY = '24F8BA788091EF77E65B03212711783CF66232C6'
ROOT = Path.cwd()
INPUT = ROOT / 'signed-input'
OUTPUT = ROOT / 'dmg-output'
OUTPUT.mkdir(exist_ok=True)

def run(*args):
    try:
        return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as error:
        print(error.stderr.decode(errors='replace'))
        raise

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def inventory(root):
    result = {}
    for path in root.rglob('*'):
        key = str(path.relative_to(root))
        if path.is_symlink():
            result[key] = ['link', os.readlink(path)]
        elif path.is_file():
            result[key] = ['file', sha(path), path.stat().st_mode & 0o777]
    return result

def verify(app, metadata):
    run('codesign', '--verify', '--deep', '--strict', str(app))
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'com.prakashjoshipax.VoiceInk'
    assert info['CFBundleShortVersionString'] == '2.27'
    assert info['CFBundleVersion'] == '227'
    assert not list(app.rglob('*.xctest'))
    run('lipo', str(app / 'Contents/MacOS' / info['CFBundleExecutable']), '-verify_arch', 'arm64')
    assert len(metadata['signedCode']) == 20
    for row in metadata['signedCode']:
        path = app / row['path']
        assert path.resolve().is_relative_to(app.resolve())
        run('codesign', '--verify', '--strict', str(path))
        with tempfile.TemporaryDirectory() as tmp:
            prefix = str(Path(tmp) / 'cert')
            run('codesign', '-d', '--extract-certificates=' + prefix, str(path))
            assert hashlib.sha1(Path(prefix + '0').read_bytes()).hexdigest().upper() == IDENTITY
    return info

metadata = json.loads((INPUT / 'build-info.json').read_text())
assert metadata['commit'] == SOURCE
assert str(metadata['signingRunId']) == SOURCE_RUN
tests = json.loads((INPUT / 'test-summary.json').read_text())
assert sha(INPUT / 'test-summary.json') == metadata['testSummarySHA256']
assert tests['totalTestCount'] > 0 and tests['failedTests'] == 0 and tests['skippedTests'] == 0
assert metadata['certificateSHA1'] == IDENTITY
archives = list(INPUT.glob('VoiceInk-*.zip'))
assert len(archives) == 1
assert sha(archives[0]) == metadata['archiveSHA256']
with tempfile.TemporaryDirectory() as temp:
    temp = Path(temp)
    stage = temp / 'stage'
    stage.mkdir()
    run('ditto', '-x', '-k', str(archives[0]), str(stage))
    app = stage / 'VoiceInk.app'
    info = verify(app, metadata)
    expected = inventory(app)
    (stage / 'Applications').symlink_to('/Applications')
    dmg = OUTPUT / 'VoiceInk-2.27-arm64.dmg'
    run('hdiutil', 'create', '-volname', 'VoiceInk 2.27', '-srcfolder', str(stage), '-ov', '-format', 'UDZO', str(dmg))
    run('hdiutil', 'verify', str(dmg))
    mount = temp / 'mounted'
    mount.mkdir()
    run('hdiutil', 'attach', str(dmg), '-readonly', '-nobrowse', '-mountpoint', str(mount))
    try:
        assert (mount / 'Applications').is_symlink()
        assert os.readlink(mount / 'Applications') == '/Applications'
        verify(mount / 'VoiceInk.app', metadata)
        assert inventory(mount / 'VoiceInk.app') == expected, 'Mounted app differs from original signed app'
    finally:
        run('hdiutil', 'detach', str(mount))
    result = {'sourceCommit': SOURCE, 'sourceRun': SOURCE_RUN, 'sourceArtifact': SOURCE_ARTIFACT,
              'packagingCommit': os.environ['GITHUB_SHA'], 'packagingRun': os.environ['GITHUB_RUN_ID'],
              'file': dmg.name, 'sha256': sha(dmg), 'bytes': dmg.stat().st_size,
              'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
              'architecture': 'arm64', 'certificateSHA1': IDENTITY, 'testSummary': tests,
              'verification': 'hdiutil verify; read-only mount; Applications link; all mounted file hashes/modes/symlinks match; deep strict codesign; original leaf certificate on all 20 code paths',
              'notarized': False, 'appResigned': False, 'privateKeysUsed': False,
              'realDeviceValidation': 'pending'}
    (OUTPUT / 'dmg-info.json').write_text(json.dumps(result, indent=2) + '\n')
    (OUTPUT / 'SHA256SUMS.txt').write_text(result['sha256'] + '  ' + dmg.name + '\n')
    print(json.dumps(result, indent=2))
