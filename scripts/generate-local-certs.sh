#!/usr/bin/env bash
set -euo pipefail

# Generate self-signed SSL certificates for local development
# Usage: ./scripts/generate-local-certs.sh [hostname]

HOSTNAME=${1:-localhost}
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
CERT_DIR="$BASE_DIR/cert"

echo "Generating self-signed SSL certificates for local development..."
echo "Hostname: $HOSTNAME"
echo "Certificate directory: $CERT_DIR"

# Create cert directory if it doesn't exist
mkdir -p "$CERT_DIR"

# Generate self-signed certificate
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout "$CERT_DIR/server.key" \
  -out "$CERT_DIR/server.crt" \
  -subj "/CN=$HOSTNAME" \
  -days 365 \
  -addext "subjectAltName=DNS:$HOSTNAME,DNS:*.$HOSTNAME,IP:127.0.0.1"

echo ""
echo "✅ Certificates generated successfully!"
echo "   - Certificate: $CERT_DIR/server.crt"
echo "   - Private key: $CERT_DIR/server.key"
echo ""
echo "⚠️  WARNING: These are self-signed certificates for LOCAL DEVELOPMENT ONLY!"
echo "   DO NOT USE IN PRODUCTION!"
echo ""
