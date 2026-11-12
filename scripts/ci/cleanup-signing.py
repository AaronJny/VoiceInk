#!/usr/bin/env python3
"""Erase private signing material; hosted-runner teardown retires scoped trust."""
import json, os, plistlib, shlex, subprocess, sys
from pathlib import Path
root=Path(os.environ['RUNNER_TEMP'])
expected='24F8BA788091EF77E65B03212711783CF66232C6'
keychain=root/'voiceink-signing.keychain-db'
marker=root/'voiceink-trust-added'
search=root/'voiceink-keychains.plist'
active=marker.exists() or search.exists() or keychain.exists()
failed=False
result={'trustRecordRemoval':'GitHub-hosted disposable runner teardown after this job',
        'manualTrustRecordRemoval':False,'publicCertificateDeleted':None,
        'privateKeychainDeleted':False,'searchListRestored':None}
def run(*args):
 return subprocess.run(args,check=True,capture_output=True,timeout=45)
try:
 if marker.exists():
  listing=subprocess.run(['security','find-certificate','-a','-Z','/Library/Keychains/System.keychain'],capture_output=True,timeout=45)
  if listing.returncode not in (0,44): raise RuntimeError('Cannot inspect runner public certificate store')
  if expected in listing.stdout.decode().upper():
   run('sudo','-n','security','delete-certificate','-Z',expected,'/Library/Keychains/System.keychain')
  result['publicCertificateDeleted']=True
  marker.unlink()
except Exception as error:
 print(f'Public certificate cleanup warning; remaining state retires with this runner: {error}',file=sys.stderr)
 result['publicCertificateDeleted']=False
finally:
 try:
  if search.exists():
   paths=plistlib.loads(search.read_bytes())
   run('security','list-keychains','-d','user','-s',*paths)
   restored=shlex.split(run('security','list-keychains','-d','user').stdout.decode())
   if paths!=restored: raise RuntimeError('Keychain search list differs after restoration')
   result['searchListRestored']=True; search.unlink()
 except Exception as error:
  print(f'Search-list cleanup warning; state retires with this runner: {error}',file=sys.stderr)
  result['searchListRestored']=False
 try:
  if keychain.exists(): run('security','delete-keychain',str(keychain))
  if keychain.exists(): raise RuntimeError('Temporary private keychain still exists')
  result['privateKeychainDeleted']=True
 except Exception as error:
  failed=True; print(f'ERROR: temporary private keychain deletion failed: {error}',file=sys.stderr)
 for name in ['voiceink-signing.p12','voiceink-signing.cer']:
  (root/name).unlink(missing_ok=True)
 if active:
  Path('artifacts').mkdir(exist_ok=True)
  Path('artifacts/signing-cleanup.json').write_text(json.dumps(result,indent=2)+'\n')
  info=Path('artifacts/build-info.json')
  if info.exists():
   d=json.loads(info.read_text()); d['signingCleanup']=result; info.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
  print('Private signing material deleted. Scoped trust records retire with this disposable hosted runner; no manual trust-record deletion claimed.')
sys.exit(1 if failed else 0)
