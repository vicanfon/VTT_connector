#!/usr/bin/env bash
# Test connector endpoints to verify DAPS validation without connecting to DAPS directly
# Strategy: Call protected endpoints - they will fail if DAPS validation is broken

set -e

CONNECTOR_URL="${1:-https://localhost:8081}"

echo "=========================================="
echo "Connector DAPS Validation Test"
echo "=========================================="
echo ""
echo "Testing: $CONNECTOR_URL"
echo ""
echo "Strategy: Call connector endpoints that require DAPS authentication."
echo "If they respond properly, the connector is validating DAPS tokens."
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# First, get the OpenAPI spec to find available endpoints
echo "=========================================="
echo "Step 1: Discovering API Endpoints"
echo "=========================================="
echo ""

API_SPEC=$(curl -k -s "$CONNECTOR_URL/v3/api-docs")
API_HTTP=$(curl -k -s -o /dev/null -w "%{http_code}" "$CONNECTOR_URL/v3/api-docs")

if [ "$API_HTTP" = "200" ]; then
    echo -e "${GREEN}✓ OpenAPI spec retrieved${NC}"

    # Extract some key endpoint paths
    echo ""
    echo "Available API endpoints:"
    echo "$API_SPEC" | jq -r '.paths | keys[]' 2>/dev/null | head -20 || echo "Could not parse endpoints"
else
    echo -e "${RED}✗ Could not retrieve OpenAPI spec (HTTP $API_HTTP)${NC}"
fi

echo ""
echo ""

# Test Strategy: Try endpoints without authentication
# If DAPS validation is working, protected endpoints should return 401/403

echo "=========================================="
echo "Step 2: Testing Endpoints (No Auth)"
echo "=========================================="
echo ""
echo "Testing endpoints WITHOUT authentication."
echo "Protected endpoints should return 401/403 if DAPS validation is active."
echo ""

# Array of endpoints to test
declare -A ENDPOINTS=(
    ["/api/offers"]="GET - List data offers"
    ["/api/resources"]="GET - List resources"
    ["/api/catalogs"]="GET - List catalogs"
    ["/api/agreements"]="GET - List agreements"
    ["/api/contracts"]="GET - List contracts"
    ["/api/representations"]="GET - List representations"
    ["/api/artifacts"]="GET - List artifacts"
    ["/api/broker/register"]="POST - Register with broker"
    ["/api/ids/description"]="GET - IDS self-description"
    ["/"]="GET - Connector self-description"
)

# Test each endpoint
PROTECTED_COUNT=0
PUBLIC_COUNT=0

for endpoint in "${!ENDPOINTS[@]}"; do
    DESC="${ENDPOINTS[$endpoint]}"

    # Determine method
    if [[ $DESC == POST* ]]; then
        METHOD="POST"
    else
        METHOD="GET"
    fi

    # Make request
    if [ "$METHOD" = "POST" ]; then
        HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -X POST "$CONNECTOR_URL$endpoint")
    else
        HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "$CONNECTOR_URL$endpoint")
    fi

    # Analyze response
    case $HTTP_CODE in
        401|403)
            echo -e "${BLUE}[$HTTP_CODE]${NC} $endpoint - ${GREEN}Protected (DAPS validation active)${NC}"
            PROTECTED_COUNT=$((PROTECTED_COUNT + 1))
            ;;
        200|201)
            echo -e "${BLUE}[$HTTP_CODE]${NC} $endpoint - Public endpoint"
            PUBLIC_COUNT=$((PUBLIC_COUNT + 1))
            ;;
        400)
            echo -e "${BLUE}[$HTTP_CODE]${NC} $endpoint - Bad request (endpoint exists)"
            ;;
        404)
            echo -e "${BLUE}[$HTTP_CODE]${NC} $endpoint - Not found"
            ;;
        *)
            echo -e "${BLUE}[$HTTP_CODE]${NC} $endpoint - $DESC"
            ;;
    esac
done

echo ""
echo "Summary:"
echo "  Protected endpoints (401/403): $PROTECTED_COUNT"
echo "  Public endpoints (200): $PUBLIC_COUNT"
echo ""

if [ $PROTECTED_COUNT -gt 0 ]; then
    echo -e "${GREEN}✓ Found protected endpoints - DAPS validation appears to be active!${NC}"
else
    echo -e "${YELLOW}⚠ No protected endpoints found - DAPS validation may not be enforced${NC}"
fi

echo ""
echo ""

# Test the IDS protocol endpoint specifically
echo "=========================================="
echo "Step 3: Testing IDS Protocol Endpoint"
echo "=========================================="
echo ""
echo "The IDS /api/ids/data endpoint is the main protocol endpoint."
echo "Testing with and without proper message format..."
echo ""

# Test 1: Simple request (should fail with 415 or 400/401)
echo "Test 3a: Simple POST (no auth, wrong format)"
IDS_SIMPLE=$(curl -k -s -o /tmp/ids_simple.txt -w "%{http_code}" -X POST "$CONNECTOR_URL/api/ids/data" -H "Content-Type: application/json" -d '{}')
echo "  HTTP Status: $IDS_SIMPLE"

case $IDS_SIMPLE in
    401|403)
        echo -e "  ${GREEN}✓ Authentication required - DAPS validation is enforced!${NC}"
        ;;
    400|415)
        echo -e "  ${BLUE}ℹ Bad request/Unsupported media type - endpoint is active${NC}"
        ;;
    *)
        echo "  Response: $(cat /tmp/ids_simple.txt 2>/dev/null | head -5)"
        ;;
esac

echo ""

# Test 2: Multipart request (proper format but no auth)
echo "Test 3b: Multipart IDS message (no valid DAT token)"
IDS_MULTIPART=$(curl -k -s -w "%{http_code}" -X POST "$CONNECTOR_URL/api/ids/data" \
    -F 'header={"@type":"ids:DescriptionRequestMessage","@id":"test"};type=application/json' \
    2>&1 | tail -1)

echo "  HTTP Status: $IDS_MULTIPART"

# Parse the response to see if it's a rejection message
if [ "$IDS_MULTIPART" = "200" ]; then
    # Check if it's a rejection message
    RESPONSE=$(curl -k -s -X POST "$CONNECTOR_URL/api/ids/data" \
        -F 'header={"@type":"ids:DescriptionRequestMessage","@id":"test"};type=application/json')

    if echo "$RESPONSE" | grep -q "RejectionMessage"; then
        REJECTION_REASON=$(echo "$RESPONSE" | grep -o '"ids:rejectionReason"[^}]*' | head -1)
        echo "  Response: IDS RejectionMessage"
        echo "  Reason: $REJECTION_REASON"

        if echo "$RESPONSE" | grep -q "NOT_AUTHENTICATED\|MALFORMED_MESSAGE"; then
            echo -e "  ${GREEN}✓ Connector is validating IDS messages!${NC}"
        fi
    else
        echo "  Response: $(echo "$RESPONSE" | head -5)"
    fi
fi

echo ""
echo ""

# Check connector logs for DAPS activity
echo "=========================================="
echo "Step 4: Checking Connector Logs"
echo "=========================================="
echo ""
echo "Looking for DAPS validation activity in connector logs..."
echo ""

DAPS_LOGS=$(docker compose logs connector 2>/dev/null | grep -i "daps\|token\|authenticat" | tail -10)

if [ ! -z "$DAPS_LOGS" ]; then
    echo -e "${BLUE}Recent DAPS-related log entries:${NC}"
    echo "$DAPS_LOGS"
    echo ""

    if echo "$DAPS_LOGS" | grep -qi "success\|valid\|verified"; then
        echo -e "${GREEN}✓ Logs show successful DAPS validation!${NC}"
    elif echo "$DAPS_LOGS" | grep -qi "error\|fail\|invalid"; then
        echo -e "${YELLOW}⚠ Logs show DAPS validation errors${NC}"
    fi
else
    echo "No DAPS activity found in recent logs"
fi

echo ""
echo ""

# Final verdict
echo "=========================================="
echo "VALIDATION VERDICT"
echo "=========================================="
echo ""

DAPS_ACTIVE=false
ENDPOINTS_PROTECTED=false

if [ $PROTECTED_COUNT -gt 0 ]; then
    ENDPOINTS_PROTECTED=true
fi

if echo "$DAPS_LOGS" | grep -qi "daps\|token"; then
    DAPS_ACTIVE=true
fi

if $ENDPOINTS_PROTECTED && $DAPS_ACTIVE; then
    echo -e "${GREEN}✓✓✓ DAPS VALIDATION IS ACTIVE ✓✓✓${NC}"
    echo ""
    echo "Evidence:"
    echo "  ✓ Protected endpoints found ($PROTECTED_COUNT endpoints require auth)"
    echo "  ✓ DAPS activity in logs"
    echo "  ✓ Connector is enforcing authentication"
    echo ""
    echo -e "${GREEN}This connector is validating DAPS tokens and is a proper dataspace participant!${NC}"
elif $ENDPOINTS_PROTECTED; then
    echo -e "${BLUE}ℹ DAPS VALIDATION APPEARS ACTIVE${NC}"
    echo ""
    echo "Evidence:"
    echo "  ✓ Protected endpoints found ($PROTECTED_COUNT endpoints require auth)"
    echo "  ? Limited DAPS activity in logs"
    echo ""
    echo "The connector is protecting endpoints, which suggests DAPS validation is configured."
elif $DAPS_ACTIVE; then
    echo -e "${YELLOW}⚠ DAPS CONFIGURED BUT NOT ENFORCED${NC}"
    echo ""
    echo "Evidence:"
    echo "  ✓ DAPS activity in logs"
    echo "  ✗ No protected endpoints found"
    echo ""
    echo "DAPS may be configured but not actively enforcing authentication."
else
    echo -e "${YELLOW}⚠ DAPS VALIDATION STATUS UNCLEAR${NC}"
    echo ""
    echo "Could not confirm DAPS validation is active."
    echo "This might be normal in development mode."
fi

echo ""
echo ""

# How to test with valid authentication
echo "=========================================="
echo "TESTING WITH AUTHENTICATION"
echo "=========================================="
echo ""
echo "To definitively prove DAPS validation is working:"
echo ""
echo "1. Get a valid DAT token from DAPS:"
echo "   You need to register a client in DAPS and request a token"
echo ""
echo "2. Use the token in API calls:"
echo "   curl -k -H 'Authorization: Bearer YOUR_DAT_TOKEN' \\"
echo "     $CONNECTOR_URL/api/offers"
echo ""
echo "3. Expected results:"
echo "   - Without token: 401/403 (Unauthorized)"
echo "   - With invalid token: 403 (Forbidden)"
echo "   - With valid token: 200 (Success)"
echo ""
echo "If this pattern works, DAPS validation is properly configured!"
echo ""

echo "=========================================="
echo "PRACTICAL VERIFICATION"
echo "=========================================="
echo ""
echo "Easiest way to verify DAPS is working:"
echo ""
echo "1. Use the Provider UI: http://localhost:8091"
echo "   - Try to publish a resource"
echo "   - If it works, DAPS validation is functioning"
echo ""
echo "2. Use the Consumer UI: http://localhost:8092"
echo "   - Try to query the broker"
echo "   - If you can see other connectors, DAPS is working"
echo ""
echo "3. Check broker registration:"
echo "   curl -k https://localhost/broker/connectors/"
echo "   - If your connector appears, it successfully authenticated with broker"
echo ""
