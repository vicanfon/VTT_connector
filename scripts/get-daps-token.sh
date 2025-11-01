#!/usr/bin/env bash
# Request a valid DAT (Dynamic Attribute Token) from DAPS
# This token can be used to test connector endpoints

set -e

DAPS_URL="${1:-https://localhost/auth}"
CLIENT_ID="${2}"

echo "=========================================="
echo "DAPS Token Acquisition Guide"
echo "=========================================="
echo ""
echo "DAPS URL: $DAPS_URL"
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Step 1: Check if DAPS is accessible
echo "=========================================="
echo "Step 1: Verify DAPS Accessibility"
echo "=========================================="
echo ""

DAPS_HTTP=$(curl -k -s -o /dev/null -w "%{http_code}" "$DAPS_URL/jwks.json")
if [ "$DAPS_HTTP" = "200" ]; then
    echo -e "${GREEN}✓ DAPS is accessible${NC}"
else
    echo -e "${RED}✗ DAPS not accessible (HTTP $DAPS_HTTP)${NC}"
    exit 1
fi

echo ""

# Step 2: List registered clients
echo "=========================================="
echo "Step 2: Check Registered Clients"
echo "=========================================="
echo ""

if [ -f "config/clients.yml" ]; then
    echo "Registered clients in DAPS:"
    echo ""

    # Parse clients.yml to show client IDs
    grep -E "^- |  client_id:|  name:" config/clients.yml | while read line; do
        echo "  $line"
    done

    echo ""
else
    echo -e "${YELLOW}⚠ config/clients.yml not found${NC}"
    echo "You may need to register a client first."
fi

echo ""

# Step 3: Explain how to get client credentials
echo "=========================================="
echo "Step 3: Client Credentials Required"
echo "=========================================="
echo ""

if [ -z "$CLIENT_ID" ]; then
    echo "To request a DAT token, you need:"
    echo "  1. Client ID (from DAPS registration)"
    echo "  2. Client certificate (private key)"
    echo "  3. Certificate keystore/file"
    echo ""
    echo "Usage:"
    echo "  $0 <DAPS_URL> <CLIENT_ID>"
    echo ""
    echo "Example:"
    echo "  $0 https://localhost/auth 12:34:56:78:9A:BC:..."
    echo ""

    # Try to extract SKI from connector keystore
    if [ -f "conf/default-connector-keystore.p12" ]; then
        echo -e "${BLUE}Attempting to extract connector SKI...${NC}"

        CERT_SKI=$(keytool -list -v -keystore conf/default-connector-keystore.p12 -storepass password 2>/dev/null | \
            grep -A1 "SubjectKeyIdentifier" | tail -1 | tr -d ' :' | tr '[:upper:]' '[:lower:]')

        if [ ! -z "$CERT_SKI" ]; then
            echo -e "${GREEN}Found connector SKI: $CERT_SKI${NC}"
            echo ""
            echo "Try running:"
            echo "  $0 $DAPS_URL $CERT_SKI"
        fi
    fi

    exit 0
fi

echo "Client ID: $CLIENT_ID"
echo ""

# Step 4: Check if this client is registered
echo "=========================================="
echo "Step 4: Verify Client Registration"
echo "=========================================="
echo ""

if [ -f "config/clients.yml" ]; then
    if grep -q "$CLIENT_ID" config/clients.yml; then
        echo -e "${GREEN}✓ Client $CLIENT_ID is registered in DAPS${NC}"

        # Extract client info
        echo ""
        echo "Client information:"
        grep -A 20 "$CLIENT_ID" config/clients.yml | head -20
    else
        echo -e "${RED}✗ Client $CLIENT_ID not found in DAPS${NC}"
        echo ""
        echo "You need to register this client first."
        echo "See the registration guide below."
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ Cannot verify client registration (config/clients.yml not found)${NC}"
fi

echo ""

# Step 5: Methods to get a token
echo "=========================================="
echo "Step 5: Token Acquisition Methods"
echo "=========================================="
echo ""

echo "There are several ways to get a DAT token:"
echo ""

# Method 1: Simple client credentials (if supported)
echo -e "${BLUE}Method 1: Client Credentials Grant (Simple)${NC}"
echo "-----------------------------------------------"
echo ""
echo "If your DAPS supports client credentials with client secret:"
echo ""
echo "curl -k -X POST $DAPS_URL/token \\"
echo "  -H 'Content-Type: application/x-www-form-urlencoded' \\"
echo "  -d 'grant_type=client_credentials' \\"
echo "  -d 'client_id=$CLIENT_ID' \\"
echo "  -d 'client_secret=YOUR_CLIENT_SECRET' \\"
echo "  -d 'scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL'"
echo ""
echo "Note: This requires a client secret configured in DAPS"
echo ""

# Method 2: JWT Bearer assertion (IDS standard)
echo -e "${BLUE}Method 2: JWT Bearer Assertion (IDS Standard)${NC}"
echo "-----------------------------------------------"
echo ""
echo "The standard IDS way using certificate-based authentication:"
echo ""
echo "1. Create a JWT assertion signed with your certificate"
echo "2. Send the assertion to DAPS to get a DAT token"
echo ""
echo "This is more complex and requires:"
echo "  - Your client certificate and private key"
echo "  - A tool to create and sign JWTs"
echo "  - Proper JWT structure with required claims"
echo ""

# Method 3: Use existing connector token
echo -e "${BLUE}Method 3: Extract Token from Connector (Easiest for Testing)${NC}"
echo "-----------------------------------------------"
echo ""
echo "The connector itself requests DAT tokens. You can extract one from logs:"
echo ""
echo "docker compose logs connector | grep -i 'token' | grep -i 'bearer\\|dat\\|jwt'"
echo ""
echo "Or check if connector exposes it via environment/config"
echo ""

echo ""

# Practical example: Try to get a token
echo "=========================================="
echo "Step 6: Attempt Token Request"
echo "=========================================="
echo ""

echo "Attempting to request a token using admin credentials..."
echo "(This may not work if DAPS requires certificate-based auth)"
echo ""

# Try with default admin credentials (common in dev environments)
TOKEN_RESPONSE=$(curl -k -s -X POST "$DAPS_URL/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials" \
    -d "client_id=admin" \
    -d "client_secret=admin" \
    -d "scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL" 2>&1)

TOKEN_HTTP=$(curl -k -s -o /dev/null -w "%{http_code}" -X POST "$DAPS_URL/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials" \
    -d "client_id=admin" \
    -d "client_secret=admin" \
    -d "scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL")

if [ "$TOKEN_HTTP" = "200" ]; then
    echo -e "${GREEN}✓ Token obtained successfully!${NC}"
    echo ""
    echo "Response:"
    echo "$TOKEN_RESPONSE" | jq '.' 2>/dev/null || echo "$TOKEN_RESPONSE"

    # Extract access token
    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token' 2>/dev/null)

    if [ ! -z "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ]; then
        echo ""
        echo -e "${GREEN}Access Token:${NC}"
        echo "$ACCESS_TOKEN"
        echo ""
        echo -e "${GREEN}You can now test with this token:${NC}"
        echo ""
        echo "curl -k -H 'Authorization: Bearer $ACCESS_TOKEN' \\"
        echo "  https://localhost:8081/api/offers"
        echo ""

        # Save to file
        echo "$ACCESS_TOKEN" > /tmp/daps-token.txt
        echo "Token saved to: /tmp/daps-token.txt"
        echo ""
        echo "Test command:"
        echo "curl -k -H \"Authorization: Bearer \$(cat /tmp/daps-token.txt)\" \\"
        echo "  https://localhost:8081/api/offers"
    fi
else
    echo -e "${YELLOW}⚠ Token request failed (HTTP $TOKEN_HTTP)${NC}"
    echo ""
    echo "Response:"
    echo "$TOKEN_RESPONSE"
    echo ""
    echo "This is expected if DAPS requires certificate-based authentication."
fi

echo ""
echo ""

# Registration guide
echo "=========================================="
echo "HOW TO REGISTER A CLIENT IN DAPS"
echo "=========================================="
echo ""
echo "If you need to register a new client:"
echo ""
echo "1. Access DAPS Admin UI:"
echo "   URL: $DAPS_URL/ (or https://localhost/)"
echo "   Login: admin / admin (default credentials)"
echo ""
echo "2. Navigate to 'Clients' section"
echo ""
echo "3. Click 'Add Client' and provide:"
echo "   - Client ID: Use the certificate SKI (Subject Key Identifier)"
echo "   - Client Name: A friendly name for your connector"
echo "   - Grant Types: client_credentials"
echo "   - Scope: idsc:IDS_CONNECTOR_ATTRIBUTES_ALL"
echo ""
echo "4. Upload certificate (optional but recommended):"
echo "   Extract certificate from keystore:"
echo "   keytool -exportcert -alias 1 \\"
echo "     -keystore conf/default-connector-keystore.p12 \\"
echo "     -storepass password -file connector.crt"
echo ""
echo "5. Configure client authentication:"
echo "   - Certificate-based: Upload the certificate"
echo "   - Secret-based: Set a client secret"
echo ""
echo "6. Save the client configuration"
echo ""

echo ""
echo "=========================================="
echo "ALTERNATIVE: Using DAPS REST API"
echo "=========================================="
echo ""
echo "You can also register clients via DAPS API (if enabled):"
echo ""
echo "curl -k -X POST $DAPS_URL/api/v1/clients \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -H 'Authorization: Bearer ADMIN_TOKEN' \\"
echo "  -d '{"
echo "    \"client_id\": \"$CLIENT_ID\","
echo "    \"client_name\": \"My Connector\","
echo "    \"grant_types\": [\"client_credentials\"],"
echo "    \"scope\": \"idsc:IDS_CONNECTOR_ATTRIBUTES_ALL\""
echo "  }'"
echo ""

echo ""
echo "=========================================="
echo "TESTING WITHOUT A REAL TOKEN"
echo "=========================================="
echo ""
echo "For testing DAPS validation, you don't actually need a valid token!"
echo ""
echo "Instead, test the connector's behavior:"
echo ""
echo "1. Test without any token:"
echo "   curl -k https://localhost:8081/api/offers"
echo "   Expected: 401 Unauthorized (if DAPS validation is active)"
echo ""
echo "2. Test with an invalid token:"
echo "   curl -k -H 'Authorization: Bearer FAKE_TOKEN' \\"
echo "     https://localhost:8081/api/offers"
echo "   Expected: 403 Forbidden (connector validated and rejected the token)"
echo ""
echo "3. If you get 401 or 403, DAPS validation IS working!"
echo "   You don't need a valid token to prove that."
echo ""
echo "Run the validation test script:"
echo "  ./scripts/test-daps-validation.sh"
echo ""
