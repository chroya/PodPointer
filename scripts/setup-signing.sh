#!/bin/bash
# One-time: create a self-signed code-signing certificate in a *separate* keychain
# (your login keychain is not touched, and the new keychain is not added to the
# search list permanently). scripts/build.sh then signs with it, giving the app a
# stable designated requirement so the Accessibility permission survives rebuilds.
#
# Undo:
#   security delete-keychain ~/Library/Keychains/podpointer-sign.keychain-db
#   rm -rf .signing
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DIR=.signing
KC="$HOME/Library/Keychains/podpointer-sign.keychain-db"
NAME="PodPointer Local Signing"

if [ -f "$KC" ] && [ -f "$DIR/keychain-password" ]; then
  echo "Already set up: $KC"
  exit 0
fi

mkdir -p "$DIR"; chmod 700 "$DIR"
KC_PASS=$(openssl rand -hex 24)
P12_PASS=$(openssl rand -hex 16)
printf '%s' "$KC_PASS" > "$DIR/keychain-password"; chmod 600 "$DIR/keychain-password"

cat > "$DIR/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = ${NAME}
[ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# /usr/bin/openssl (LibreSSL) writes PKCS#12 in a format `security import` accepts.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$DIR/key.pem" -out "$DIR/cert.pem" -config "$DIR/cert.cnf" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" \
  -name "$NAME" -out "$DIR/identity.p12" -passout pass:"$P12_PASS"

security create-keychain -p "$KC_PASS" "$KC"
security set-keychain-settings "$KC"            # no auto-lock
security unlock-keychain -p "$KC_PASS" "$KC"
security import "$DIR/identity.p12" -k "$KC" -P "$P12_PASS" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KC" >/dev/null
rm -f "$DIR/identity.p12" "$DIR/key.pem"         # the private key now lives only in the keychain

echo "Created certificate \"${NAME}\" in ${KC}"
echo "Next: scripts/build.sh"
