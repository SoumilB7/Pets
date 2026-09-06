#!/bin/zsh
# One-time: create a local self-signed code-signing certificate "PixelPet Dev" so the app's
# identity stays the same across rebuilds and macOS keeps the Accessibility grant.
# May show one or two macOS password prompts (keychain trust + codesign key access).
set -e
NAME="PixelPet Dev"
if security find-certificate -c "$NAME" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1; then
  echo "certificate '$NAME' already exists"; exit 0
fi
T=$(mktemp -d)
cat > "$T/cfg" <<CFG
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
basicConstraints=critical,CA:false
CFG
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$T/cfg" -keyout "$T/key.pem" -out "$T/cert.pem" 2>/dev/null
openssl pkcs12 -export -out "$T/id.p12" -inkey "$T/key.pem" -in "$T/cert.pem" -passout pass:pixelpet -legacy 2>/dev/null || \
openssl pkcs12 -export -out "$T/id.p12" -inkey "$T/key.pem" -in "$T/cert.pem" -passout pass:pixelpet
security import "$T/id.p12" -k ~/Library/Keychains/login.keychain-db -P pixelpet -T /usr/bin/codesign -T /usr/bin/security >/dev/null
# trust it for code signing (user trust settings; macOS may ask for your login password)
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db "$T/cert.pem" || true
rm -rf "$T"
echo "created '$NAME'"
security find-identity -v -p codesigning | grep -c "$NAME" >/dev/null && echo "identity is valid for code signing" || echo "identity present but not yet trusted (approve the prompt, then rerun)"
