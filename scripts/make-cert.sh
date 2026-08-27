#!/usr/bin/env bash
# One-time setup: create a self-signed code signing certificate.
#
# WHY THIS EXISTS
# ---------------
# macOS remembers "this app may use Accessibility" by recognising the app's code
# signature. An ad-hoc signature is a different identity every single build, so
# macOS treats each rebuild as a brand new app and drops the permission. You
# would be re-granting access in System Settings after every code change.
#
# A stable self-signed certificate fixes that: same identity every build.
#
# WHAT IT CHANGES ON YOUR MACHINE
#   Adds one certificate + private key to your login keychain. Nothing else --
#   no trust settings, no admin rights, no password prompt.
# Undo with:  security delete-certificate -c "Rephraze Dev"
set -euo pipefail

CERT_NAME="${REPHRAZE_SIGN_ID:-Rephraze Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# Can we already sign with this name? That is the only test that matters --
# `find-identity -v` hides self-signed certs because they chain to no trusted
# root, even though codesign accepts them perfectly well.
can_sign() {
  local probe; probe="$(mktemp)"
  cp /bin/echo "$probe"
  local ok=1
  codesign --force --sign "$CERT_NAME" --timestamp=none "$probe" >/dev/null 2>&1 && ok=0
  rm -f "$probe"
  return $ok
}

if can_sign; then
  echo "Signing identity '$CERT_NAME' already works. Nothing to do."
  exit 0
fi

cat <<EOF

This creates a self-signed code signing certificate called "$CERT_NAME"
and adds it to your login keychain.

No admin rights and no password needed. Undo any time with:
    security delete-certificate -c "$CERT_NAME"

EOF

read -r -p "Go ahead? [y/N] " reply
[[ "$reply" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Generating certificate"
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -days 3650 \
  -subj "/CN=$CERT_NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# The password must NOT be empty. Apple's importer fails MAC verification on
# empty-password PKCS12 files produced by LibreSSL. It is a transport password
# only -- the bundle is deleted seconds from now.
TRANSPORT_PW="rephraze-transport-$$"
openssl pkcs12 -export -out "$WORK/cert.p12" \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -passout "pass:$TRANSPORT_PW" 2>/dev/null

echo "==> Importing into login keychain"
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P "$TRANSPORT_PW" \
  -T /usr/bin/codesign > /dev/null

# Deliberately NOT running `security add-trusted-cert`. codesign is happy with
# an untrusted self-signed cert (it just prints a harmless warning about not
# building a chain to a trusted root), and skipping it avoids an admin prompt.

echo
if can_sign; then
  echo "Done. '$CERT_NAME' is ready. Run 'make install' to rebuild with it."
  echo
  echo "If macOS asks whether codesign may use the key, click 'Always Allow'."
else
  echo "Certificate imported but signing still fails."
  echo "Fallback: Keychain Access > Certificate Assistant > Create a Certificate."
  echo "Name it exactly '$CERT_NAME', Identity Type 'Self Signed Root',"
  echo "Certificate Type 'Code Signing'."
  exit 1
fi
