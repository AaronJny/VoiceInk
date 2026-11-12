#!/usr/bin/env python3
"""Remove only this build's original signer trust, then erase its private keychain."""
import os
from pathlib import Path
import plistlib
import subprocess
import sys

root = Path(os.environ['RUNNER_TEMP'])
expected = '24F8BA788091EF77E65B03212711783CF66232C6'
keychain = root / 'voiceink-signing.keychain-db'
marker = root / 'voiceink-trust-added'
search = root / 'voiceink-keychains.plist'
failed = False


def run(*args):
    # Only public trust metadata / file paths, never credential arguments.
    return subprocess.run(args, check=True, capture_output=True, timeout=45)


def trust_export(name):
    path = root / name
    run('sudo', '-n', 'security', 'trust-settings-export', '-d', str(path))
    run('sudo', '-n', 'chown', f'{os.getuid()}:{os.getgid()}', str(path))
    return plistlib.loads(path.read_bytes())


try:
    if marker.exists():
        current = trust_export('voiceink-trust-current.plist')
        # Preserve every unrelated trust entry, removing only the exact signer.
        for key in list(current['trustList']):
            if key.upper() == expected:
                del current['trustList'][key]
        restored = root / 'voiceink-trust-restored.plist'
        restored.write_bytes(plistlib.dumps(current))
        run('sudo', '-n', 'security', 'trust-settings-import', '-d', str(restored))
        actual = trust_export('voiceink-trust-verify.plist')
        if current != actual:
            raise RuntimeError('Unrelated trust settings changed during cleanup')
        result = subprocess.run(['security', 'find-certificate', '-a', '-Z', '/Library/Keychains/System.keychain'], capture_output=True, timeout=45)
        if result.returncode not in (0, 44):
            raise RuntimeError('Cannot inspect runner System keychain during cleanup')
        listing = result.stdout.decode()
        if expected in listing.upper():
            run('sudo', '-n', 'security', 'delete-certificate', '-Z', expected, '/Library/Keychains/System.keychain')
        marker.unlink()
        print('Verified removal of temporary codeSign trust; unrelated trust settings preserved.')
except Exception as error:
    failed = True
    print(f'ERROR: scoped trust cleanup needs retry: {error}', file=sys.stderr)
finally:
    try:
        if search.exists():
            paths = plistlib.loads(search.read_bytes())
            run('security', 'list-keychains', '-d', 'user', '-s', *paths)
            search.unlink()
    except Exception as error:
        failed = True
        print(f'ERROR: keychain search-list restoration failed: {error}', file=sys.stderr)
    try:
        if keychain.exists():
            run('security', 'delete-keychain', str(keychain))
    except Exception as error:
        failed = True
        print(f'ERROR: temporary private keychain deletion failed: {error}', file=sys.stderr)
    for name in ['voiceink-signing.p12', 'voiceink-signing.cer']:
        (root / name).unlink(missing_ok=True)
    if not failed:
        for name in ['voiceink-trust-current.plist', 'voiceink-trust-restored.plist', 'voiceink-trust-verify.plist']:
            (root / name).unlink(missing_ok=True)
sys.exit(1 if failed else 0)
