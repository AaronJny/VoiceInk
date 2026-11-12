#!/bin/bash
set -euo pipefail
umask 077
expected=24F8BA788091EF77E65B03212711783CF66232C6
[[ "${SIGNING_IDENTITY_SHA1:-}" == "$expected" ]]
keychain="$RUNNER_TEMP/voiceink-signing.keychain-db"
p12="$RUNNER_TEMP/voiceink-signing.p12"
cert="$RUNNER_TEMP/voiceink-signing.cer"
export keychain expected cert
bounded() { python3 - "$@" <<'PY'
import subprocess,sys
subprocess.run(sys.argv[1:],check=True,timeout=45)
PY
}
cleanup() {
 rc=$?; trap - EXIT; echo 'Restoring original runner trust settings and keychain search list.'
 if [[ -f "$RUNNER_TEMP/trust-added" ]]; then
  if bounded sudo -n security trust-settings-export -d "$RUNNER_TEMP/trust-current.plist"; then
   sudo -n chown "$(id -u):$(id -g)" "$RUNNER_TEMP/trust-current.plist"
   python3 - <<'PY' || rc=1
import os,plistlib,pathlib
p=pathlib.Path(os.environ['RUNNER_TEMP'])
d=plistlib.loads((p/'trust-current.plist').read_bytes())
keys=[k for k in d['trustList'] if k.upper()==os.environ['expected']]
assert len(keys)==1, keys
for k in keys: del d['trustList'][k]
(p/'trust-restored.plist').write_bytes(plistlib.dumps(d))
PY
   if bounded sudo -n security trust-settings-import -d "$RUNNER_TEMP/trust-restored.plist"; then
    echo 'Removed only the original temporary certificate trust entry.'
    bounded sudo -n security trust-settings-export -d "$RUNNER_TEMP/trust-verify.plist" || rc=1
    sudo -n chown "$(id -u):$(id -g)" "$RUNNER_TEMP/trust-verify.plist" || rc=1
    python3 - <<'PY' || rc=1
import os,plistlib,pathlib
p=pathlib.Path(os.environ['RUNNER_TEMP'])
a=plistlib.loads((p/'trust-restored.plist').read_bytes()); b=plistlib.loads((p/'trust-verify.plist').read_bytes())
assert a==b, 'Trust settings restoration mismatch'
print('Trust settings restoration verified.')
PY
   else rc=1; fi
  else rc=1; fi
  bounded sudo -n security delete-certificate -Z "$expected" /Library/Keychains/System.keychain || rc=1
 fi
 if [[ -f "$RUNNER_TEMP/keychains.json" ]]; then
  python3 - <<'PY' || rc=1
import os,pathlib,json,subprocess
paths=json.loads((pathlib.Path(os.environ['RUNNER_TEMP'])/'keychains.json').read_text())
subprocess.run(['security','list-keychains','-d','user','-s',*paths],check=True,timeout=30)
PY
 fi
 security delete-keychain "$keychain" >/dev/null 2>&1 || rc=1
 rm -f "$p12" "$cert"
 exit "$rc"
}
trap cleanup EXIT
password=$(openssl rand -hex 32); echo "::add-mask::$password"
printf '%s' "$SIGNING_CERTIFICATE_P12_BASE64" | base64 --decode > "$p12"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$p12" -k "$keychain" -P "$SIGNING_CERTIFICATE_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
rm -f "$p12"; unset SIGNING_CERTIFICATE_P12_BASE64 SIGNING_CERTIFICATE_PASSWORD password
security find-certificate -c 'VoiceInk Local Dev' -p "$keychain" > "$cert"
[[ "$(openssl x509 -in "$cert" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')" == "$expected" ]]
[[ "$(openssl x509 -in "$cert" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':')" == 0D8A10DA627B134F22C2B6AB7FB2D7CFE5E4A0B462D6BC2FF0C437F2013D7129 ]]
python3 - <<'PY'
import os,subprocess,shlex,pathlib,json
old=shlex.split(subprocess.check_output(['security','list-keychains','-d','user'],text=True))
(pathlib.Path(os.environ['RUNNER_TEMP'])/'keychains.json').write_text(json.dumps(old))
subprocess.run(['security','list-keychains','-d','user','-s',os.environ['keychain'],*old],check=True)
PY
echo 'Adding approved codeSign-only trust.'
bounded sudo -n security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$cert"
touch "$RUNNER_TEMP/trust-added"
security find-identity -v -p codesigning "$keychain" | grep -F "$expected"
echo 'Signing with the original identity and explicit keychain.'
printf 'int main(void) { return 0; }\n' > "$RUNNER_TEMP/probe.c"
/usr/bin/clang "$RUNNER_TEMP/probe.c" -o "$RUNNER_TEMP/probe"
bounded codesign --force --sign "$expected" --keychain "$keychain" --timestamp=none "$RUNNER_TEMP/probe"
codesign --verify --strict --verbose=2 "$RUNNER_TEMP/probe"
codesign -d --extract-certificates="$RUNNER_TEMP/probe-cert" "$RUNNER_TEMP/probe"
[[ "$(shasum "$RUNNER_TEMP/probe-cert0" | awk '{print toupper($1)}')" == "$expected" ]]
echo 'Original certificate signature and fingerprint verified.'
