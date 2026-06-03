#!/bin/bash
# setup-codesign.sh
# One-time setup: creates a local self-signed code-signing certificate in your
# login keychain so the EVE Imager app can be signed permanently without an
# Apple Developer account.
#
# Run once per machine. The certificate is valid for 10 years.
set -e

CERT_NAME="EVE Imager Dev"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
  echo "Certificate '$CERT_NAME' already exists in keychain — nothing to do."
  exit 0
fi

echo "Creating self-signed code-signing certificate: $CERT_NAME"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Generate private key + self-signed cert with Code Signing EKU (10 year validity)
openssl req -x509 -newkey rsa:2048 \
  -keyout "$TMPDIR/key.pem" \
  -out "$TMPDIR/cert.pem" \
  -days 3650 -nodes \
  -subj "/CN=$CERT_NAME/O=ZEDEDA/C=US" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false" \
  2>/dev/null

# Bundle into PKCS12
PASS="$(openssl rand -hex 16)"
openssl pkcs12 -export -legacy \
  -out "$TMPDIR/cert.p12" \
  -inkey "$TMPDIR/key.pem" \
  -in "$TMPDIR/cert.pem" \
  -passout "pass:$PASS" 2>/dev/null

# Import into login keychain
security import "$TMPDIR/cert.p12" \
  -k ~/Library/Keychains/login.keychain-db \
  -P "$PASS" \
  -T /usr/bin/codesign \
  -A

# Trust for code signing
security add-trusted-cert \
  -d -r trustRoot \
  -k ~/Library/Keychains/login.keychain-db \
  "$TMPDIR/cert.pem"

echo ""
echo "Done! '$CERT_NAME' is now trusted for code signing on this machine."
echo "Run './run-dev.sh' to sign and launch the app."
