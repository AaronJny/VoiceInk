#!/bin/bash
# Deliberately no `set -x`: secrets are scoped only to this post-test step.
set -euo pipefail
umask 077
expected=24F8BA788091EF77E65B03212711783CF66232C6
[[ "${SIGNING_IDENTITY_SHA1:-}" == "$expected" ]] || { echo 'Missing or unexpected signing identity.' >&2; exit 1; }
[[ -n "${SIGNING_CERTIFICATE_P12_BASE64:-}" && -n "${SIGNING_CERTIFICATE_PASSWORD:-}" ]] || { echo 'Signing secrets are missing.' >&2; exit 1; }
keychain="$RUNNER_TEMP/voiceink-signing.keychain-db"
p12="$RUNNER_TEMP/voiceink-signing.p12"
cleanup() {
  security delete-keychain "$keychain" > /dev/null 2>&1 || true
  rm -f "$p12" "$RUNNER_TEMP/voiceink-signing.cer"
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
# Presence is distinct from OS trust: self-signed identities may be omitted by -v.
# Try the exact original identity and require cryptographic/leaf verification below.
# Do not alter system trust settings, create a replacement identity, or fall back to ad-hoc.
security find-identity -p codesigning "$keychain" > artifacts/signing-identities.txt
grep -F "$expected" artifacts/signing-identities.txt > /dev/null || {
  echo 'Original certificate/private-key identity is missing from the temporary keychain.' >&2; exit 1;
}
export VOICEINK_SIGNING_KEYCHAIN="$keychain"
python3 scripts/ci/sign_bundle.py "$RUNNER_TEMP/voiceink-distribution/VoiceInk.app"
