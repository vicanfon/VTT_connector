#!/usr/bin/env bash
# Script to verify connector registration and DAPS validation
# This tests if a connector is a valid participant in the dataspace

set -e

CONNECTOR_URL="${1:-https://localhost/connector}"
DAPS_URL="${2:-https://localhost/auth}"
BROKER_URL="${3:-https://localhost/broker}"

echo "======================================"
echo "DAPS & Connector Validation Test"
echo "======================================"
echo ""
echo "Connector URL: $CONNECTOR_URL"
echo "DAPS URL: $DAPS_URL"
echo "Broker URL: $BROKER_URL"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test 1: Check if DAPS is accessible
echo "======================================"
echo "Test 1: DAPS Accessibility"
echo "======================================"
echo "Checking DAPS JWKS endpoint..."
DAPS_JWKS=$(curl -k -s -w "\n%{http_code}" "$DAPS_URL/jwks.json" | tail -1)
if [ "$DAPS_JWKS" = "200" ]; then
    echo -e "${GREEN}✓ DAPS JWKS endpoint accessible (HTTP 200)${NC}"
else
    echo -e "${RED}✗ DAPS JWKS endpoint failed (HTTP $DAPS_JWKS)${NC}"
fi
echo ""

# Test 2: Check DAPS OpenID Configuration
echo "======================================"
echo "Test 2: DAPS OpenID Configuration"
echo "======================================"
DAPS_CONFIG=$(curl -k -s -w "\n%{http_code}" "$DAPS_URL/.well-known/openid-configuration" | tail -1)
if [ "$DAPS_CONFIG" = "200" ]; then
    echo -e "${GREEN}✓ DAPS OpenID configuration accessible${NC}"
    curl -k -s "$DAPS_URL/.well-known/openid-configuration" | jq -r '.issuer, .token_endpoint, .jwks_uri' 2>/dev/null || echo "Install jq for formatted output"
else
    echo -e "${RED}✗ DAPS OpenID configuration failed (HTTP $DAPS_CONFIG)${NC}"
fi
echo ""

# Test 3: Check Connector Self-Description
echo "======================================"
echo "Test 3: Connector Self-Description"
echo "======================================"
echo "Testing connector self-description endpoint..."
CONNECTOR_SELF=$(curl -k -s -w "\n%{http_code}" "$CONNECTOR_URL/" | tail -1)
if [ "$CONNECTOR_SELF" = "200" ]; then
    echo -e "${GREEN}✓ Connector self-description accessible (HTTP 200)${NC}"
    echo "Connector ID and description:"
    curl -k -s "$CONNECTOR_URL/" | jq -r '.["@id"], .["ids:securityProfile"]["@id"]' 2>/dev/null || echo "Response received"
else
    echo -e "${YELLOW}⚠ Connector self-description returned HTTP $CONNECTOR_SELF${NC}"
fi
echo ""

# Test 4: Check Connector IDS Infrastructure
echo "======================================"
echo "Test 4: IDS Infrastructure Endpoint"
echo "======================================"
echo "Testing IDS data endpoint..."
IDS_DATA=$(curl -k -s -w "\n%{http_code}" "$CONNECTOR_URL/api/ids/data" | tail -1)
if [ "$IDS_DATA" = "200" ] || [ "$IDS_DATA" = "400" ]; then
    echo -e "${GREEN}✓ IDS endpoint is responding (HTTP $IDS_DATA)${NC}"
    if [ "$IDS_DATA" = "400" ]; then
        echo -e "${YELLOW}  Note: HTTP 400 is expected without proper IDS message${NC}"
    fi
else
    echo -e "${RED}✗ IDS endpoint failed (HTTP $IDS_DATA)${NC}"
fi
echo ""

# Test 5: Check if connector can reach DAPS
echo "======================================"
echo "Test 5: Connector to DAPS Connectivity"
echo "======================================"
echo "Checking if connector is configured to use DAPS..."
docker compose exec -T connector env | grep -E '(DAPS_URL|DAPS_TOKEN_URL|DAPS_KEY_URL)' || echo "DAPS environment variables not found"
echo ""

# Test 6: Broker Connectivity
echo "======================================"
echo "Test 6: Broker Infrastructure"
echo "======================================"
echo "Testing broker infrastructure endpoint..."
BROKER_INFRA=$(curl -k -s -w "\n%{http_code}" "$BROKER_URL/infrastructure/" | tail -1)
if [ "$BROKER_INFRA" = "200" ] || [ "$BROKER_INFRA" = "400" ]; then
    echo -e "${GREEN}✓ Broker infrastructure endpoint responding (HTTP $BROKER_INFRA)${NC}"
else
    echo -e "${YELLOW}⚠ Broker infrastructure returned HTTP $BROKER_INFRA${NC}"
fi
echo ""

# Test 7: Check connector logs for DAPS token requests
echo "======================================"
echo "Test 7: Connector DAPS Token Activity"
echo "======================================"
echo "Checking connector logs for DAPS interactions..."
echo "Recent DAPS-related log entries:"
docker compose logs connector 2>/dev/null | grep -i -E "(daps|token|dat)" | tail -5 || echo "No DAPS activity found in logs"
echo ""

# Test 8: Test a protected endpoint (requires valid DAT)
echo "======================================"
echo "Test 8: Protected Endpoint Test"
echo "======================================"
echo "Testing connector API endpoint that requires authentication..."
API_TEST=$(curl -k -s -w "\n%{http_code}" "$CONNECTOR_URL/api/offers" | tail -1)
if [ "$API_TEST" = "200" ]; then
    echo -e "${GREEN}✓ Protected endpoint accessible (HTTP 200)${NC}"
    echo "This suggests the connector has valid authentication"
elif [ "$API_TEST" = "401" ] || [ "$API_TEST" = "403" ]; then
    echo -e "${YELLOW}⚠ Authentication required (HTTP $API_TEST)${NC}"
    echo "To test with authentication, you need to provide a valid DAT token"
else
    echo -e "${YELLOW}⚠ API returned HTTP $API_TEST${NC}"
fi
echo ""

# Summary
echo "======================================"
echo "Summary & Next Steps"
echo "======================================"
echo ""
echo "To fully test DAPS validation, you need to:"
echo "1. Register a connector client in DAPS (via Omejdn UI at https://localhost/)"
echo "2. Generate a client certificate and keystore"
echo "3. Request a DAT (Dynamic Attribute Token) from DAPS"
echo "4. Use that token to make authenticated IDS calls"
echo ""
echo "For manual testing:"
echo "  - DAPS Admin UI: https://localhost/ (user: admin, pass: admin)"
echo "  - Connector API: $CONNECTOR_URL/api/docs"
echo "  - Broker: $BROKER_URL/infrastructure/"
echo ""
echo "To test with IDS messages:"
echo "  curl -k -X POST $CONNECTOR_URL/api/ids/data \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"@type\":\"ids:DescriptionRequestMessage\"}'"
echo ""
