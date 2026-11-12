#!/bin/bash
# Deliberately no `set -x`: secrets are scoped only to this post-test step.
set -euo pipefail
umask 077
expected=24F8BA788091EF77E65B03212711783CF66232C6
[[ "${SIGNING_IDENTITY_SHA1:-}" == "$expected" ]] || { echo 'Missing or unexpected signing identity.' >&2; exit 1; }
[[ -n "${SIGNING_CERTIFICATE_P12_BASE64:-}" && -n "${SIGNING_CERTIFICATE_PASSWORD:-}" ]] || { echo 'Signing secrets are missing.' >&2; exit 1; }
keychain="$RUNNER_TEMP/voiceink-signing.keychain-db"
p12="$RUNNER_TEMP/voiceink-signing.p12"
cert="$RUNNER_TEMP/voiceink-signing.cer"
marker="$RUNNER_TEMP/voiceink-trust-added"
cleanup() {
  rc=$?
  trap - EXIT
  python3 scripts/ci/cleanup-signing.py || { [[ "$rc" -ne 0 ]] || rc=1; }
  exit "$rc"
}
trap cleanup EXIT
password=$(openssl rand -hex 32)
echo "::add-mask::$password"
printf '%s' "$SIGNING_CERTIFICATE_P12_BASE64" | base64 --decode > "$p12"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$p12" -k "$keychain" -P "$SIGNING_CERTIFICATE_PASSWORD" -T /usr/bin/codesign > /dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" > /dev/null
rm -f "$p12"
unset SIGNING_CERTIFICATE_P12_BASE64 SIGNING_CERTIFICATE_PASSWORD password
# Approved scope: original self-signed leaf, codeSign trust only on this ephemeral
# runner. Private key remains in the temporary keychain; cleanup verifies restoration.
security find-certificate -c 'VoiceInk Local Dev' -p "$keychain" > "$cert"
actual_sha1=$(openssl x509 -in "$cert" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':' | tr '[:lower:]' '[:upper:]')
actual_sha256=$(openssl x509 -in "$cert" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':' | tr '[:lower:]' '[:upper:]')
[[ "$actual_sha1" == "$expected" ]]
[[ "$actual_sha256" == 0D8A10DA627B134F22C2B6AB7FB2D7CFE5E4A0B462D6BC2FF0C437F2013D7129 ]]
VOICEINK_TEMP_KEYCHAIN="$keychain" python3 - <<'SETUP'
import os,plistlib,shlex,subprocess
from pathlib import Path
root=Path(os.environ['RUNNER_TEMP'])
paths=shlex.split(subprocess.check_output(['security','list-keychains','-d','user'],text=True))
(root/'voiceink-keychains.plist').write_bytes(plistlib.dumps(paths))
subprocess.run(['security','list-keychains','-d','user','-s',os.environ['VOICEINK_TEMP_KEYCHAIN'],*paths],check=True,timeout=45)
result=subprocess.run(['security','find-certificate','-a','-Z','/Library/Keychains/System.keychain'],text=True,capture_output=True)
assert result.returncode in (0,44), 'Cannot inspect runner System keychain'
listing=result.stdout
assert '24F8BA788091EF77E65B03212711783CF66232C6' not in listing.upper(), 'Signer unexpectedly exists in runner System keychain'
(root/'voiceink-trust-added').touch()
subprocess.run(['sudo','-n','security','add-trusted-cert','-d','-r','trustRoot','-p','codeSign','-k','/Library/Keychains/System.keychain',str(root/'voiceink-signing.cer')],check=True,timeout=45)
SETUP
security find-identity -v -p codesigning "$keychain" > artifacts/signing-identities.txt
grep -F "$expected" artifacts/signing-identities.txt > /dev/null || {
  echo 'Original certificate/private-key identity is not valid after scoped trust.' >&2; exit 1;
}
export VOICEINK_SIGNING_KEYCHAIN="$keychain"
python3 scripts/ci/sign_bundle.py "$RUNNER_TEMP/voiceink-distribution/VoiceInk.app"
