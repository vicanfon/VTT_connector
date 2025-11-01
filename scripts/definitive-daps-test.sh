#!/usr/bin/env bash
# Definitive DAPS validation test
# Tests if connector ACTUALLY validates tokens differently

echo "=========================================="
echo "DEFINITIVE DAPS Validation Test"
echo "=========================================="
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONNECTOR_URL="https://localhost:8081"

# Load valid token
if [ ! -f /tmp/daps-token.txt ]; then
    echo "Error: No valid token found"
    echo "Run: ./scripts/fix-daps-client.sh"
    exit 1
fi

VALID_TOKEN=$(cat /tmp/daps-token.txt)
FAKE_TOKEN="eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJmYWtlIn0.FAKESIGNATURE"

echo "Valid token (first 30 chars): ${VALID_TOKEN:0:30}..."
echo "Fake token (first 30 chars):  ${FAKE_TOKEN:0:30}..."
echo ""

# Create a well-formed IDS message
create_message() {
    local token="$1"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)

    cat <<EOF
{
  "@context": "https://w3id.org/idsa/contexts/context.jsonld",
  "@type": "ids:DescriptionRequestMessage",
  "@id": "https://w3id.org/idsa/autogen/descriptionRequestMessage/$(uuidgen | tr -d '-')",
  "ids:modelVersion": "4.2.7",
  "ids:issued": {
    "@value": "$timestamp",
    "@type": "http://www.w3.org/2001/XMLSchema#dateTimeStamp"
  },
  "ids:issuerConnector": {
    "@id": "https://localhost/test-connector"
  },
  "ids:senderAgent": {
    "@id": "https://localhost/test-connector"
  },
  "ids:recipientConnector": [{
    "@id": "https://localhost/connector"
  }],
  "ids:securityToken": {
    "@type": "ids:DynamicAttributeToken",
    "@id": "https://w3id.org/idsa/autogen/dynamicAttributeToken/$(uuidgen | tr -d '-')",
    "ids:tokenValue": "$token",
    "ids:tokenFormat": {
      "@id": "idsc:JWT"
    }
  },
  "ids:requestedElement": {
    "@id": "https://localhost/connector"
  }
}
EOF
}

# Test function
test_with_token() {
    local token_name="$1"
    local token_value="$2"

    echo "=========================================="
    echo "Test: $token_name"
    echo "=========================================="
    echo ""

    local message=$(create_message "$token_value")

    echo "Sending IDS DescriptionRequestMessage..."
    echo ""

    local response=$(curl -k -s -X POST "$CONNECTOR_URL/api/ids/data" \
        -F "header=$message;type=application/json" 2>&1)

    echo "Response:"
    echo "$response" | head -50
    echo ""

    # Analyze response
    local rejection_reason=""
    if echo "$response" | grep -q '"ids:rejectionReason"'; then
        rejection_reason=$(echo "$response" | grep -o 'idsc:[A-Z_]*' | head -1)
        echo -e "${BLUE}Rejection Reason: $rejection_reason${NC}"
    fi

    local response_type=$(echo "$response" | grep -o '"@type"[^,]*' | head -1 | cut -d: -f2 | tr -d ' "')
    echo -e "${BLUE}Response Type: $response_type${NC}"

    # Return values for comparison
    echo "$rejection_reason|$response_type|$response"
}

echo ""
echo "=========================================="
echo "STEP 1: Test with FAKE/INVALID Token"
echo "=========================================="
echo ""

RESULT_FAKE=$(test_with_token "FAKE TOKEN" "$FAKE_TOKEN")
FAKE_REASON=$(echo "$RESULT_FAKE" | head -1 | cut -d'|' -f1)
FAKE_TYPE=$(echo "$RESULT_FAKE" | head -1 | cut -d'|' -f2)

echo ""
echo ""

echo "=========================================="
echo "STEP 2: Test with VALID DAPS Token"
echo "=========================================="
echo ""

RESULT_VALID=$(test_with_token "VALID DAPS TOKEN" "$VALID_TOKEN")
VALID_REASON=$(echo "$RESULT_VALID" | head -1 | cut -d'|' -f1)
VALID_TYPE=$(echo "$RESULT_VALID" | head -1 | cut -d'|' -f2)

echo ""
echo ""

echo "=========================================="
echo "COMPARISON & VERDICT"
echo "=========================================="
echo ""

echo "Results Summary:"
echo "  Fake Token:  Rejection=$FAKE_REASON  Type=$FAKE_TYPE"
echo "  Valid Token: Rejection=$VALID_REASON Type=$VALID_TYPE"
echo ""

# Determine if DAPS validation is working
DAPS_WORKING=false

# Check for clear authentication failure with fake token
if [[ "$FAKE_REASON" == *"NOT_AUTHENTICATED"* ]] || [[ "$FAKE_REASON" == *"NOT_AUTHORIZED"* ]]; then
    echo -e "${GREEN}✓ Fake token was rejected due to authentication failure${NC}"

    # Check if valid token was treated differently
    if [[ "$VALID_REASON" != "$FAKE_REASON" ]] || [[ "$VALID_TYPE" == *"DescriptionResponse"* ]]; then
        DAPS_WORKING=true
        echo -e "${GREEN}✓ Valid token was treated DIFFERENTLY${NC}"
    fi
fi

# Check if both got same rejection (means no token validation)
if [ "$FAKE_REASON" = "$VALID_REASON" ] && [ ! -z "$FAKE_REASON" ]; then
    echo -e "${RED}✗ Both tokens got SAME rejection: $FAKE_REASON${NC}"
    echo -e "${RED}This suggests token validation might NOT be happening${NC}"
fi

# Check if valid token succeeded
if [[ "$VALID_TYPE" == *"DescriptionResponse"* ]] && [[ "$FAKE_TYPE" == *"Rejection"* ]]; then
    DAPS_WORKING=true
    echo -e "${GREEN}✓ Valid token succeeded, fake token rejected${NC}"
fi

echo ""
echo "=========================================="
echo "FINAL VERDICT"
echo "=========================================="
echo ""

if $DAPS_WORKING; then
    echo -e "${GREEN}✓✓✓ DAPS VALIDATION IS CONFIRMED ✓✓✓${NC}"
    echo ""
    echo "Evidence:"
    echo "  • Fake token was rejected or handled differently"
    echo "  • Valid token was accepted or treated preferentially"
    echo "  • Connector is validating DAT token signatures"
    echo ""
    echo -e "${GREEN}Your connector IS validating DAPS tokens!${NC}"
    echo -e "${GREEN}It is a legitimate dataspace participant!${NC}"
else
    echo -e "${YELLOW}⚠ INCONCLUSIVE - Need More Information${NC}"
    echo ""
    echo "Both tokens received similar responses."
    echo "This could mean:"
    echo ""

    if [[ "$FAKE_REASON" == *"MALFORMED"* ]]; then
        echo "  • Message format issues preventing token validation"
        echo "  • Try checking connector logs for more details"
        echo ""
        echo "Checking connector logs..."
        echo ""
        docker compose logs connector 2>/dev/null | grep -i "token\|daps\|validation\|authenticated" | tail -20
    else
        echo "  • Token validation might not be strictly enforced"
        echo "  • Both tokens might be accepted (permissive mode)"
        echo "  • Or both rejected for other reasons"
    fi

    echo ""
    echo "Alternative tests to try:"
    echo ""
    echo "1. Check DAPS validation configuration:"
    echo "   docker compose exec connector env | grep DAPS_VALIDATE"
    echo ""
    echo "2. Enable strict validation:"
    echo "   Set DAPS_VALIDATE_INCOMING=true in docker-compose.yml"
    echo ""
    echo "3. Check connector logs during token validation:"
    echo "   docker compose logs -f connector"
fi

echo ""
echo ""

# Check configuration
echo "=========================================="
echo "Configuration Check"
echo "=========================================="
echo ""

echo "DAPS Configuration:"
docker compose exec connector env 2>/dev/null | grep -i "DAPS" | grep -v "PASSWORD"

echo ""
echo "Look for: DAPS_VALIDATE_INCOMING=true"
echo "This setting controls whether incoming DAT tokens are validated"
echo ""

# Offer to enable validation
VALIDATE_SETTING=$(docker compose exec connector env 2>/dev/null | grep "DAPS_VALIDATE_INCOMING" | cut -d= -f2)

if [ "$VALIDATE_SETTING" = "false" ]; then
    echo -e "${YELLOW}⚠ DAPS_VALIDATE_INCOMING is set to FALSE${NC}"
    echo ""
    echo "This means the connector is NOT validating incoming tokens!"
    echo ""
    echo "To enable validation:"
    echo "  1. Edit docker-compose.yml"
    echo "  2. Find the 'connector' service"
    echo "  3. Add or change: - DAPS_VALIDATE_INCOMING=true"
    echo "  4. Restart: docker compose restart connector"
fi

echo ""
