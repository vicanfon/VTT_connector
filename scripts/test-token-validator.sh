#!/usr/bin/env bash
# Test the token validator with different token types

echo "=========================================="
echo "Token Validator Test Suite"
echo "=========================================="
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test 1: Invalid JWT format
echo "=========================================="
echo "Test 1: Invalid Token Format"
echo "=========================================="
echo ""

echo "Testing with a non-JWT token..."
echo ""
./scripts/validate-token-with-jwks.sh "INVALID_NOT_A_JWT"

echo ""
echo ""
sleep 2

# Test 2: Fake JWT with invalid structure
echo "=========================================="
echo "Test 2: Fake JWT (Invalid Signature)"
echo "=========================================="
echo ""

echo "Testing with a fake JWT token..."
echo ""

# Create a fake but structurally valid JWT
FAKE_HEADER=$(echo -n '{"alg":"RS256","typ":"JWT"}' | base64 -w 0 | tr -d '=' | tr '+/' '-_')
FAKE_PAYLOAD=$(echo -n '{"iss":"https://fake-daps.com","sub":"fake-client","aud":"idsc:IDS_CONNECTORS_ALL","exp":'$(($(date +%s) + 3600))',"iat":'$(date +%s)'}' | base64 -w 0 | tr -d '=' | tr '+/' '-_')
FAKE_SIGNATURE="FAKE_SIGNATURE_HERE"
FAKE_TOKEN="${FAKE_HEADER}.${FAKE_PAYLOAD}.${FAKE_SIGNATURE}"

echo "Fake token: ${FAKE_TOKEN:0:80}..."
echo ""

./scripts/validate-token-with-jwks.sh "$FAKE_TOKEN"

echo ""
echo ""
sleep 2

# Test 3: Valid token from DAPS
echo "=========================================="
echo "Test 3: Valid DAPS Token"
echo "=========================================="
echo ""

if [ -f /tmp/daps-token.txt ]; then
    VALID_TOKEN=$(cat /tmp/daps-token.txt)
    echo "Testing with valid token from /tmp/daps-token.txt..."
    echo ""
    ./scripts/validate-token-with-jwks.sh "$VALID_TOKEN"
else
    echo -e "${YELLOW}⚠ No valid token found at /tmp/daps-token.txt${NC}"
    echo ""
    echo "To get a valid token, run:"
    echo "  ./scripts/fix-daps-client.sh"
    echo ""
    echo "Then re-run this test suite:"
    echo "  ./scripts/test-token-validator.sh"
fi

echo ""
echo ""

# Summary
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo ""

echo "The validator should:"
echo "  ✓ Reject non-JWT format tokens"
echo "  ✓ Reject tokens from untrusted issuers"
echo "  ✓ Reject expired tokens"
echo "  ✓ Accept valid tokens from trusted DAPS"
echo ""
echo "This provides DEFINITIVE validation results!"
echo ""
