#!/bin/bash
# Deliberately no `set -x`: secrets are scoped only to this post-test step.
set -euo pipefail
umask 077
mkdir -p artifacts
expected=24F8BA788091EF77E65B03212711783CF66232C6
[[ "${SIGNING_IDENTITY_SHA1:-}" == "$expected" ]] || { echo 'Missing or unexpected signing identity.' >&2; exit 1; }
[[ -n "${SIGNING_CERTIFICATE_P12_BASE64:-}" && -n "${SIGNING_CERTIFICATE_PASSWORD:-}" ]] || { echo 'Signing secrets are missing.' >&2; exit 1; }
keychain="$RUNNER_TEMP/voiceink-signing.keychain-db"
p12="$RUNNER_TEMP/voiceink-signing.p12"
bounded_security() {
  python3 - "$@" <<'PY'
import subprocess,sys
subprocess.run(sys.argv[1:],check=True,timeout=45)
PY
}
cleanup() {
  rc=$?
  trap - EXIT
  echo 'Removing scoped trust and public certificate from this ephemeral runner.'
  if [[ -f "$RUNNER_TEMP/voiceink-signing.cer" ]]; then
    bounded_security sudo -n security remove-trusted-cert -d "$RUNNER_TEMP/voiceink-signing.cer" || rc=1
    bounded_security sudo -n security delete-certificate -Z "$expected" /Library/Keychains/System.keychain || rc=1
  fi
  security delete-keychain "$keychain" > /dev/null 2>&1 || true
  rm -f "$p12" "$RUNNER_TEMP/voiceink-signing.cer"
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
# Use only the owner-approved temporary codeSign trust for the original certificate.
security find-identity -p codesigning "$keychain" > artifacts/signing-identities.txt
grep -F "$expected" artifacts/signing-identities.txt > /dev/null || {
  echo 'Original certificate is not a valid signing identity on this runner; inspect certificate trust.' >&2; exit 1;
}
echo 'Public identity validity diagnostics:'
security find-identity -p codesigning "$keychain"
security find-identity -v -p codesigning "$keychain"
security find-certificate -a -Z "$keychain"
security list-keychains -d user
security show-keychain-info "$keychain"
security find-certificate -c "VoiceInk Local Dev" -p "$keychain" | openssl x509 -noout -subject -issuer -dates -fingerprint -sha256
cert="$RUNNER_TEMP/voiceink-signing.cer"
security find-certificate -c "VoiceInk Local Dev" -p "$keychain" > "$cert"
actual_sha1=$(openssl x509 -in "$cert" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
actual_sha256=$(openssl x509 -in "$cert" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':')
[[ "$actual_sha1" == "$expected" ]]
[[ "$actual_sha256" == 0D8A10DA627B134F22C2B6AB7FB2D7CFE5E4A0B462D6BC2FF0C437F2013D7129 ]]
echo 'Adding temporary admin-domain codeSign-only trust for the exact original certificate.'
bounded_security sudo -n security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$cert"
echo 'Scoped trust added; signing the probe.'
security find-identity -v -p codesigning "$keychain" | grep -F "$expected"
export VOICEINK_SIGNING_KEYCHAIN="$keychain"
printf 'int main(void) { return 0; }\n' > "$RUNNER_TEMP/signing-probe.c"
/usr/bin/clang "$RUNNER_TEMP/signing-probe.c" -o "$RUNNER_TEMP/signing-probe"
codesign --force --sign "$SIGNING_IDENTITY_SHA1" --keychain "$keychain" --timestamp=none "$RUNNER_TEMP/signing-probe"
codesign --verify --strict --verbose=2 "$RUNNER_TEMP/signing-probe"
codesign -d --extract-certificates "$RUNNER_TEMP/probe-cert" "$RUNNER_TEMP/signing-probe"
actual=$(shasum "$RUNNER_TEMP/probe-cert0" | awk '{print toupper($1)}')
test "$actual" = "$SIGNING_IDENTITY_SHA1"
echo 'Direct signature and leaf fingerprint verified with temporary codeSign-only trust.'
rm -f "$RUNNER_TEMP/signing-probe.c" "$RUNNER_TEMP/signing-probe" "$RUNNER_TEMP/probe-cert0"
