#!/usr/bin/env bash
# Create a stable self-signed code-signing identity ("SnapKeep Dev") in the login
# keychain so Screen Recording (and other TCC) grants survive rebuilds. Idempotent.
set -euo pipefail

IDENTITY="SnapKeep Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# A self-signed cert isn't listed by `find-identity -p codesigning` (that needs trust),
# so check for the certificate itself.
if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "✓ '$IDENTITY' already exists — nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = SnapKeep Dev
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

echo "→ Generating self-signed code-signing certificate…"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" >/dev/null 2>&1

# -legacy + a real password: macOS `security` rejects OpenSSL 3's modern PKCS#12
# encryption and empty-password MACs, so both are required for a clean import.
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/id.p12" -passout pass:snapkeep -name "$IDENTITY" >/dev/null 2>&1

echo "→ Importing into the login keychain…"
# -A lets any tool use the key without a per-sign prompt; -T names codesign explicitly.
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "snapkeep" -A -T /usr/bin/codesign >/dev/null 2>&1

echo "✓ Created '$IDENTITY'. Rebuild with ./scripts/bootstrap.sh and grant Screen"
echo "  Recording once — the grant now persists across rebuilds."
